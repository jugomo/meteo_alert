# Meteo Alert

Monorepo with a Flutter app and an AWS Lambda microservice that together monitor weather forecasts and notify users when wind speed, temperature, or rain probability thresholds are about to be exceeded.

## Repository structure

```
meteo_alert/
├── app/        # Flutter application
└── lambda/     # AWS Lambda microservice (server-side alert checker)
```

## Overall architecture

```
┌──────────────────────────┐                   ┌───────────────────────┐
│     Flutter app          │                   │     AWS Lambda        │
│       (app/)             │                   │      (lambda/)        │
│                          │                   │                       │
│  local alert checks      │                   │  hourly EventBridge   │
│  + push notification UI  │                   │  cron → checks alerts │
└───────────┬──────────────┘                   └────────────┬──────────┘
            │                                               │
            │ read/write alerts                             │ read alerts
            │ register FCM token                            │ send FCM push
            ▼                                               ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     Firebase (Auth · RTDB · FCM)                       │
└────────────────────────────────────────────────────────────────────────┘
            ▲                                                 ▲
            │            forecast + geocoding (per-alert      │
            │            provider: Open-Meteo or AEMET)       │
            └────────────────────────┬────────────────────────┘
                                     ▼
                     ┌─────────────────────────────────────┐
                     │  Open-Meteo API  ·  AEMET OpenData  │
                     └─────────────────────────────────────┘
```

The app and the Lambda both read/write alerts in Firebase RTDB and independently query whichever weather provider each alert was created with; the Lambda is what makes alerts fire even when the app is closed, by pushing notifications through FCM.

### Weather providers

Each alert stores its own `provider` (`openMeteo` or `aemet`), chosen when creating or editing the alert, so the app and the Lambda always agree on where to fetch that alert's forecast from:

