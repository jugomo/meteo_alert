from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import requests
import firebase_admin
from firebase_admin import credentials, db, messaging

AEMET_API_KEY = os.environ.get("AEMET_API_KEY")
AEMET_TZ = ZoneInfo("Europe/Madrid")

MAX_LEAD_HOURS = 24
DIGEST_HOURS = 24
# Today + tomorrow always covers [now, now + 24h], which is the widest window
# needed by both lead-time alerts and the daily digest.
OPEN_METEO_FORECAST_DAYS = 2
# Caps the alerts processed per user so a single account can't exhaust the
# Open-Meteo/AEMET quotas or the Lambda timeout for everyone else.
MAX_ALERTS_PER_USER = 20

# Firebase Admin SDK init — credentials come from FIREBASE_SERVICE_ACCOUNT env var (JSON string)
_app = None

def _get_app():
    global _app
    if _app is None:
        sa = json.loads(os.environ["FIREBASE_SERVICE_ACCOUNT"])
        cred = credentials.Certificate(sa)
        _app = firebase_admin.initialize_app(cred, {
            "databaseURL": os.environ["FIREBASE_DATABASE_URL"],
        })
    return _app


# ── Forecast model ────────────────────────────────────────────────────────────

@dataclass
class Hour:
    time: datetime          # naive, local time of the forecast location, on the hour
    temperature: float | None
    wind: float | None
    rain: float | None


@dataclass
class Forecast:
    now: datetime           # current hour, naive, same timezone as Hour.time
    hours: list[Hour]


@dataclass
class Episode:
    start: datetime
    end: datetime           # last hour included (the episode lasts until end + 1h)
    variables: set[str] = field(default_factory=set)

    def hour_keys(self) -> list[str]:
        keys, t = [], self.start
        while t <= self.end:
            keys.append(_hour_key(t))
            t += timedelta(hours=1)
        return keys


def _hour_key(t: datetime) -> str:
    return t.strftime("%Y-%m-%dT%H:00")


# ── Providers ─────────────────────────────────────────────────────────────────

def _fetch_open_meteo(latitude: float, longitude: float) -> Forecast:
    url = (
        "https://api.open-meteo.com/v1/forecast"
        f"?latitude={latitude}&longitude={longitude}"
        "&hourly=temperature_2m,precipitation_probability,windspeed_10m"
        f"&forecast_days={OPEN_METEO_FORECAST_DAYS}&timezone=auto"
    )
    response = requests.get(url, timeout=10)
    response.raise_for_status()
    data = response.json()

    # With timezone=auto Open-Meteo returns naive local times of the location
    tz = ZoneInfo(data["timezone"])
    now = datetime.now(tz).replace(minute=0, second=0, microsecond=0, tzinfo=None)

    hourly = data["hourly"]
    hours = [
        Hour(
            time=datetime.fromisoformat(t),
            temperature=_to_float(hourly["temperature_2m"][i]),
            wind=_to_float(hourly["windspeed_10m"][i]),
            rain=_to_float(hourly["precipitation_probability"][i]),
        )
        for i, t in enumerate(hourly["time"])
    ]
    return Forecast(now=now, hours=hours)


