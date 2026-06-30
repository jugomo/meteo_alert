# Meteo Alert

Flutter app that monitors weather forecasts and notifies when wind speed, temperature, or rain probability thresholds are about to be exceeded.

## Repository structure

```
meteo_alert/
├── app/        # Flutter application
└── lambda/     # AWS Lambda microservice (server-side alert checker)
```

---

## Flutter app (`app/`)

### Features

- **Authentication** — sign in with Firebase Auth; alerts are tied to the authenticated user.
- **Multiple alerts** — each alert is displayed as an independent tab.
- **Configurable thresholds** — enable or disable wind (km/h), temperature (°C), and rain probability (%) independently.
- **Hourly forecast** — queries the [Open-Meteo](https://open-meteo.com) API and lists only the hours where a threshold is exceeded, grouped by day.
- **Automatic geocoding** — city suggestions appear in real time while typing; coordinates are resolved before saving the alert.
- **Cloud persistence** — alerts are stored in Firebase Realtime Database and synced across devices.
- **Local persistence** — alerts are also cached in `SharedPreferences` and restored on next launch.
- **Pull-to-refresh** — swipe down on the detail view to refresh the forecast.
- **Push notifications** — local notification fired when any threshold will be exceeded in the next hour; server-side FCM push notifications sent by the Lambda microservice.
- **Dark / light mode** — theme preference toggled from the settings screen and persisted locally.
- **Settings screen** — dark mode switch, sign-out action, and an About tab with app and API info.

### Project structure

```
app/
├── pubspec.yaml
└── lib/
    ├── main.dart                             # Entry point
    ├── app.dart                              # MaterialApp + FCM token registration
    ├── firebase_options.dart                 # Generated Firebase configuration
    ├── core/
    │   ├── alert_checker.dart                # Checks forecasts and triggers local notifications
    │   ├── notification_service.dart         # Conditional export (native / web)
    │   ├── notification_service_native.dart  # flutter_local_notifications implementation
    │   ├── notification_service_web.dart     # Web Notification API implementation
    │   ├── theme_notifier.dart               # ValueNotifier<ThemeMode> with SharedPreferences
    │   └── constants/
    │       └── countries.dart                # Country list and ISO codes
    ├── data/
    │   ├── models/
    │   │   ├── alert.dart                    # Alert model with JSON serialization
    │   │   ├── forecast_hour.dart            # Forecast hour with exceeded values
    │   │   └── city_suggestion.dart          # Geocoding suggestion
    │   └── repositories/
    │       ├── alert_repository.dart         # Firebase RTDB persistence
    │       ├── auth_repository.dart          # Firebase Auth (sign in / sign out)
    │       └── weather_repository.dart       # Open-Meteo API (forecast + geocoding)
    └── presentation/
        ├── screens/
        │   ├── home_screen.dart              # Main screen with TabBar
        │   ├── settings_screen.dart          # Dark mode, sign out, About
        │   └── auth_screen.dart              # Login / registration screen
        └── widgets/
            ├── alert_detail_view.dart        # Forecast view per alert
            ├── create_alert_sheet.dart       # Bottom sheet to create/edit an alert
            ├── summary_chip.dart             # Threshold summary chip
            ├── hour_tile.dart                # Hourly row with exceeded values
            └── value_chip.dart               # Individual colored value chip
```

### External APIs

| Service | Purpose |
|---|---|
| `api.open-meteo.com/v1/forecast` | Hourly forecast (temperature, wind, rain) |
| `geocoding-api.open-meteo.com/v1/search` | City autocomplete and geocoding |

Both APIs are free and require no API key.

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

#### Run

```bash
cd app
flutter pub get
flutter run
```

---

## Lambda microservice (`lambda/`)

A serverless function that runs every hour on AWS, checks all user alerts against the Open-Meteo forecast, and sends FCM push notifications when any threshold is exceeded.

### Architecture

```
EventBridge (cron: every 1h)
        │
        ▼
  AWS Lambda (Python)
        │
        ├── Firebase RTDB  →  read all users + alerts + FCM tokens
        ├── Open-Meteo API →  fetch hourly forecast per location
        └── Firebase FCM   →  send push notification if threshold exceeded
```

### AWS free tier cost

| Service | Free tier | Usage |
|---|---|---|
| Lambda invocations | 1 M / month | 24 × 30 = **720 / month** |
| Lambda compute | 400 000 GB-s / month | ~1 800 GB-s / month |
| EventBridge scheduled rule | Free | 1 rule |

**Total: $0 / month.** Firebase credentials are stored as a Lambda environment variable — no Secrets Manager needed.

### Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- Python 3.x and pip3
- Firebase service account JSON (see below)

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
4. Creates or updates the Lambda function (`meteo-alert-checker`) with the Firebase credentials as environment variables
5. Creates the EventBridge rule (`meteo-alert-hourly`) that triggers every hour
6. Wires the rule to the Lambda function

### Test and logs

```bash
# Invoke manually
aws lambda invoke --function-name meteo-alert-checker --region eu-west-1 /tmp/out.json && cat /tmp/out.json

# Stream logs
aws logs tail /aws/lambda/meteo-alert-checker --follow --region eu-west-1

# See detail
aws events describe-rule --name "meteo-alert-hourly" --region "${AWS_DEFAULT_REGION:-eu-west-1}" 2>&1
```