| | Open-Meteo | AEMET OpenData |
|---|---|---|
| Coverage | Worldwide | Spain only |
| Location lookup | Free-text geocoding API | Local municipios (INE) catalog bundled with the app — `app/assets/aemet_municipios.json` |
| Auth | None | Personal API key (free, requested at [opendata.aemet.es](https://opendata.aemet.es)) |
| Forecast horizon | Up to the alert's configured days | Capped at 3 days (AEMET's own limit) |

AEMET requires a personal API key that must **not** be committed. If it's missing, the app disables the AEMET option in the alert creation/edit sheet ("No disponible actualmente") and the Lambda silently skips AEMET-provider alerts. See [AEMET key setup](#aemet-key-setup-both-app-and-lambda) below.

---

## Flutter app (`app/`)

### Features

- **Authentication** — sign in with Firebase Auth; alerts are tied to the authenticated user.
- **Multiple alerts** — each alert is displayed as an independent tab.
- **Configurable thresholds** — enable or disable wind (km/h), temperature (°C), and rain probability (%) independently.
- **Hourly forecast** — queries [Open-Meteo](https://open-meteo.com) or [AEMET OpenData](https://opendata.aemet.es) (selectable per alert, when creating or editing it) and lists only the hours where a threshold is exceeded, grouped by day.
- **Automatic geocoding** — city suggestions appear in real time while typing; coordinates are resolved before saving the alert (via Open-Meteo's geocoder or the local AEMET municipios catalog, depending on the selected provider).
- **Cloud persistence** — alerts are stored in Firebase Realtime Database and synced across devices.
- **Local persistence** — alerts are also cached in `SharedPreferences` and restored on next launch.
- **Pull-to-refresh** — swipe down on the detail view to refresh the forecast.
- **Push notifications** — local notification fired when any threshold will be exceeded in the next hour; server-side FCM push notifications sent by the Lambda microservice. Both title the notification with the city and forecast provider, e.g. `Madrid (AEMET OpenData)`.
- **Dark / light mode** — theme preference toggled from the settings screen and persisted locally.
- **Settings screen** — dark mode switch, local/push notification toggles, sign-out and delete-account actions, and an About tab with app and API info.

### Project structure

```
app/
├── pubspec.yaml
├── assets/
│   ├── aemet_municipios.json              # AEMET municipios (INE) catalog — name, id, lat/lon (tracked)
│   └── aemet_key.txt                      # AEMET OpenData API key (gitignored, not in repo)
└── lib/
    ├── main.dart                             # Entry point
    ├── app.dart                              # MaterialApp + FCM token registration
    ├── firebase_options.dart                 # Generated Firebase configuration
    ├── core/
    │   ├── alert_checker.dart                # Checks forecasts and triggers local notifications
    │   ├── aemet_config.dart                 # Loads the AEMET API key asset; disables AEMET if absent
    │   ├── weather_provider_prefs.dart       # ValueNotifier<WeatherProvider> with SharedPreferences
    │   ├── notification_service.dart         # Conditional export (native / web)
    │   ├── notification_service_native.dart  # flutter_local_notifications implementation
    │   ├── notification_service_web.dart     # Web Notification API implementation
    │   ├── theme_notifier.dart               # ValueNotifier<ThemeMode> with SharedPreferences
    │   └── constants/
    │       └── countries.dart                # Country list and ISO codes
    ├── data/
    │   ├── aemet_municipios_catalog.dart     # Offline search over the bundled AEMET municipios catalog
    │   ├── models/
    │   │   ├── alert.dart                    # Alert model + WeatherProvider enum, JSON serialization
    │   │   ├── forecast_hour.dart            # Forecast hour with exceeded values
    │   │   └── city_suggestion.dart          # Geocoding / municipio suggestion
    │   └── repositories/
    │       ├── alert_repository.dart         # Firebase RTDB persistence
    │       ├── auth_repository.dart          # Firebase Auth (sign in / sign out)
    │       ├── weather_repository.dart       # Open-Meteo API (forecast + geocoding); delegates to AEMET below
    │       └── aemet_weather_repository.dart # AEMET OpenData API (hourly forecast by municipio)
    └── presentation/
        ├── screens/
        │   ├── home_screen.dart              # Main screen with TabBar
        │   ├── settings_screen.dart          # Dark mode, notifications, sign out, delete account, About
        │   └── auth_screen.dart              # Login / registration screen
        └── widgets/
            ├── alert_detail_view.dart        # Forecast view per alert
            ├── create_alert_sheet.dart       # Bottom sheet to create/edit an alert, incl. provider picker
            ├── summary_chip.dart             # Threshold summary chip
            ├── hour_tile.dart                # Hourly row with exceeded values
            └── value_chip.dart               # Individual colored value chip
```

### External APIs

| Service | Purpose | Auth |
|---|---|---|
| `api.open-meteo.com/v1/forecast` | Hourly forecast (temperature, wind, rain) | None |
| `geocoding-api.open-meteo.com/v1/search` | City autocomplete and geocoding | None |
| `opendata.aemet.es/opendata/api/prediccion/especifica/municipio/horaria/{id}` | Hourly forecast for a Spanish municipio (id = INE code) | `api_key` — see [AEMET key setup](#aemet-key-setup-both-app-and-lambda). Sent as a query param from the Flutter app (a header would force a CORS preflight on web, which AEMET's server doesn't answer) and as a header from the Lambda (plain server-to-server call, no CORS involved) |

Open-Meteo is free and requires no API key. AEMET OpenData is also free but requires a personal API key; city lookup for AEMET doesn't hit a network API at all — it searches the bundled `assets/aemet_municipios.json` catalog locally.

### Main dependencies

| Package | Purpose |
|---|---|
| `http` | Requests to Open-Meteo APIs |
| `shared_preferences` | Local alert persistence and theme preference |
| `firebase_core` | Firebase initialization |
| `firebase_auth` | User authentication |
| `firebase_database` | Cloud alert storage (Realtime Database) |
| `firebase_messaging` | FCM token registration for server-side push notifications |
| `flutter_local_notifications` | Local push notifications (native platforms) |
| `web` | Web Notification API access (web platform) |

### Getting started

#### Prerequisites

- Flutter 3.x / Dart 3.x
- A [Firebase](https://console.firebase.google.com) project with **Authentication** (Email/Password), **Realtime Database**, and **Cloud Messaging** enabled
- [FlutterFire CLI](https://pub.dev/packages/flutterfire_cli): `dart pub global activate flutterfire_cli`

#### Firebase setup

The following files are excluded from version control because they contain project credentials:

| File | Platform |
|---|---|
| `app/android/app/google-services.json` | Android |
| `app/ios/Runner/GoogleService-Info.plist` | iOS |
| `app/macos/Runner/GoogleService-Info.plist` | macOS |
| `app/lib/firebase_options.dart` | All (generated) |

After cloning, run from the `app/` directory:

```bash
flutterfire configure --project=<your-firebase-project-id>
```

#### AEMET key setup (both app and Lambda)

AEMET OpenData is optional — the app and Lambda work fine with only Open-Meteo. To enable it:

1. Request a free API key at [opendata.aemet.es/centrodedescargas/altaUsuario](https://opendata.aemet.es/centrodedescargas/altaUsuario).
2. For the app: save the key (just the raw token, no quotes/newlines) as `app/assets/aemet_key.txt`.
3. For the Lambda: save the same key as `lambda/aemet-api-key.txt`.

Both files are gitignored and must never be committed. If either is missing, that side simply treats AEMET as unavailable — the app disables the option in the alert creation/edit sheet, and the Lambda skips AEMET-provider alerts without failing.

#### Run

```bash
cd app
flutter pub get
flutter run
```

---

## Lambda microservice (`lambda/`)

A serverless function that runs every hour on AWS, checks all user alerts against their chosen forecast provider (Open-Meteo or AEMET), and sends FCM push notifications when any threshold is exceeded.

### Architecture

```
EventBridge (cron: every hour, on the hour, UTC)
        │
        ▼
  AWS Lambda (Python)
        │
        ├── Firebase RTDB      →  read all users + alerts + FCM tokens
        ├── Open-Meteo API     →  fetch hourly forecast (alerts with provider = openMeteo)
        ├── AEMET OpenData API →  fetch hourly forecast by municipio id (provider = aemet)
        └── Firebase FCM       →  send push notification if threshold exceeded
```

Each alert's `provider` field (set when the alert is created or edited in the app) decides which branch runs; AEMET-provider alerts are skipped if `AEMET_API_KEY` isn't configured (see [AEMET key setup](#aemet-key-setup-both-app-and-lambda)).

### AWS free tier cost

| Service | Free tier | Usage |
|---|---|---|
| Lambda invocations | 1 M / month | 24 × 30 = **720 / month** |
| Lambda compute | 400 000 GB-s / month | ~117 GB-s / month (256 MB, ~0.65 s avg duration) |
| EventBridge scheduled rule | Free | 1 rule |

**Total: $0 / month.** This is a tiny fraction of the Lambda "Always Free" tier, which never expires (unlike the 12-month trial that covers services like EC2 or RDS). Firebase credentials are stored as a Lambda environment variable — no Secrets Manager needed.

### Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- Python 3.x and pip3
- Firebase service account JSON (see below)
- (Optional) AEMET OpenData API key, as `lambda/aemet-api-key.txt` — see [AEMET key setup](#aemet-key-setup-both-app-and-lambda). Without it, AEMET-provider alerts are silently skipped.

#### Configure AWS CLI

```bash
# Install (macOS)
brew install awscli

# Configure with your IAM credentials
aws configure
# AWS Access Key ID:     <from AWS Console → IAM → Users → Security credentials>
# AWS Secret Access Key: <same>
# Default region name:   eu-west-1   (or your preferred region)
# Default output format: json
```

#### Get Firebase service account

1. Firebase Console → Project settings → Service accounts
2. Click **Generate new private key**
3. Save the downloaded JSON as `lambda/firebase-service-account.json`

> This file is in `.gitignore` and must never be committed.

### Deploy

```bash
cd lambda
./deploy.sh
```

The script handles everything on first run and subsequent updates:

1. Installs Python dependencies into a build directory
2. Packages `index.py` + dependencies into `function.zip`
3. Creates the IAM execution role (`meteo-alert-lambda-role`) if it does not exist
4. Creates or updates the Lambda function (`meteo-alert-checker`) with the Firebase credentials and the AEMET API key (if `aemet-api-key.txt` exists) as environment variables
5. Creates or updates the EventBridge rule (`meteo-alert-hourly`, `cron(0 * * * ? *)`) so it fires every hour on the hour (UTC) — reconciled on every deploy, even if the rule already exists
6. Wires the rule to the Lambda function

### Test and logs

```bash
# Invoke manually
aws lambda invoke --function-name meteo-alert-checker --region eu-west-1 /tmp/out.json && cat /tmp/out.json

# Stream logs
aws logs tail /aws/lambda/meteo-alert-checker --follow --region eu-west-1

# Inspect the EventBridge schedule (rate vs cron, enabled/disabled)
aws events describe-rule --name meteo-alert-hourly --region eu-west-1

# List recent invocations (useful to check actual execution times / offset)
aws logs describe-log-streams --log-group-name /aws/lambda/meteo-alert-checker \
  --region eu-west-1 --order-by LastEventTime --descending --max-items 5

# Average / max duration over the last 30 days (for free tier estimates)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda --metric-name Duration \
  --dimensions Name=FunctionName,Value=meteo-alert-checker \
  --start-time "$(date -u -v-30d '+%Y-%m-%dT%H:%M:%S')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%S')" \
  --period 2592000 --statistics Average Maximum SampleCount \
  --region eu-west-1

# Dump current users + alerts from Firebase RTDB (needs: pip3 install firebase_admin)
cd lambda && python3 -c "
import firebase_admin
from firebase_admin import credentials, db
cred = credentials.Certificate('firebase-service-account.json')
firebase_admin.initialize_app(cred, {'databaseURL': 'https://meteo-alert-409a8-default-rtdb.europe-west1.firebasedatabase.app'})
users = db.reference('users').get()
for uid, data in (users or {}).items():
    print(uid, 'fcmToken:', bool(data.get('fcmToken')), data.get('alertsJson'))
"
```
