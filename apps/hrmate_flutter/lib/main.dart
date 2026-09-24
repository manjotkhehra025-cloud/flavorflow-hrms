import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/router.dart';
import 'core/session.dart';
import 'core/i18n.dart';

void main() {
  runApp(const ProviderScope(child: HrmateApp()));
}

class HrmateApp extends ConsumerWidget {
  const HrmateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Load the saved language once on startup.
    ref.watch(_langBootProvider);
    return MaterialApp.router(
      title: 'HRMate',
      debugShowCheckedModeBanner: false,
      theme: buildHmTheme(),
      routerConfig: router,
    );
  }
}

final _langBootProvider = FutureProvider<void>((ref) async {
  await loadLang(ref);
});
