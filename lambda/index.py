import json
import os
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import requests
import firebase_admin
from firebase_admin import credentials, db, messaging

AEMET_API_KEY = os.environ.get("AEMET_API_KEY")

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


def _fetch_weather(latitude: float, longitude: float, forecast_days: int) -> dict:
    url = (
        "https://api.open-meteo.com/v1/forecast"
        f"?latitude={latitude}&longitude={longitude}"
        "&hourly=temperature_2m,precipitation_probability,windspeed_10m"
        f"&forecast_days={forecast_days}&timezone=UTC"
    )
    response = requests.get(url, timeout=10)
    response.raise_for_status()
    return response.json()


def _check_alert(alert: dict, weather: dict) -> list[str]:
    """Returns list of threshold messages that are exceeded in the next hour."""
    hourly = weather["hourly"]
    times = hourly["time"]
    temps = hourly["temperature_2m"]
    winds = hourly["windspeed_10m"]
    rains = hourly["precipitation_probability"]

    # Open-Meteo returns times in UTC (timezone=UTC), naive, on the hour
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0, tzinfo=None)

    exceeded_temp = False
    exceeded_wind = False
    exceeded_rain = False

    for i, time_str in enumerate(times):
        hour_dt = datetime.fromisoformat(time_str)
        # Only check the current hour's forecast
        if hour_dt != now:
            continue

        t = float(temps[i]) if temps[i] is not None else 0.0
        w = float(winds[i]) if winds[i] is not None else 0.0
        r = float(rains[i]) if rains[i] is not None else 0.0

        if alert.get("temperatureEnabled", True) and t > alert["temperature"]:
            exceeded_temp = True
        if alert.get("windEnabled", True) and w > alert["wind"]:
            exceeded_wind = True
        if alert.get("rainEnabled", True) and r > alert["rainProbability"]:
            exceeded_rain = True

    parts = []
    if exceeded_temp:
        parts.append(f"Temperatura: >{alert['temperature']:.0f}°C")
    if exceeded_wind:
        parts.append(f"Viento: >{alert['wind']:.0f} km/h")
    if exceeded_rain:
        parts.append(f"Prob. lluvia: >{alert['rainProbability']:.0f}%")
    return parts


def _fetch_weather_aemet(municipio_id: str) -> dict:
    meta = requests.get(
        f"https://opendata.aemet.es/opendata/api/prediccion/especifica/municipio/horaria/{municipio_id}",
        headers={"api_key": AEMET_API_KEY},
        timeout=10,
    )
    meta.raise_for_status()
    data_url = meta.json()["datos"]
    response = requests.get(data_url, timeout=10)
    response.raise_for_status()
    return json.loads(response.content.decode("iso-8859-15"))[0]


def _rain_prob_for_hour(blocks: list[tuple[str, float]], hour: int) -> float:
    for periodo, value in blocks:
        start, end = int(periodo[:2]), int(periodo[2:])
        in_range = hour >= start and hour < end if end > start else hour >= start or hour < end
        if in_range:
            return value
    return 0.0


def _check_alert_aemet(alert: dict, weather: dict) -> list[str]:
    """Returns list of threshold messages exceeded in the current local hour."""
    now = datetime.now(ZoneInfo("Europe/Madrid"))

    for dia in weather["prediccion"]["dia"]:
        fecha = datetime.fromisoformat(dia["fecha"])
        if fecha.date() != now.date():
            continue

        hour_str = f"{now.hour:02d}"
        t = next(
            (float(x["value"]) for x in (dia.get("temperatura") or []) if x["periodo"] == hour_str),
            None,
        )
        w = next(
            (
                float(x["velocidad"][0])
                for x in (dia.get("vientoAndRachaMax") or [])
                if isinstance(x, dict) and "velocidad" in x and x["periodo"] == hour_str
            ),
            None,
        )
        rain_blocks = [
            (x["periodo"], float(x["value"]))
            for x in (dia.get("probPrecipitacion") or [])
            if x.get("periodo") and x.get("value") is not None
        ]
        r = _rain_prob_for_hour(rain_blocks, now.hour)

        exceeded_temp = alert.get("temperatureEnabled", True) and t is not None and t > alert["temperature"]
        exceeded_wind = alert.get("windEnabled", True) and w is not None and w > alert["wind"]
        exceeded_rain = alert.get("rainEnabled", True) and r > alert["rainProbability"]

        parts = []
        if exceeded_temp:
            parts.append(f"Temperatura: >{alert['temperature']:.0f}°C")
        if exceeded_wind:
            parts.append(f"Viento: >{alert['wind']:.0f} km/h")
        if exceeded_rain:
            parts.append(f"Prob. lluvia: >{alert['rainProbability']:.0f}%")
        return parts

    return []


def handler(event, context):
    _get_app()

    users_ref = db.reference("users")
    users_snapshot = users_ref.get()

    if not users_snapshot:
        print("No users found")
        return {"statusCode": 200, "body": "No users"}

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

        for alert in alerts:
            provider = alert.get("provider", "openMeteo")

            try:
                if provider == "aemet":
                    municipio_id = alert.get("aemetMunicipioId")
                    if not municipio_id or not AEMET_API_KEY:
                        continue
                    weather = _fetch_weather_aemet(municipio_id)
                    parts = _check_alert_aemet(alert, weather)
                else:
                    lat = alert.get("latitude")
                    lon = alert.get("longitude")
                    if lat is None or lon is None:
                        continue
                    weather = _fetch_weather(lat, lon, alert.get("forecastDays", 1))
                    parts = _check_alert(alert, weather)
            except Exception as e:
                print(f"Error fetching weather for user {uid}, city {alert.get('city')}: {e}")
                continue

            if not parts:
                continue

            provider_label = "AEMET OpenData" if provider == "aemet" else "Open-Meteo"

            try:
                message = messaging.Message(
                    notification=messaging.Notification(
                        title=f"{alert['city']} ({provider_label})",
                        body="\n".join(parts),
                    ),
                    token=fcm_token,
                )
                messaging.send(message)
                notifications_sent += 1
                print(f"Notification sent to user {uid} for {alert['city']}: {parts}")
            except Exception as e:
                print(f"Error sending notification to user {uid}: {e}")

    return {
        "statusCode": 200,
        "body": f"Done. Notifications sent: {notifications_sent}",
    }
