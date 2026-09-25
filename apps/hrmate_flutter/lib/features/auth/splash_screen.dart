import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Splash — boots the session from secure storage, warm-pings /api/auth/me
/// when a token exists, then the router guard sends us on our way.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final session = ref.read(sessionStoreProvider);
    if (!session.booted) await session.bootstrap();
    final token = session.cachedToken;
    if (token != null) {
      try {
        final res = await ref.read(apiProvider).get('/api/auth/me');
        final u = (res.data['user'] as Map?)?.cast<String, dynamic>();
        session.setUser(u != null ? HmUser.fromJson(u) : null);
      } on DioException {
        // Offline or bad token → stay with stored token; screens will surface
        // a fresh 401 later (request-level handling comes in P2).
        session.setUser(null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HMC.ink,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 0.9,
            colors: [Color(0x2210D9A0), HMC.ink],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              Image.asset('assets/hrmate_emblem.png', width: 128, height: 128),
              const SizedBox(height: 20),
              const Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: 'HR',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  TextSpan(
                    text: 'Mate',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w300, color: Colors.white),
                  ),
                ]),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: const LinearProgressIndicator(
                    minHeight: 3,
                    color: HMC.emerald,
                    backgroundColor: Color(0x33FFFFFF),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'GD Foods · Khadur Sahib',
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.65)),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
