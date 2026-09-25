import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase is switched on per build: CI passes `--dart-define=FIREBASE_ON=true`
/// only when the `google-services.json` secret is present (and then also
/// applies the google-services + Crashlytics Gradle plugins). Without it the
/// app runs exactly as before — no push, no crash upload, nothing breaks.
const kFirebaseOn = bool.fromEnvironment('FIREBASE_ON');

bool _ready = false;

/// True once Firebase initialised successfully on this launch.
bool get firebaseReady => _ready;

/// Call once, before `runApp`. Never throws.
Future<void> bootFirebase() async {
  if (!kFirebaseOn) return;
  try {
    await Firebase.initializeApp();
    _ready = true;
  } catch (e) {
    debugPrint('[firebase] init failed: $e');
    return;
  }

  final crash = FirebaseCrashlytics.instance;
  // Debug builds would flood the console with test crashes — release only.
  await crash.setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = crash.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(crash.recordError(error, stack, fatal: true));
    return true;
  };
}

/// Tag crash reports with the signed-in user (id only — no names/emails).
Future<void> crashSetUser(String? userId) async {
  if (!_ready) return;
  try {
    await FirebaseCrashlytics.instance.setUserIdentifier(userId ?? '');
  } catch (_) {}
}
