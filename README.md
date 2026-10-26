# iHRMS – Employee Self-Service HR App (Flutter starter)

iHRMS is a company HR app in the style of HROne. It is a **starter project**: every screen works,
using sample (mock) data stored in memory. Next you connect a real backend (Firebase or your own API).

* Flutter 3 / Dart 3 (null-safe), Material 3, blue theme, amounts in INR (₹)
* State management: `provider`
* Data layer: repository interfaces plus mock implementations, so a real backend plugs in later
* Platforms: Android, iOS, Web

Verified on Flutter 3.47.8 (Dart 3.13): `flutter analyze` reports no issues, `flutter test` passes
(this includes a smoke test that opens every screen), and `flutter build web` succeeds.

## Demo logins

| Role     | Employee ID | Password |
|----------|-------------|----------|
| Employee | EMP001      | emp123   |
| Admin/HR | ADM001      | admin123 |

EMP002 to EMP005 also work, with the password `emp123`. The login screen has buttons that fill these in for you.
The data resets every time the app restarts. That is expected for mock data.

## Run it

```bash
flutter pub get
flutter run              # pick a connected phone, emulator, or Chrome
flutter run -d chrome    # run in the browser
flutter analyze && flutter test
```

Build:

```bash
flutter build apk --release        # Android APK  -> build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle            # Android App Bundle (for Play Store)
flutter build ios --release        # iOS (needs a Mac with Xcode + Apple developer account)
flutter build web                  # Web
```

## Features

| Area | What works now |
|------|----------------|
| Splash and login | Employee ID and password, mock authentication, employee or admin role |
| Dashboard | Greeting, live clock, today's punch status, quick-action tiles, leave balance, last salary, next holiday, latest announcement |
| Attendance | Punch in and punch out with time and hours worked, a monthly calendar coloured by status, monthly summary, day-by-day history |
| Leave | Balance cards (CL, SL, EL), apply with type, date range and reason (Sundays are not counted), status list, cancel a pending request |
| Payslips | List of months, detail view with earnings, deductions and net pay (PF, ESI, Professional Tax, TDS), a "Download PDF" stub |
| Holidays | Yearly list with the next holiday highlighted |
| Announcements | List with pinned items; admins can post and delete |
| Profile | Work and personal details, change password, logout |
| Admin | Employee list with search, add and edit an employee (role, salary, active), leave approvals (approve or reject with a comment), daily attendance report |

## Project structure

```
lib/
  main.dart                      app entry point
  app.dart                       MaterialApp + theme
  app_providers.dart             registers all providers
  core/                          theme, INR/date formatters, errors, navigation helper
  models/                        Employee, AttendanceRecord, LeaveRequest/LeaveBalance, Payslip, Holiday, Announcement
  repositories/
    *_repository.dart            ABSTRACT interfaces (the contract the app uses)
    repository_factory.dart      <-- THE ONE PLACE TO SWITCH TO A REAL BACKEND
    mock/                        in-memory mock implementations + sample data (mock_database.dart)
  services/
    punch_verification_service.dart   GPS / geo-fence / selfie hooks (TODO)
  providers/                     ChangeNotifier state for auth, attendance, leave, payslips, employees, content
  screens/                       one folder per feature (auth, dashboard, attendance, leave, payslip, holidays,
                                 announcements, profile, more, admin)
  widgets/                       reusable widgets (punch card, leave balance card, status chips...)
test/                            unit test + smoke test that opens every screen
```

## Connecting a real backend

The screens and providers only use the abstract repositories in `lib/repositories/`.
To go live:

1. Create implementations, for example `lib/repositories/firebase/firebase_auth_repository.dart`
   containing `class FirebaseAuthRepository implements AuthRepository`. Do the same for
   Employee, Attendance, Leave, Payslip and Content.
2. Return them from `buildRepositories()` in `lib/repositories/repository_factory.dart`.
3. No screen or provider has to change.

Suggested Firebase layout:

* **Auth:** Firebase Auth. Map the employee ID to an email such as `emp001@yourcompany.com`, or use a Cloud Function.
* **Firestore collections:**
  * `employees/{id}`: profile fields plus `role` (`employee` or `admin`)
  * `attendance/{employeeId}_{yyyy-MM-dd}`: punchIn, punchOut, location, selfieUrl
  * `leaves/{id}`: employeeId, type, fromDate, toDate, reason, status, approverComment
  * `payslips/{id}`: employeeId, month, earnings[], deductions[]
  * `holidays/{id}` and `announcements/{id}`
* Add security rules so employees can read and write only their own data and admins can access everything.

Do not put real API keys or passwords in the code. Use `flutterfire configure`, which generates `firebase_options.dart`.

## Next steps (TODO hooks already in the code)

Search the code for `TODO(` to find each one:

* `TODO(geo)` / `TODO(geo-fence)`: real GPS punch with `geolocator`, plus an office-radius check, in `services/punch_verification_service.dart`
* `TODO(selfie)`: selfie at punch-in with `image_picker`, uploaded to storage
* `TODO(pdf)`: payslip PDF with the `pdf` and `printing` packages, in `mock_payslip_repository.dart` and `payslip_detail_screen.dart`
* `TODO(push)`: push notifications (leave approved or rejected, new announcement) with `firebase_messaging`
* `TODO(export)`: export the attendance report to Excel or CSV
* Remove the demo-login box on the login screen
* App icon and splash: `flutter_launcher_icons`, `flutter_native_splash`
* Android and iOS permissions for location and camera (AndroidManifest.xml, Info.plist)
