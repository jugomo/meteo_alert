import json
import os
from datetime import datetime, timezone

import requests
import firebase_admin
from firebase_admin import credentials, db, messaging

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
            lat = alert.get("latitude")
            lon = alert.get("longitude")
            if lat is None or lon is None:
                continue

            try:
                weather = _fetch_weather(lat, lon, alert.get("forecastDays", 1))
                parts = _check_alert(alert, weather)
            except Exception as e:
                print(f"Error fetching weather for user {uid}, city {alert.get('city')}: {e}")
                continue

            if not parts:
                continue

            try:
                message = messaging.Message(
                    notification=messaging.Notification(
                        title=alert["city"],
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
