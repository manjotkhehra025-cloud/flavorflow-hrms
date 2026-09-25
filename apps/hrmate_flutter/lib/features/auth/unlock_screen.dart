import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_lock.dart';
import '../../core/i18n.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Full-screen biometric gate, drawn over the navigator (so the user returns
/// to exactly the screen they left). Auto-prompts once when shown.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final lang = ref.read(langProvider);
    final ok = await ref.read(appLockProvider).unlock(T.s('Unlock HRMate', lang));
    if (!mounted) return;
    setState(() => _failed = !ok);
  }

  Future<void> _usePassword() async {
    await ref.read(pushServiceProvider).stop();
    await ref.read(sessionStoreProvider).clear();
    ref.read(appLockProvider).release();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final lock = ref.watch(appLockProvider);
    final name = (ref.watch(sessionStoreProvider).user?.name ?? '').split(' ').first;

    return Material(
      color: HMC.ink,
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.2), radius: 0.95, colors: [Color(0x2210D9A0), HMC.ink]),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(children: [
              const Spacer(flex: 2),
              Image.asset('assets/hrmate_emblem.png', width: 96, height: 96),
              const SizedBox(height: 18),
              Text(
                name.isEmpty ? 'HRMate' : '${T.s('Welcome back', lang)}, $name',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                T.s('HRMate is locked — use your fingerprint or screen lock', lang),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13.5),
              ),
              const Spacer(),
              GestureDetector(
                onTap: lock.busy ? null : _unlock,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: HMC.brand,
                    boxShadow: [BoxShadow(color: HMC.emerald.withValues(alpha: 0.35), blurRadius: 30, spreadRadius: 2)],
                  ),
                  child: lock.busy
                      ? const Padding(
                          padding: EdgeInsets.all(34),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.fingerprint, size: 54, color: Colors.white),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _failed ? T.s('Not recognised — tap to try again', lang) : T.s('Tap to unlock', lang),
                style: TextStyle(
                  color: _failed ? HMC.amber : Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(flex: 2),
              TextButton(
                onPressed: lock.busy ? null : _usePassword,
                child: Text(
                  T.s('Sign in with password instead', lang),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
