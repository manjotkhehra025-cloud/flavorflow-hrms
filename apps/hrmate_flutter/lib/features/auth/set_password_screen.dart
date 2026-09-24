import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Approved P1 mock forced-change screen — glowing emblem, name greet,
/// new/repeat fields, 3-bar strength meter, save → sign out → /login?changed=1.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;
  String? _error;

  int _strength(String p) {
    if (p.isEmpty) return 0;
    var score = 1;
    if (p.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    return score.clamp(1, 3);
  }

  Future<void> _save() async {
    if (_busy) return;
    final session = ref.read(sessionStoreProvider);
    final lang = ref.read(langProvider);
    if (_p1.text.length < 6) {
      setState(() => _error = T.s('Your new password must be at least 6 characters.', lang));
      return;
    }
    if (_p1.text != _p2.text) {
      setState(() => _error = T.s("Both passwords don't match", lang));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).post('/api/auth/set-password', data: {'newPassword': _p1.text});
      // Sign out → the login screen shows the "password saved" banner.
      await session.clear();
      if (mounted) context.go('/login?changed=1');
    } catch (e) {
      setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final session = ref.watch(sessionStoreProvider);
    final name = (session.user?.name ?? '').split(' ').first;
    final strength = _strength(_p1.text);

    return Scaffold(
      backgroundColor: HMC.ink,
      body: Stack(children: [
        Positioned(
          top: -120,
          right: -60,
          child: Container(
            width: 320,
            height: 320,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x2610D9A0)),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 36),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x1410D9A0)),
                    child: Image.asset('assets/hrmate_emblem.png', width: 92, height: 92),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  T.s('Choose your own password', lang),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  name.isEmpty
                      ? T.s('this keeps your account yours alone.', lang)
                      : 'Hi $name — ${T.s('this keeps your account yours alone.', lang)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.65)),
                ),
                const SizedBox(height: 28),
                _darkField(controller: _p1, hint: T.s('New password', lang), obscure: true, onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                _darkField(controller: _p2, hint: T.s('Repeat password', lang), obscure: true),
                const SizedBox(height: 14),
                // strength meter — 3 bars
                Row(children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                        height: 8,
                        decoration: BoxDecoration(
                          color: i < strength ? HMC.emerald : const Color(0x26FFFFFF),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    strength <= 1 ? T.s('weak', lang) : strength == 2 ? T.s('okay', lang) : T.s('strong', lang),
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: HMC.inkSoft,
                    foregroundColor: HMC.emerald,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: HMC.emerald))
                      : Text(T.s('Save my password & log in', lang)),
                ),
                const SizedBox(height: 16),
                Text(
                  T.s("After saving you'll be signed out — log in again with the new password", lang),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _darkField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        filled: true,
        fillColor: const Color(0x26FFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x33FFFFFF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x33FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: HMC.emerald, width: 2),
        ),
      ),
    );
  }
}
