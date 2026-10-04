import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/brand_config.dart';
import '../../core/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _rememberMe = true;
  bool _isPunjabi = false;
  bool _biometricsAvailable = false;
  bool _checkingBiometrics = true;
  String? _busyAction;
  String? _error;
  bool _loadedSavedEmail = false;
  Future<bool>? _biometricCheck;

  bool get _busy => _busyAction != null;
  _LoginCopy get _copy => _LoginCopy(_isPunjabi);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshBiometrics();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedSavedEmail) return;
    _email.text = AppScope.of(context).rememberedEmail ?? '';
    _loadedSavedEmail = true;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<bool> _refreshBiometrics() {
    final currentCheck = _biometricCheck;
    if (currentCheck != null) return currentCheck;
    final nextCheck = _loadBiometricAvailability();
    _biometricCheck = nextCheck;
    return nextCheck;
  }

  Future<bool> _loadBiometricAvailability() async {
    var available = false;
    try {
      available = await AppScope.of(context).canUseBiometricsOnDevice();
    } catch (_) {
      available = false;
    }
    if (mounted) {
      setState(() {
        _biometricsAvailable = available;
        _checkingBiometrics = false;
      });
    }
    return available;
  }

  Future<void> _signIn() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busyAction = 'password';
      _error = null;
    });

    try {
      final controller = AppScope.of(context);
      final enableBiometrics =
          _rememberMe && await _refreshBiometrics();
      await controller.signIn(
        _email.text,
        _password.text,
        rememberMe: _rememberMe,
        enableBiometricLogin: enableBiometrics,
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _copy.text(
              'Sign-in failed. Please try again.',
              'ਸਾਈਨ ਇਨ ਨਹੀਂ ਹੋ ਸਕਿਆ। ਕਿਰਪਾ ਕਰਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।',
            ));
      }
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _signInWithBiometrics() async {
    if (_busy) return;
    setState(() {
      _busyAction = 'biometric';
      _error = null;
    });

    try {
      final available = _checkingBiometrics
          ? await _refreshBiometrics()
          : _biometricsAvailable;
      if (!mounted) return;
      if (!available) {
        if (mounted) {
          setState(() => _error = _copy.text(
                'Fingerprint or face unlock is not available. Set it up in your device settings, or sign in with your password.',
                'ਇਸ ਡਿਵਾਈਸ ’ਤੇ ਫਿੰਗਰਪ੍ਰਿੰਟ ਜਾਂ ਫੇਸ ਅਨਲੌਕ ਉਪਲਬਧ ਨਹੀਂ। ਡਿਵਾਈਸ ਸੈਟਿੰਗਾਂ ਵਿੱਚ ਸੈੱਟ ਕਰੋ ਜਾਂ ਪਾਸਵਰਡ ਨਾਲ ਸਾਈਨ ਇਨ ਕਰੋ।',
              ));
        }
        return;
      }

      final controller = AppScope.of(context);
      if (!controller.hasBiometricLoginSession) {
        if (mounted) {
          setState(() => _error = _copy.text(
                'Sign in with your password once and keep “Remember me on this device” checked. Biometric sign-in will then be ready next time.',
                'ਪਹਿਲਾਂ ਪਾਸਵਰਡ ਨਾਲ ਸਾਈਨ ਇਨ ਕਰੋ ਅਤੇ “ਇਸ ਡਿਵਾਈਸ ’ਤੇ ਮੈਨੂੰ ਯਾਦ ਰੱਖੋ” ਚੁਣੋ। ਫਿਰ ਅਗਲੀ ਵਾਰ ਬਾਇਓਮੈਟ੍ਰਿਕ ਨਾਲ ਸਾਈਨ ਇਨ ਹੋ ਸਕੇਗਾ।',
              ));
        }
        return;
      }

      final authenticated = await controller.signInWithBiometrics();
      if (!authenticated && mounted) {
        setState(() => _error = _copy.text(
              'Biometric check was cancelled. You can use your password instead.',
              'ਬਾਇਓਮੈਟ੍ਰਿਕ ਜਾਂਚ ਰੱਦ ਹੋ ਗਈ। ਤੁਸੀਂ ਪਾਸਵਰਡ ਨਾਲ ਸਾਈਨ ਇਨ ਕਰ ਸਕਦੇ ਹੋ।',
            ));
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _copy.text(
              'Biometric sign-in could not be completed. Please use your password.',
              'ਬਾਇਓਮੈਟ੍ਰਿਕ ਸਾਈਨ ਇਨ ਪੂਰਾ ਨਹੀਂ ਹੋ ਸਕਿਆ। ਕਿਰਪਾ ਕਰਕੇ ਪਾਸਵਰਡ ਵਰਤੋ।',
            ));
      }
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _showPasswordHelp() async {
    final copy = _copy;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.text('Forgot your password?', 'ਪਾਸਵਰਡ ਭੁੱਲ ਗਏ?')),
        content: Text(copy.text(
          'For account security, password resets are handled by your HR team. Contact ${BrandConfig.companyShortName} HR to reset your account.',
          'ਖਾਤੇ ਦੀ ਸੁਰੱਖਿਆ ਲਈ ਪਾਸਵਰਡ ਰੀਸੈੱਟ ਤੁਹਾਡੀ HR ਟੀਮ ਕਰਦੀ ਹੈ। ਖਾਤਾ ਰੀਸੈੱਟ ਕਰਨ ਲਈ ${BrandConfig.companyShortName} HR ਨਾਲ ਸੰਪਰਕ ਕਰੋ।',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(copy.text('Close', 'ਬੰਦ ਕਰੋ')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.navy,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final pagePadding = constraints.maxWidth >= 760 ? 30.0 : 18.0;
              return SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(pagePadding, 12, pagePadding, 26),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: _LanguageSelector(
                            isPunjabi: _isPunjabi,
                            onChanged: (value) => setState(
                              () => _isPunjabi = value == 'Punjabi',
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 18 : 30),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(compact ? 29 : 38),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x25000000),
                                blurRadius: 34,
                                offset: Offset(0, 18),
                              ),
                            ],
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 23 : 42,
                            vertical: compact ? 22 : 40,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _BrandHeader(copy: copy, compact: compact),
                              SizedBox(height: compact ? 24 : 38),
                              _BiometricButton(
                                label: copy.text(
                                  'Login with Biometrics / Fingerprint',
                                  'ਬਾਇਓਮੈਟ੍ਰਿਕ / ਫਿੰਗਰਪ੍ਰਿੰਟ ਨਾਲ ਲੌਗਇਨ',
                                ),
                                busy: _busyAction == 'biometric',
                                height: compact ? 62 : 72,
                                onPressed: _busy ? null : _signInWithBiometrics,
                              ),
                              SizedBox(height: compact ? 19 : 27),
                              _OrPasswordDivider(copy: copy),
                              SizedBox(height: compact ? 18 : 24),
                              AutofillGroup(
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _FieldTitle(
                                        label: copy.text('Email Address', 'ਈਮੇਲ ਪਤਾ'),
                                      ),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        controller: _email,
                                        enabled: !_busy,
                                        keyboardType: TextInputType.emailAddress,
                                        textCapitalization: TextCapitalization.none,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.username,
                                          AutofillHints.email,
                                        ],
                                        style: const TextStyle(
                                          color: AppColors.ink,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: _loginFieldDecoration(
                                          hint: copy.text(
                                            'e.g. admin@hrmate.com',
                                            'ਉਦਾਹਰਨ: admin@hrmate.com',
                                          ),
                                          icon: Icons.mail_outline_rounded,
                                          compact: compact,
                                        ),
                                        validator: (value) {
                                          final text = value?.trim() ?? '';
                                          if (text.isEmpty || !text.contains('@')) {
                                            return copy.text(
                                              'Enter a valid email address.',
                                              'ਸਹੀ ਈਮੇਲ ਪਤਾ ਦਰਜ ਕਰੋ।',
                                            );
                                          }
                                          return null;
                                        },
                                      ),
                                      SizedBox(height: compact ? 15 : 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _FieldTitle(
                                              label: copy.text('Password', 'ਪਾਸਵਰਡ'),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: _busy ? null : _showPasswordHelp,
                                            style: TextButton.styleFrom(
                                              foregroundColor: AppColors.success,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 2,
                                                vertical: 4,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            child: Text(
                                              copy.text('Forgot?', 'ਭੁੱਲ ਗਏ?'),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: compact ? 6 : 8),
                                      TextFormField(
                                        controller: _password,
                                        enabled: !_busy,
                                        obscureText: true,
                                        textInputAction: TextInputAction.done,
                                        autofillHints: const [AutofillHints.password],
                                        onFieldSubmitted: (_) => _signIn(),
                                        style: const TextStyle(
                                          color: AppColors.ink,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: _loginFieldDecoration(
                                          hint: copy.text(
                                            'Enter your password',
                                            'ਆਪਣਾ ਪਾਸਵਰਡ ਦਰਜ ਕਰੋ',
                                          ),
                                          icon: Icons.lock_outline_rounded,
                                          compact: compact,
                                        ),
                                        validator: (value) =>
                                            (value?.isEmpty ?? true)
                                                ? copy.text(
                                                    'Enter your password.',
                                                    'ਆਪਣਾ ਪਾਸਵਰਡ ਦਰਜ ਕਰੋ।',
                                                  )
                                                : null,
                                      ),
                                      if (_error != null) ...[
                                        const SizedBox(height: 16),
                                        _LoginError(message: _error!),
                                      ],
                                      SizedBox(height: compact ? 14 : 20),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 27,
                                            height: 27,
                                            child: Checkbox(
                                              value: _rememberMe,
                                              onChanged: _busy
                                                  ? null
                                                  : (value) => setState(
                                                        () => _rememberMe = value ?? false,
                                                      ),
                                              activeColor: AppColors.blue,
                                              side: const BorderSide(
                                                color: AppColors.line,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 11),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: _busy
                                                  ? null
                                                  : () => setState(
                                                        () => _rememberMe = !_rememberMe,
                                                      ),
                                              child: Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      copy.text(
                                                        'Remember me on this device',
                                                        'ਇਸ ਡਿਵਾਈਸ ’ਤੇ ਮੈਨੂੰ ਯਾਦ ਰੱਖੋ',
                                                      ),
                                                      style: const TextStyle(
                                                        color: AppColors.ink,
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      copy.text(
                                                        'Save your session securely; biometric sign-in is available when supported.',
                                                        'ਸੈਸ਼ਨ ਸੁਰੱਖਿਅਤ ਸੰਭਾਲੋ; ਸਮਰਥਿਤ ਹੋਣ ’ਤੇ ਬਾਇਓਮੈਟ੍ਰਿਕ ਸਾਈਨ ਇਨ ਮਿਲੇਗਾ।',
                                                      ),
                                                      style: const TextStyle(
                                                        color: AppColors.muted,
                                                        fontSize: 11,
                                                        height: 1.35,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: compact ? 14 : 20),
                                      SizedBox(
                                        height: compact ? 58 : 66,
                                        child: ElevatedButton(
                                          onPressed: _busy ? null : _signIn,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.navy,
                                            foregroundColor: Colors.white,
                                            disabledBackgroundColor:
                                                AppColors.navy.withValues(alpha: 0.78),
                                            disabledForegroundColor: Colors.white,
                                            elevation: 3,
                                            shadowColor: AppColors.navy.withValues(alpha: 0.22),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(22),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (_busyAction == 'password') ...[
                                                const SizedBox(
                                                  width: 19,
                                                  height: 19,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                              ],
                                              Text(
                                                copy.text(
                                                  'Sign In with Password',
                                                  'ਪਾਸਵਰਡ ਨਾਲ ਸਾਈਨ ਇਨ',
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(width: 11),
                                              const Icon(
                                                Icons.arrow_forward_rounded,
                                                size: 21,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: compact ? 20 : 28),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.verified_user_outlined,
                                            color: AppColors.success,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              copy.text(
                                                'Secure session stored on this device',
                                                'ਸੁਰੱਖਿਅਤ ਸੈਸ਼ਨ ਇਸ ਡਿਵਾਈਸ ’ਤੇ ਸੰਭਾਲਿਆ ਜਾਂਦਾ ਹੈ',
                                              ),
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Color(0xFF198E6F),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: compact ? 20 : 26),
                        Text(
                          copy.text(
                            'New employee? Contact your HR Manager at ${BrandConfig.companyShortName}.',
                            'ਨਵੇਂ ਕਰਮਚਾਰੀ? ${BrandConfig.companyShortName} ਦੇ HR ਮੈਨੇਜਰ ਨਾਲ ਸੰਪਰਕ ਕਰੋ।',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFAAB6C8),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

InputDecoration _loginFieldDecoration({
  required String hint,
  required IconData icon,
  bool compact = false,
}) {
  final shape = OutlineInputBorder(
    borderRadius: BorderRadius.circular(21),
    borderSide: const BorderSide(color: Color(0xFFD4DAE2), width: 1.1),
  );
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: AppColors.muted, size: 22),
    prefixIconConstraints: const BoxConstraints(minWidth: 58),
    filled: true,
    fillColor: const Color(0xFFF9FAFC),
    contentPadding: EdgeInsets.symmetric(
      horizontal: 17,
      vertical: compact ? 16 : 22,
    ),
    hintStyle: const TextStyle(color: AppColors.ink, fontSize: 14),
    enabledBorder: shape,
    focusedBorder: shape.copyWith(
      borderSide: const BorderSide(color: AppColors.blue, width: 1.6),
    ),
    errorBorder: shape.copyWith(
      borderSide: const BorderSide(color: Color(0xFFC94D54), width: 1.2),
    ),
    focusedErrorBorder: shape.copyWith(
      borderSide: const BorderSide(color: Color(0xFFC94D54), width: 1.5),
    ),
  );
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.isPunjabi, required this.onChanged});

  final bool isPunjabi;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final language = isPunjabi ? 'ਪੰਜਾਬੀ' : 'English';
    return PopupMenuButton<String>(
      tooltip: 'Choose language',
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'English', child: Text('English')),
        PopupMenuItem(value: 'Punjabi', child: Text('ਪੰਜਾਬੀ')),
      ],
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: const Color(0xFF263348),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF536075), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, color: AppColors.teal, size: 21),
            const SizedBox(width: 10),
            Text(
              language,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 7),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.copy, required this.compact});

  final _LoginCopy copy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HRMateLogo(size: compact ? 66 : 88),
        SizedBox(height: compact ? 12 : 17),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: compact ? 31 : 37,
              height: 1,
              letterSpacing: -1.4,
              fontWeight: FontWeight.w800,
            ),
            children: const [
              TextSpan(text: 'HR', style: TextStyle(color: AppColors.ink)),
              TextSpan(text: 'Mate', style: TextStyle(color: AppColors.blue)),
            ],
          ),
        ),
        SizedBox(height: compact ? 9 : 14),
        Text(
          '${BrandConfig.companyName} · ${copy.text('WORKFORCE PORTAL', 'ਵਰਕਫੋਰਸ ਪੋਰਟਲ')}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF1CA57F),
            fontSize: 12,
            height: 1.5,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _HRMateLogo extends StatelessWidget {
  const _HRMateLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final stemWidth = size * 0.16;
    final sideInset = size * 0.25;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Stack(
        children: [
          Positioned(
            left: sideInset,
            top: size * 0.2,
            bottom: size * 0.2,
            child: Container(
              width: stemWidth,
              decoration: BoxDecoration(
                color: AppColors.blue,
                borderRadius: BorderRadius.circular(stemWidth),
              ),
            ),
          ),
          Positioned(
            right: sideInset,
            top: size * 0.2,
            bottom: size * 0.2,
            child: Container(
              width: stemWidth,
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.circular(stemWidth),
              ),
            ),
          ),
          Positioned(
            left: sideInset,
            right: sideInset,
            top: size * 0.43,
            child: Container(
              height: stemWidth,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.blue, AppColors.teal],
                ),
                borderRadius: BorderRadius.circular(stemWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrPasswordDivider extends StatelessWidget {
  const _OrPasswordDivider({required this.copy});

  final _LoginCopy copy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE1E5E9), height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Text(
            copy.text('OR WITH PASSWORD', 'ਜਾਂ ਪਾਸਵਰਡ ਨਾਲ'),
            style: const TextStyle(
              color: Color(0xFF98A3B2),
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFE1E5E9), height: 1)),
      ],
    );
  }
}

class _FieldTitle extends StatelessWidget {
  const _FieldTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _BiometricButton extends StatelessWidget {
  const _BiometricButton({
    required this.label,
    required this.busy,
    required this.height,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final double height;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF14B985), Color(0xFF008C68)],
        ),
        borderRadius: BorderRadius.circular(23),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2914B985),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onPressed,
          borderRadius: BorderRadius.circular(23),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(Icons.fingerprint,
                        color: Colors.white, size: 28),
                  const SizedBox(width: 11),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginError extends StatelessWidget {
  const _LoginError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.softRed,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFC94D54), size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF9E353B),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginCopy {
  const _LoginCopy(this.isPunjabi);

  final bool isPunjabi;

  String text(String english, String punjabi) => isPunjabi ? punjabi : english;
}
