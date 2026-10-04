import 'package:flutter/material.dart';

import 'core/app_controller.dart';
import 'core/app_scope.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlavorFlowApp());
}

class FlavorFlowApp extends StatefulWidget {
  const FlavorFlowApp({super.key});

  @override
  State<FlavorFlowApp> createState() => _FlavorFlowAppState();
}

class _FlavorFlowAppState extends State<FlavorFlowApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _controller.restoreSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: MaterialApp(
        title: 'FlavorFlow HRMS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _SessionRouter(),
      ),
    );
  }
}

class _SessionRouter extends StatelessWidget {
  const _SessionRouter();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.isRestoring) {
          return const _SplashScreen();
        }
        if (controller.user == null) {
          return const LoginScreen();
        }
        return HomeShell(key: ValueKey(controller.user!.id));
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                gradient: const LinearGradient(colors: [AppColors.blue, AppColors.teal]),
              ),
              child: const Icon(Icons.bubble_chart_rounded, color: Colors.white, size: 31),
            ),
            const SizedBox(height: 18),
            const Text('FlavorFlow', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('People, connected.', style: TextStyle(color: Color(0xFFAFC0D2), fontSize: 13)),
            const SizedBox(height: 25),
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal)),
          ],
        ),
      ),
    );
  }
}
