import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).signIn(_email.text, _password.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 36, 22, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _BrandMark(compact: true),
                        const SizedBox(height: 42),
                        _LoginForm(
                          formKey: _formKey,
                          email: _email,
                          password: _password,
                          busy: _busy,
                          showPassword: _showPassword,
                          error: _error,
                          onTogglePassword: () => setState(() => _showPassword = !_showPassword),
                          onSubmit: _signIn,
                        ),
                        const SizedBox(height: 24),
                        const _SecureFooter(centered: true),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Row(
              children: [
                Expanded(flex: 11, child: _BrandPanel()),
                Expanded(
                  flex: 9,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 35),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 470),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink)),
                            const SizedBox(height: 8),
                            const Text('Sign in to your people workspace.', style: TextStyle(color: AppColors.muted, fontSize: 15)),
                            const SizedBox(height: 34),
                            _LoginForm(
                              formKey: _formKey,
                              email: _email,
                              password: _password,
                              busy: _busy,
                              showPassword: _showPassword,
                              error: _error,
                              onTogglePassword: () => setState(() => _showPassword = !_showPassword),
                              onSubmit: _signIn,
                            ),
                            const SizedBox(height: 25),
                            const _SecureFooter(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.email,
    required this.password,
    required this.busy,
    required this.showPassword,
    required this.onTogglePassword,
    required this.onSubmit,
    this.error,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool busy;
  final bool showPassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (MediaQuery.sizeOf(context).width < 900) ...[
          Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 8),
          const Text('Sign in to your people workspace.', style: TextStyle(color: AppColors.muted, fontSize: 14)),
          const SizedBox(height: 27),
        ],
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('Work email'),
              const SizedBox(height: 8),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                decoration: const InputDecoration(
                  hintText: 'you@company.com',
                  prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty || !text.contains('@')) return 'Enter your work email.';
                  return null;
                },
              ),
              const SizedBox(height: 19),
              const _FieldLabel('Password'),
              const SizedBox(height: 8),
              TextFormField(
                controller: password,
                obscureText: !showPassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                  suffixIcon: IconButton(
                    tooltip: showPassword ? 'Hide password' : 'Show password',
                    onPressed: onTogglePassword,
                    icon: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  ),
                ),
                validator: (value) => (value?.isEmpty ?? true) ? 'Enter your password.' : null,
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.softRed, borderRadius: BorderRadius.circular(13)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFC94D54), size: 19),
                      const SizedBox(width: 9),
                      Expanded(child: Text(error!, style: const TextStyle(color: Color(0xFF9E353B), fontSize: 13, height: 1.4))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 23),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Sign in',
                  icon: Icons.arrow_forward_rounded,
                  busy: busy,
                  expand: true,
                  onPressed: onSubmit,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w700));
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: const LinearGradient(colors: [AppColors.blue, AppColors.teal]),
          ),
          child: const Icon(Icons.bubble_chart_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FlavorFlow', style: TextStyle(color: compact ? AppColors.navy : Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('PEOPLE PLATFORM', style: TextStyle(color: compact ? AppColors.muted : const Color(0xFFB6C8D9), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          ],
        ),
      ],
    );
  }
}

class _BrandPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(15),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(30)),
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.navy, Color(0xFF103B62), Color(0xFF0C6970)],
                ),
              ),
            ),
          ),
          Positioned(
            right: -80,
            top: -70,
            child: Container(width: 360, height: 360, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 60))),
          ),
          Positioned(
            right: 70,
            bottom: -230,
            child: Container(width: 520, height: 520, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.teal.withValues(alpha: 0.1))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(54, 48, 52, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BrandMark(),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withValues(alpha: 0.11))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFF70E2CB)), SizedBox(width: 7), Text('A better day at work starts here', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))]),
                ),
                const SizedBox(height: 22),
                const Text('People,\nconnected.', style: TextStyle(color: Colors.white, fontSize: 48, height: 1.06, letterSpacing: -1.8, fontWeight: FontWeight.w800)),
                const SizedBox(height: 19),
                const Text('A calmer way to manage your team,\ntime, and every step in between.', style: TextStyle(color: Color(0xFFC1D0DE), fontSize: 16, height: 1.6)),
                const SizedBox(height: 35),
                const Row(
                  children: [
                    _TrustPoint(icon: Icons.location_on_outlined, text: 'Location-aware'),
                    SizedBox(width: 24),
                    _TrustPoint(icon: Icons.verified_user_outlined, text: 'Permission-led'),
                  ],
                ),
                const Spacer(),
                const Text('FLAVORFLOW  ·  HRMS', style: TextStyle(color: Color(0xFFA8BDCF), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustPoint extends StatelessWidget {
  const _TrustPoint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, color: const Color(0xFF70E2CB), size: 17), const SizedBox(width: 7), Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))]);
}

class _SecureFooter extends StatelessWidget {
  const _SecureFooter({this.centered = false});
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: const [
        Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.muted),
        SizedBox(width: 7),
        Text('Secure workspace · Your account is protected', style: TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
    return centered ? Center(child: row) : row;
  }
}
