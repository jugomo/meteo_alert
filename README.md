# Meteo Alert

Flutter app that monitors weather forecasts and notifies when wind speed, temperature, or rain probability thresholds are about to be exceeded.

## Features

- **Authentication** — sign in with Firebase Auth; alerts are tied to the authenticated user.
- **Multiple alerts** — each alert is displayed as an independent tab.
- **Configurable thresholds** — enable or disable wind (km/h), temperature (°C), and rain probability (%) independently.
- **Hourly forecast** — queries the [Open-Meteo](https://open-meteo.com) API and lists only the hours where a threshold is exceeded, grouped by day.
- **Automatic geocoding** — city suggestions appear in real time while typing; coordinates are resolved before saving the alert.
- **Cloud persistence** — alerts are stored in Firebase Realtime Database and synced across devices.
- **Local persistence** — alerts are also cached in `SharedPreferences` and restored on next launch.
- **Pull-to-refresh** — swipe down on the detail view to refresh the forecast.

## Project structure

```
lib/
├── main.dart                        # Entry point (runApp only)
├── app.dart                         # MaterialApp + theme
├── firebase_options.dart            # Generated Firebase configuration
├── core/
│   └── constants/
│       └── countries.dart           # Country list and ISO codes
├── data/
│   ├── models/
│   │   ├── alert.dart               # Alert model with JSON serialization
│   │   ├── forecast_hour.dart       # Forecast hour with exceeded values
│   │   └── city_suggestion.dart     # Geocoding suggestion
│   └── repositories/
│       ├── alert_repository.dart    # Persistence via SharedPreferences + Firebase RTDB
│       ├── auth_repository.dart     # Firebase Auth (sign in / sign out)
│       └── weather_repository.dart  # Open-Meteo API (forecast + geocoding)
└── presentation/
    ├── screens/
    │   ├── home_screen.dart         # Main screen with TabBar
    │   └── auth_screen.dart         # Login / registration screen
    └── widgets/
        ├── alert_detail_view.dart   # Forecast view per alert
        ├── create_alert_sheet.dart  # Bottom sheet to create/edit an alert
        ├── summary_chip.dart        # Threshold summary chip
        ├── hour_tile.dart           # Hourly row with exceeded values
        └── value_chip.dart          # Individual colored value chip
```

## External APIs

| Service | Purpose |
|---|---|
| `api.open-meteo.com/v1/forecast` | Hourly forecast (temperature, wind, rain) |
| `geocoding-api.open-meteo.com/v1/search` | City autocomplete and geocoding |

Both APIs are free and require no API key.

## Main dependencies

| Package | Purpose |
|---|---|
| `http` | Requests to Open-Meteo APIs |
| `shared_preferences` | Local alert persistence |
| `firebase_core` | Firebase initialization |
| `firebase_auth` | User authentication |
| `firebase_database` | Cloud alert storage (Realtime Database) |

## Getting started

### Prerequisites

- Flutter 3.x / Dart 3.x
- A [Firebase](https://console.firebase.google.com) project with **Authentication** (Email/Password) and **Realtime Database** enabled
- [FlutterFire CLI](https://pub.dev/packages/flutterfire_cli): `dart pub global activate flutterfire_cli`

### Firebase setup

The following files are excluded from version control because they contain project credentials:

| File | Platform |
|---|---|
| `android/app/google-services.json` | Android |
| `ios/Runner/GoogleService-Info.plist` | iOS |
| `macos/Runner/GoogleService-Info.plist` | macOS |
| `lib/firebase_options.dart` | All (generated) |

After cloning, run:

```bash
flutterfire configure --project=<your-firebase-project-id>
```

This generates `lib/firebase_options.dart` and places the platform config files in the right directories.

### Run

```bash
flutter pub get
flutter run
```
