#!/usr/bin/env python3
"""Patch the `flutter create`-generated Android wrapper for HRMate (CI only).

Run from apps/hrmate_flutter after `flutter create .`. Idempotent.

Always:
  * minSdk 24 (local_auth 3.x floor; covers camera/geolocator/firebase too)
  * permissions: INTERNET, location, biometric, camera feature (optional)
  * MainActivity -> FlutterFragmentActivity (local_auth needs a FragmentActivity)
  * Launch/Normal themes -> Theme.AppCompat (+ androidx.appcompat dep) so the
    biometric prompt does not crash on Android 7-8 (local_auth README)
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
import binascii
import json
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


APPCOMPAT = "androidx.appcompat:appcompat:1.7.0"
THEMES = {
    "android/app/src/main/res/values/styles.xml": "@style/Theme.AppCompat.Light.NoActionBar",
    "android/app/src/main/res/values-night/styles.xml": "@style/Theme.AppCompat.NoActionBar",
}


def patch_appcompat_theme(app_path):
    for path, parent in THEMES.items():
        if not os.path.exists(path):
            print(f"theme: {path} missing, skipped")
            continue
        s = read(path)
        s = re.sub(
            r'(<style\s+name="(?:LaunchTheme|NormalTheme)"\s+parent=")[^"]*(")',
            lambda m: m.group(1) + parent + m.group(2),
            s,
        )
        write(path, s)
        print(f"theme: AppCompat in {path}")
    a = read(app_path)
    if APPCOMPAT not in a:
        if app_path.endswith(".kts"):
            a += f'\ndependencies {{\n    implementation("{APPCOMPAT}")\n}}\n'
        else:
            a += f"\ndependencies {{\n    implementation '{APPCOMPAT}'\n}}\n"
        write(app_path, a)
    print(f"dep: {APPCOMPAT}")


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


PACKAGE = "in.flavorflow.hrmate"


def decode_secret(name, raw):
    """base64 from a CircleCI env var, forgiving of the usual paste slips:
    spaces / line breaks, missing '=' padding. Returns bytes or None."""
    blob = "".join(raw.split())
    if not blob:
        return None
    blob += "=" * (-len(blob) % 4)
    try:
        return base64.b64decode(blob, validate=True)
    except (binascii.Error, ValueError):
        return None


def secret_problem(release, msg):
    """Bad secret: the release APK must not silently ship without it; the
    debug/PR build just carries on with the feature off."""
    print(f"ERROR: {msg}")
    if release:
        sys.exit(1)


def google_services_json(release):
    raw = os.environ.get("FIREBASE_GOOGLE_SERVICES_B64", "").strip()
    if not raw:
        return None
    if raw.startswith("{"):
        text = raw  # raw JSON pasted instead of base64 — accept it
    else:
        data = decode_secret("FIREBASE_GOOGLE_SERVICES_B64", raw)
        text = data.decode("utf-8", "replace") if data else ""
    try:
        j = json.loads(text)
    except ValueError:
        secret_problem(
            release,
            f"FIREBASE_GOOGLE_SERVICES_B64 is not valid base64 of google-services.json "
            f"(length {len(raw)}, starts {raw[:4]!r}, ends {raw[-4:]!r}). Re-copy it "
            "(PowerShell: [Convert]::ToBase64String([IO.File]::ReadAllBytes(\"$PWD\\google-services.json\")) | Set-Clipboard) "
            "and replace the variable in CircleCI. Building WITHOUT push/Crashlytics.",
        )
        return None
    pkgs = [
        c.get("client_info", {}).get("android_client_info", {}).get("package_name")
        for c in j.get("client", [])
    ]
    if PACKAGE not in pkgs:
        secret_problem(
            release,
            f"google-services.json has no Android app with package {PACKAGE} (found {pkgs}). "
            "Add that exact package in Firebase and download the file again. Building WITHOUT push/Crashlytics.",
        )
        return None
    return json.dumps(j, indent=2)


def enable_firebase(app_path, release=False):
    text = google_services_json(release)
    if text is None:
        if not os.environ.get("FIREBASE_GOOGLE_SERVICES_B64", "").strip():
            print("firebase: FIREBASE_GOOGLE_SERVICES_B64 not set — push/Crashlytics stay off in this build")
        return False
    write("android/app/google-services.json", text)

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
    data = decode_secret("HRMATE_KEYSTORE_B64", blob)
    if not data or len(data) < 500:
        sys.exit(
            f"ERROR: HRMATE_KEYSTORE_B64 is not valid base64 of upload-keystore.jks "
            f"(length {len(blob)}, starts {blob[:4]!r}). It should start with 'MII'. Re-copy it "
            "and replace the variable in CircleCI."
        )
    with open("android/app/upload-keystore.jks", "wb") as f:
        f.write(data)

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
    patch_appcompat_theme(app_path)
    patch_gradle_props()
    firebase = enable_firebase(app_path, release="--release" in sys.argv)
    if "--release" in sys.argv:
        enable_release_signing(app_path)
    # Last line is machine-read by the CI step.
    print(f"FIREBASE_ON={'true' if firebase else 'false'}")


if __name__ == "__main__":
    main()
