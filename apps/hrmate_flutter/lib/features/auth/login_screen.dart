import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Approved P1 mock login — emblem, welcome, email+password(eye), gradient
/// sign-in capsule, EN|ਪੰਜਾਬੀ pill, geofence footnote.
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
      // Pull fresh flags so the guard can route to /set-password when needed.
      final meRes = await ref.read(apiProvider).get('/api/auth/me');
      final u = (meRes.data['user'] as Map?)?.cast<String, dynamic>();
      session.setUser(u != null ? HmUser.fromJson(u) : null);
      // Guard redirects from here.
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: _LangPill(lang: lang),
              ),
              const SizedBox(height: 12),
              Center(child: Image.asset('assets/hrmate_emblem.png', width: 120, height: 120)),
              const SizedBox(height: 18),
              Text(T.s('Welcome back', lang),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: HMC.ink,
                      )),
              const SizedBox(height: 6),
              Text(T.s('Sign in to your HR account', lang),
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              if (widget.changed)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Text(
                    T.s('Password saved ✔ — log in with the NEW password', lang),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HMC.emeraldDeep),
                  ),
                ),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.mail_outline),
                  hintText: T.s('Email', lang),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  hintText: T.s('Password', lang),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  ),
                ),
                onSubmitted: (_) => _signIn(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: HMC.danger, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _signIn,
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: HMC.brand,
                    borderRadius: BorderRadius.circular(27),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33059669), blurRadius: 14, offset: Offset(0, 6)),
                    ],
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
              const SizedBox(height: 40),
              Text(
                '🔒 ${T.s('Punch & attendance are geofenced', lang)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
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
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          lang == 'pa' ? 'ਪੰਜਾਬੀ' : 'English',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HMC.ink),
        ),
      ),
    );
  }
}
