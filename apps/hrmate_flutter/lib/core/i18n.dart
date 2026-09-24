import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI language ('en' | 'pa') — persisted locally; grows with each phase.
final langProvider = StateProvider<String>((ref) => 'en');

Future<void> loadLang(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  ref.read(langProvider.notifier).state = prefs.getString('hm_lang') ?? 'en';
}

Future<void> saveLang(WidgetRef ref, String lang) async {
  ref.read(langProvider.notifier).state = lang;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('hm_lang', lang);
}

/// App-level strings for the P1 flow. Every user-facing label goes through T().
class T {
  static const _pa = <String, String>{
    'Splash loading': 'ਲੋਡ ਹੋ ਰਿਹਾ…',
    'Welcome back': 'ਮੁੜ ਖੁਸ਼ ਆਇਆ',
    'Sign in to your HR account': 'ਆਪਣੇ HR ਖਾਤੇ ਵਿੱਚ ਸਾਈਨ ਇਨ ਕਰੋ',
    'Email': 'ਈਮੇਲ',
    'Password': 'ਪਾਸਵਰਡ',
    'Sign In': 'ਸਾਈਨ ਇਨ',
    'Signing in…': 'ਸਾਈਨ ਇਨ ਹੋ ਰਿਹਾ…',
    'Punch & attendance are geofenced': 'ਪੰਚ ਤੇ ਹਾਜ਼ਰੀ ਜੀਓ-ਫੈਂਸ ਨਾਲ ਹੈ',
    'English': 'English',
    'ਪੰਜਾਬੀ': 'ਪੰਜਾਬੀ',
    'Choose your own password': 'ਆਪਣਾ ਪਾਸਵਰਡ ਖ਼ੁਦ ਚੁਣੋ',
    'this keeps your account yours alone.': 'ਇਹ ਤੁਹਾਡਾ ਖ਼ਾਤਾ ਸਿਰਫ਼ ਤੁਹਾਡਾ ਹੀ ਰੱਖਦਾ ਹੈ।',
    'New password': 'ਨਵਾਂ ਪਾਸਵਰਡ',
    'Repeat password': 'ਪਾਸਵਰਡ ਫਿਰ ਤੋਂ',
    'Save my password & log in': 'ਪਾਸਵਰਡ ਸੇਵ ਕਰੋ ਅਤੇ ਲੌਗਿਨ ਕਰੋ',
    "After saving you'll be signed out — log in again with the new password":
        'ਸੇਵ ਕਰਨ ਮਗਰੋਂ ਤੁਸੀਂ ਬਾਹਰ ਹੋ ਜਾਓਗੇ — ਨਵੇਂ ਪਾਸਵਰਡ ਨਾਲ ਦੁਬਾਰਾ ਲੌਗਿਨ ਕਰੋ',
    'Both passwords don\'t match': 'ਦੋਵੇਂ ਪਾਸਵਰਡ ਮਿਲਦੇ ਨਹੀਂ',
    'Password saved ✔ — log in with the NEW password': 'ਪਾਸਵਰਡ ਸੇਵ ਹੋ ਗਿਆ ✔ — ਨਵੇਂ ਪਾਸਵਰਡ ਨਾਲ ਲੌਗਿਨ ਕਰੋ',
    'Home': 'ਹੋਮ',
    'Dashboard is coming next phase': 'ਡੈਸ਼ਬੋਰਡ ਅਗਲੇ ਫੇਜ਼ ਵਿੱਚ ਆ ਰਿਹਾ ਹੈ',
    'Log out': 'ਲੌਗ ਆਉਟ',
    'Strength': 'ਤਾਕਤ',
    'weak': 'ਕਮਜ਼ੋਰ',
    'okay': 'ਠੀਕ',
    'strong': 'ਮਜ਼ਬੂਤ',
  };

  static String s(String en, String lang) => lang == 'pa' ? (_pa[en] ?? en) : en;
}