def _fetch_aemet(municipio_id: str) -> Forecast:
    meta = requests.get(
        f"https://opendata.aemet.es/opendata/api/prediccion/especifica/municipio/horaria/{municipio_id}",
        headers={"api_key": AEMET_API_KEY},
        timeout=10,
    )
    meta.raise_for_status()
    data_url = meta.json()["datos"]
    response = requests.get(data_url, timeout=10)
    response.raise_for_status()
    data = json.loads(response.content.decode("iso-8859-15"))[0]

    now = datetime.now(AEMET_TZ).replace(minute=0, second=0, microsecond=0, tzinfo=None)

    hours = []
    for dia in data["prediccion"]["dia"]:
        fecha = datetime.fromisoformat(dia["fecha"]).replace(hour=0, minute=0, second=0, tzinfo=None)
        temps = {x["periodo"]: _to_float(x.get("value")) for x in (dia.get("temperatura") or [])}
        winds = {
            x["periodo"]: _to_float(x["velocidad"][0])
            for x in (dia.get("vientoAndRachaMax") or [])
            if isinstance(x, dict) and x.get("velocidad") and x.get("periodo")
        }
        # Rain probability comes in 6-hour blocks ("0208", "0814", ...)
        rain_blocks = [
            (x["periodo"], float(x["value"]))
            for x in (dia.get("probPrecipitacion") or [])
            if x.get("periodo") and x.get("value") not in (None, "")
        ]
        for h in range(24):
            hh = f"{h:02d}"
            if hh not in temps and hh not in winds:
                continue  # hour not covered by the hourly forecast
            hours.append(Hour(
                time=fecha + timedelta(hours=h),
                temperature=temps.get(hh),
                wind=winds.get(hh),
                rain=_rain_prob_for_hour(rain_blocks, h),
            ))
    return Forecast(now=now, hours=hours)


def _rain_prob_for_hour(blocks: list[tuple[str, float]], hour: int) -> float | None:
    for periodo, value in blocks:
        start, end = int(periodo[:2]), int(periodo[2:])
        in_range = start <= hour < end if end > start else hour >= start or hour < end
        if in_range:
            return value
    return None


def _to_float(v) -> float | None:
    try:
        return float(v) if v not in (None, "") else None
    except (TypeError, ValueError):
        return None


# ── Alert evaluation ──────────────────────────────────────────────────────────

def _temperature_below(alert: dict) -> bool:
    return alert.get("temperatureDirection") == "below"


def _exceeded_variables(alert: dict, h: Hour) -> set[str]:
    out = set()
    if alert.get("temperatureEnabled", True) and h.temperature is not None:
        threshold = alert["temperature"]
        if (h.temperature < threshold) if _temperature_below(alert) else (h.temperature > threshold):
            out.add("temperature")
    if alert.get("windEnabled", True) and h.wind is not None and h.wind > alert["wind"]:
        out.add("wind")
    if alert.get("rainEnabled", True) and h.rain is not None and h.rain > alert["rainProbability"]:
        out.add("rain")
    return out


def _episodes(alert: dict, forecast: Forecast, window_hours: int) -> list[Episode]:
    """Groups consecutive exceeding hours into episodes.

    Only episodes that start inside [now, now + window_hours] are returned, but each one
    is extended past the window with the rest of the forecast so its real end is known.
    """
    window_end = forecast.now + timedelta(hours=window_hours)
    hours = sorted((h for h in forecast.hours if h.time >= forecast.now), key=lambda h: h.time)

    episodes: list[Episode] = []
    current: Episode | None = None
    for h in hours:
        exceeded = _exceeded_variables(alert, h)
        contiguous = current is not None and h.time == current.end + timedelta(hours=1)
        if exceeded and contiguous:
            current.end = h.time
            current.variables |= exceeded
        elif exceeded:
            if h.time > window_end:
                break
            current = Episode(start=h.time, end=h.time, variables=set(exceeded))
            episodes.append(current)
        else:
            current = None
            if h.time > window_end:
                break
    return episodes


VARIABLE_ORDER = ["temperature", "wind", "rain"]


def _variable_label(alert: dict, var: str) -> str:
    if var == "temperature":
        symbol = "<" if _temperature_below(alert) else ">"
        return f"Temperatura: {symbol}{alert['temperature']:.0f}°C"
    if var == "wind":
        return f"Viento: >{alert['wind']:.0f} km/h"
    return f"Prob. lluvia: >{alert['rainProbability']:.0f}%"


def _variable_short(var: str) -> str:
    return {"temperature": "temperatura", "wind": "viento", "rain": "lluvia"}[var]


