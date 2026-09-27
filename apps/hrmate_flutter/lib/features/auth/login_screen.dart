import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Product login — navy canvas + emerald sign-in (same skin as Home).
class LoginScreen extends ConsumerStatefulWidget {
  final bool changed;
  const LoginScreen({super.key, this.changed = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(sessionStoreProvider);
    try {
      final res = await ref.read(apiProvider).post('/api/auth/login', data: {
        'email': _email.text.trim().toLowerCase(),
        'password': _password.text,
      });
      await session.saveToken(res.data['token'] as String);
      final meRes = await ref.read(apiProvider).get('/api/auth/me');
      final u = (meRes.data['user'] as Map?)?.cast<String, dynamic>();
      session.setUser(u != null ? HmUser.fromJson(u) : null);
    } catch (e) {
      setState(() => _error = apiErrorMessage(e, fallback: 'Wrong email or password.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    return Scaffold(
      backgroundColor: HMC.ink,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF065F46),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text('v0.9.3', style: TextStyle(color: Color(0xFF6EE7B7), fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.4)),
                  ),
                  const Spacer(),
                  _LangPill(lang: lang),
                ],
              ),
              const SizedBox(height: 28),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF34D399), Color(0xFF059669)],
                    ),
                    boxShadow: const [BoxShadow(color: Color(0x6610B981), blurRadius: 24, spreadRadius: 2)],
                  ),
                  child: const Icon(Icons.fingerprint, color: Colors.white, size: 48),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                T.s('Welcome back', lang),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 28),
              ),
              const SizedBox(height: 6),
              Text(
                T.s('Sign in to your HR account', lang),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              ),
              const SizedBox(height: 28),
              if (widget.changed)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF064E3B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF34D399)),
                  ),
                  child: Text(
                    T.s('Password saved ✔ — log in with the NEW password', lang),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFA7F3D0)),
                  ),
                ),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                cursorColor: const Color(0xFF34D399),
                decoration: _fieldDeco(T.s('Email', lang), Icons.mail_outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                cursorColor: const Color(0xFF34D399),
                decoration: _fieldDeco(T.s('Password', lang), Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: const Color(0xFF94A3B8)),
                  ),
                ),
                onSubmitted: (_) => _signIn(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 22),
              GestureDetector(
                onTap: _signIn,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF34D399), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [BoxShadow(color: Color(0x6610B981), blurRadius: 16, offset: Offset(0, 6))],
                  ),
                  alignment: Alignment.center,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(
                          T.s('Sign In', lang),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                ),
              ),
              const SizedBox(height: 36),
              Text(
                '🔒 ${T.s('Punch & attendance are geofenced', lang)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 8),
              const Text(
                'HRMate · v0.9.3',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String hint, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: const Color(0xFF6EE7B7)),
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      filled: true,
      fillColor: const Color(0xFF122033),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF34D399), width: 1.5),
      ),
    );
  }
}

class _LangPill extends ConsumerWidget {
  final String lang;
  const _LangPill({required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = lang == 'pa' ? 'en' : 'pa';
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () => saveLang(ref, next),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: const Color(0xFF122033),
          border: Border.all(color: const Color(0xFF1E3A4C)),
        ),
        child: Text(
          lang == 'pa' ? 'ਪੰਜਾਬੀ' : 'English',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
  }
}
