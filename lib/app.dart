import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/splash/splash_screen.dart';

class IhrmsApp extends StatelessWidget {
  const IhrmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iHRMS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const SplashScreen(),
    );
  }
}