def _day_prefix(t: datetime, now: datetime) -> str:
    if t.date() == now.date():
        return ""
    if t.date() == now.date() + timedelta(days=1):
        return "mañana "
    return f"{t:%d/%m} "


def _format_range(ep: Episode, now: datetime) -> str:
    # The episode covers [start, end + 1h). An end at midnight is shown as 24:00 of the
    # last day included, so "18:00–24:00" never reads as a 6-hour range ending today.
    end = ep.end + timedelta(hours=1)
    end_label = "24:00" if end.hour == 0 else f"{end:%H:%M}"
    start_str = f"{_day_prefix(ep.start, now)}{ep.start:%H:%M}"
    end_prefix = _day_prefix(ep.end, now) if ep.end.date() != ep.start.date() else ""
    return f"{start_str}–{end_prefix}{end_label}"


def _lead_notification(alert: dict, ep: Episode, now: datetime) -> str:
    lead = int((ep.start - now).total_seconds() // 3600)
    when = "ahora" if lead == 0 else f"en {lead} h"
    lines = [f"Previsión {_format_range(ep, now)} ({when})"]
    lines += [_variable_label(alert, v) for v in VARIABLE_ORDER if v in ep.variables]
    return "\n".join(lines)


def _digest_notification(alert: dict, episodes: list[Episode], now: datetime) -> str:
    if not episodes:
        return "Sin umbrales superados en las próximas 24 h ✅"
    lines = []
    for ep in episodes:
        vars_ = ", ".join(_variable_short(v) for v in VARIABLE_ORDER if v in ep.variables)
        lines.append(f"{_format_range(ep, now)}: {vars_}")
    return "\n".join(lines)


def _alert_key(alert: dict) -> str:
    """Stable key for the per-alert notification state in Firebase."""
    if alert.get("id"):
        return str(alert["id"])
    # Legacy alerts (created by app versions without ids): hash the whole alert so two
    # alerts for the same city with different thresholds don't share state. Editing the
    # alert changes the key, which at worst repeats one notification.
    raw = json.dumps(alert, sort_keys=True)
    return "legacy_" + hashlib.sha1(raw.encode()).hexdigest()[:16]


def _process_alert(alert: dict, forecast: Forecast, state: dict) -> tuple[list[tuple[str, str]], dict]:
    """Returns (notifications as (title_suffix, body), new state for this alert)."""
    now = forecast.now
    now_key = _hour_key(now)
    notified_hours = {h for h in state.get("hours", []) if h >= now_key}
    last_digest = state.get("lastDigest")
    notifications = []

    # B: lead-time alerts — one notification per episode
    lead = max(0, min(int(alert.get("leadHours", 0) or 0), MAX_LEAD_HOURS))
    for ep in _episodes(alert, forecast, lead):
        keys = ep.hour_keys()
        if not notified_hours.intersection(keys):
            notifications.append(("", _lead_notification(alert, ep, now)))
        # Track every hour of the episode so that if the forecast later shifts or
        # extends it, it is still recognised as the same episode.
        notified_hours.update(keys)

    # C: daily digest at the alert's chosen local hour
    today = now.date().isoformat()
    if alert.get("digestEnabled") and now.hour == int(alert.get("digestHour", 8)) and last_digest != today:
        episodes = _episodes(alert, forecast, DIGEST_HOURS - 1)
        notifications.append((" · resumen 24 h", _digest_notification(alert, episodes, now)))
        last_digest = today

    new_state = {}
    if notified_hours:
        new_state["hours"] = sorted(notified_hours)
    if last_digest:
        new_state["lastDigest"] = last_digest
    return notifications, new_state


# ── Handler ───────────────────────────────────────────────────────────────────

def _forecast_source(alert: dict) -> tuple | None:
    """Cache key identifying the forecast an alert needs (shared across users)."""
    if alert.get("provider", "openMeteo") == "aemet":
        mid = alert.get("aemetMunicipioId")
        return ("aemet", mid) if mid and AEMET_API_KEY else None
    lat, lon = alert.get("latitude"), alert.get("longitude")
    if lat is None or lon is None:
        return None
    return ("openMeteo", round(float(lat), 4), round(float(lon), 4))


def _get_forecast(source: tuple, cache: dict) -> Forecast | None:
    if source not in cache:
        try:
            if source[0] == "aemet":
                cache[source] = _fetch_aemet(source[1])
            else:
                cache[source] = _fetch_open_meteo(source[1], source[2])
        except Exception as e:
            print(f"Error fetching forecast {source}: {e}")
            cache[source] = None  # don't retry the same source in this run
    return cache[source]


def _remove_stale_token(uid: str, stale_token: str) -> None:
    """Deletes an FCM token that FCM reports as no longer registered (app
    uninstalled, data cleared...). Uses a transaction so a fresh token the app
    wrote since the users snapshot was read is never wiped."""
    try:
        db.reference(f"users/{uid}/fcmToken").transaction(
            lambda current: None if current == stale_token else current
        )
        print(f"Removed unregistered FCM token for user {uid}")
    except Exception as e:
        print(f"Error removing FCM token for user {uid}: {e}")


def handler(event, context):
    _get_app()

    users_snapshot = db.reference("users").get()
    if not users_snapshot:
        print("No users found")
        return {"statusCode": 200, "body": "No users"}

    forecast_cache: dict = {}
    notifications_sent = 0

    for uid, user_data in users_snapshot.items():
        fcm_token = user_data.get("fcmToken")
        alerts_json_str = user_data.get("alertsJson")

        if not fcm_token or not alerts_json_str:
            continue

        try:
            alerts = json.loads(alerts_json_str)
        except (json.JSONDecodeError, TypeError):
            print(f"Invalid alertsJson for user {uid}")
            continue
        if not isinstance(alerts, list):
            print(f"Invalid alertsJson for user {uid}: not a list")
            continue
        if len(alerts) > MAX_ALERTS_PER_USER:
            print(f"User {uid} has {len(alerts)} alerts, only the first {MAX_ALERTS_PER_USER} are processed")
            alerts = alerts[:MAX_ALERTS_PER_USER]

        old_state = user_data.get("notified") or {}
        new_state = {}

        for alert in alerts:
            key = _alert_key(alert)
            source = _forecast_source(alert)
            forecast = _get_forecast(source, forecast_cache) if source else None
            if forecast is None:
                # Keep previous state so a transient error doesn't cause duplicates later
                if key in old_state:
                    new_state[key] = old_state[key]
                continue

            notifications, alert_state = _process_alert(alert, forecast, old_state.get(key) or {})
            if alert_state:
                new_state[key] = alert_state

            provider_label = "AEMET OpenData" if alert.get("provider") == "aemet" else "Open-Meteo"
            for title_suffix, body in notifications:
                if fcm_token is None:
                    break
                try:
                    messaging.send(messaging.Message(
                        notification=messaging.Notification(
                            title=f"{alert['city']} ({provider_label}){title_suffix}",
                            body=body,
                        ),
                        token=fcm_token,
                    ))
                    notifications_sent += 1
                    print(f"Notification sent to user {uid} for {alert['city']}: {body!r}")
                except messaging.UnregisteredError:
                    _remove_stale_token(uid, fcm_token)
                    fcm_token = None
                except Exception as e:
                    print(f"Error sending notification to user {uid}: {e}")

        # Alerts that were deleted drop out of new_state, which prunes their state too
        if new_state != old_state:
            db.reference(f"users/{uid}/notified").set(new_state or None)

    print(f"Forecasts fetched: {len(forecast_cache)}")
    return {
        "statusCode": 200,
        "body": f"Done. Notifications sent: {notifications_sent}",
    }
