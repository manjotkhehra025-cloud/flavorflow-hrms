# FlavorFlow HRMS

A native Flutter HRMS client for Android/iOS, backed by a small, self-contained JSON API and SQLite database. The app is not a website, PWA, or WebView. The Flutter client reads its current capabilities from the API; the API independently authorizes each request against role and permission rows in SQLite.

## Repository layout

- `lib/`, `android/`, `ios/` — native Flutter application and platform projects
- `backend/` — Python standard-library REST API, SQLite schema, seed data, and tests
- `docs/architecture.md` — route map, schema, RBAC matrix, API contract, and build plan

## Run the API

Python 3.10+ is sufficient; there are no third-party Python dependencies.

```sh
python3 backend/server.py
```

The API listens on `0.0.0.0:8080` and creates `backend/data/hrms.sqlite3` on first start. Development-only seed accounts:

| Role | Email | Password |
|---|---|---|
| Super Admin | `admin@flavorflow.com` | `Admin123!` |
| Manager | `manager@flavorflow.com` | `Manager123!` |
| Employee | `employee@flavorflow.com` | `Employee123!` |

Set `HRMS_ADMIN_EMAIL` and `HRMS_ADMIN_PASSWORD` **before first startup** to seed a different Super Admin account. Other local options: `HRMS_DB_PATH`, `HRMS_PORT`, `HRMS_MANAGER_EMAIL`, `HRMS_MANAGER_PASSWORD`, `HRMS_EMPLOYEE_EMAIL`, and `HRMS_EMPLOYEE_PASSWORD`. The demo credentials are not production credentials. Back up the database, change demo passwords, use HTTPS, and add production-grade deployment controls before exposing the API to a network.

## Run the native Flutter app

Install Flutter (stable) and the Android SDK/JDK, then from the repository root:

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1/
```

`10.0.2.2` reaches the host machine from an Android emulator. For an iOS simulator, use `http://127.0.0.1:8080/api/v1/`; for a physical device, use the host's LAN address and keep the API bound to `0.0.0.0`. Production builds should pass an HTTPS URL via `API_BASE_URL`. Geolocation permissions are requested by the native app at punch time.

## Checks

```sh
python3 -m unittest discover -s backend/tests -v
flutter analyze
flutter test
flutter build apk --debug
```

## CircleCI Android build

`.circleci/config.yml` runs the Python API tests, Flutter analysis and tests, then builds an installable Android **debug** APK. In CircleCI, add `API_BASE_URL` under **Project Settings → Environment Variables**, using the HTTPS URL for the deployed API, for example `https://hrms.your-domain.com/api/v1/`. The Android job fails early if this variable is missing or is not HTTPS, so the APK will not silently point at the Android emulator's local development address.

After a successful workflow, download `flavorflow-hrms-debug.apk` from the `android-build` job's **Artifacts** tab. This debug-signed APK is for installation/testing, not Google Play distribution. A Play Store release needs an Android upload keystore and signing secrets configured in CircleCI; never commit the keystore or passwords.

The authoring sandbox did not have Flutter, Dart, Java, or the Android SDK installed, so the Flutter analysis/tests/native build could not be run locally. The CircleCI job provides those checks in its Android build environment.
