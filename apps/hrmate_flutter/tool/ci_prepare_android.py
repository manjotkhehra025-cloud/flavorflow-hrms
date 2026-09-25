#!/usr/bin/env python3
"""Patch the `flutter create`-generated Android wrapper for HRMate (CI only).

Run from apps/hrmate_flutter after `flutter create .`. Idempotent.

Always:
  * minSdk 24 (local_auth 3.x floor; covers camera/geolocator/firebase too)
  * permissions: INTERNET, location, biometric, camera feature (optional)
  * MainActivity -> FlutterFragmentActivity (local_auth needs a FragmentActivity)
  * app label "HRMate"
  * gradle heap capped for CircleCI medium+ (GRADLE_XMX, default 2200m)

Optional, from CircleCI project env vars (never committed):
  FIREBASE_GOOGLE_SERVICES_B64   base64 of google-services.json
      -> writes android/app/google-services.json, applies the google-services
         + Crashlytics Gradle plugins, and prints `FIREBASE_ON=true` so the
         caller adds --dart-define=FIREBASE_ON=true.
  HRMATE_KEYSTORE_B64 (+ HRMATE_KEYSTORE_PASSWORD, HRMATE_KEY_ALIAS,
  HRMATE_KEY_PASSWORD)
      -> writes android/app/upload-keystore.jks and signs `release` with it.
         Without it, release builds keep Flutter's debug signing.
"""
import base64
import glob
import os
import re
import sys

GOOGLE_SERVICES_VERSION = "4.4.2"
CRASHLYTICS_GRADLE_VERSION = "3.0.2"
MIN_SDK = "24"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def app_gradle():
    for f in ("android/app/build.gradle.kts", "android/app/build.gradle"):
        if os.path.exists(f):
            return f
    sys.exit("android/app/build.gradle(.kts) not found — run `flutter create .` first")


def patch_min_sdk(path):
    s = read(path)
    s = s.replace("flutter.minSdkVersion", MIN_SDK)
    s = re.sub(r"minSdk\s*=\s*\d+", f"minSdk = {MIN_SDK}", s)
    s = re.sub(r"minSdkVersion\s+\d+", f"minSdkVersion {MIN_SDK}", s)
    write(path, s)
    print(f"minSdk {MIN_SDK} in {path}")


PERMISSIONS = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>',
    '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>',
    '<uses-permission android:name="android.permission.USE_BIOMETRIC"/>',
    '<uses-feature android:name="android.hardware.camera" android:required="false"/>',
]


def patch_manifest():
    mp = "android/app/src/main/AndroidManifest.xml"
    ms = read(mp)
    missing = [p for p in PERMISSIONS if p.split('android:name="')[1].split('"')[0] not in ms]
    if missing:
        ms = re.sub(
            r"(<manifest[^>]*>)",
            lambda m: m.group(1) + "\n" + "".join(f"    {p}\n" for p in missing),
            ms,
            count=1,
        )
    ms = re.sub(r'android:label="[^"]*"', 'android:label="HRMate"', ms, count=1)
    write(mp, ms)
    print("manifest: +" + ", ".join(p.split('android:name="')[1].split('"')[0].split(".")[-1] for p in missing))


def patch_main_activity():
    files = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True) + glob.glob(
        "android/app/src/main/java/**/MainActivity.java", recursive=True
    )
    if not files:
        sys.exit("MainActivity not found")
    for f in files:
        s = read(f)
        if "FlutterFragmentActivity" not in s:
            s = s.replace("FlutterActivity", "FlutterFragmentActivity")
            write(f, s)
        print(f"FlutterFragmentActivity in {f}")


def patch_gradle_props():
    gp = "android/gradle.properties"
    gs = read(gp)
    xmx = os.environ.get("GRADLE_XMX", "2200m")
    gs = re.sub(r"-Xmx\S+", f"-Xmx{xmx}", gs)
    gs = re.sub(r"-XX:MaxMetaspaceSize=\S+", "-XX:MaxMetaspaceSize=768m", gs)
    for line in ("org.gradle.daemon=false", "org.gradle.parallel=false"):
        if line not in gs:
            gs += f"\n{line}"
    write(gp, gs + "\n")
    print(f"gradle heap -Xmx{xmx}")


def enable_firebase(app_path):
    blob = os.environ.get("FIREBASE_GOOGLE_SERVICES_B64", "").strip()
    if not blob:
        print("firebase: FIREBASE_GOOGLE_SERVICES_B64 not set — push/Crashlytics stay off in this build")
        return False
    write("android/app/google-services.json", base64.b64decode(blob).decode("utf-8"))

    settings = "android/settings.gradle.kts"
    s = read(settings)
    if "com.google.gms.google-services" not in s:
        anchor = 'id("dev.flutter.flutter-plugin-loader") version "1.0.0"'
        if anchor not in s:
            sys.exit(f"cannot find plugin block anchor in {settings}")
        s = s.replace(
            anchor,
            anchor
            + f'\n    id("com.google.gms.google-services") version "{GOOGLE_SERVICES_VERSION}" apply false'
            + f'\n    id("com.google.firebase.crashlytics") version "{CRASHLYTICS_GRADLE_VERSION}" apply false',
            1,
        )
        write(settings, s)

    a = read(app_path)
    if "com.google.gms.google-services" not in a:
        anchor = 'id("dev.flutter.flutter-gradle-plugin")'
        if anchor not in a:
            sys.exit(f"cannot find flutter plugin anchor in {app_path}")
        a = a.replace(
            anchor,
            anchor + '\n    id("com.google.gms.google-services")\n    id("com.google.firebase.crashlytics")',
            1,
        )
        write(app_path, a)
    print("firebase: google-services.json + gradle plugins applied")
    return True


def enable_release_signing(app_path):
    blob = os.environ.get("HRMATE_KEYSTORE_B64", "").strip()
    if not blob:
        print("signing: HRMATE_KEYSTORE_B64 not set — release keeps debug signing (internal testing only)")
        return False
    for var in ("HRMATE_KEYSTORE_PASSWORD", "HRMATE_KEY_ALIAS", "HRMATE_KEY_PASSWORD"):
        if not os.environ.get(var):
            sys.exit(f"signing: {var} missing (set it next to HRMATE_KEYSTORE_B64)")
    with open("android/app/upload-keystore.jks", "wb") as f:
        f.write(base64.b64decode(blob))

    a = read(app_path)
    if 'create("release")' not in a:
        block = (
            "    signingConfigs {\n"
            '        create("release") {\n'
            '            storeFile = file("upload-keystore.jks")\n'
            '            storePassword = System.getenv("HRMATE_KEYSTORE_PASSWORD")\n'
            '            keyAlias = System.getenv("HRMATE_KEY_ALIAS")\n'
            '            keyPassword = System.getenv("HRMATE_KEY_PASSWORD")\n'
            "        }\n"
            "    }\n\n"
            "    buildTypes {"
        )
        if "    buildTypes {" not in a:
            sys.exit(f"cannot find buildTypes in {app_path}")
        a = a.replace("    buildTypes {", block, 1)
        a = a.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("release")')
        write(app_path, a)
    print("signing: release signed with upload keystore")
    return True


def main():
    app_path = app_gradle()
    patch_min_sdk(app_path)
    patch_manifest()
    patch_main_activity()
    patch_gradle_props()
    firebase = enable_firebase(app_path)
    if "--release" in sys.argv:
        enable_release_signing(app_path)
    # Last line is machine-read by the CI step.
    print(f"FIREBASE_ON={'true' if firebase else 'false'}")


if __name__ == "__main__":
    main()
