import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/work_management_provider.dart';
import '../services/mobile_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _bootstrapStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapSession());
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapSession() async {
    if (_bootstrapStarted) {
      return;
    }
    _bootstrapStarted = true;

    final auth = context.read<AuthProvider>();
    final authApi = context.read<MobileApiService>();

    await auth.restoreRememberedSession(authApi: authApi);
    if (!mounted) {
      return;
    }

    setState(() {
      _rememberMe = auth.rememberMe;
    });

    if (auth.isAuthenticated) {
      await _triggerAppOpenCheckinIfNeeded();
      _navigateToAppRoot();
    }
  }

  Future<void> _onRememberMeChanged(bool value) async {
    setState(() {
      _rememberMe = value;
    });
    await context.read<AuthProvider>().setRememberMe(value);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    final auth = context.read<AuthProvider>();
    final authApi = context.read<MobileApiService>();
    final l = context.read<SettingsProvider>().l;

    final ok = await auth.loginWithMobileApi(
      authApi: authApi,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      rememberMe: _rememberMe,
    );

    if (!mounted) {
      return;
    }

    if (ok) {
      await _triggerAppOpenCheckinIfNeeded();
      _navigateToAppRoot();
      return;
    }

    final errorKey = auth.error ?? 'network_error_try_again';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l.get(errorKey))),
      );
  }

  void _navigateToAppRoot() {
    Navigator.of(context).pushNamedAndRemoveUntil('/landing', (_) => false);
  }

  Future<void> _triggerAppOpenCheckinIfNeeded() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isRangerSession) {
      return;
    }

    final workProvider = context.read<WorkManagementProvider>();
    await workProvider.triggerAppOpenCheckin(authProvider: auth);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsProvider>().l;
    final auth = context.watch<AuthProvider>();

    if (auth.isRestoringSession && !auth.restoreAttempted) {
      return LightScaffold(
        showBackground: true,
        child: SafeArea(
          child: Center(
            child: GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.accentGreen,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.get('restoring_session'),
                    style: const TextStyle(
                      color: Color(0xFF1B2838),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: LightScaffold(
        showBackground: true,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, MediaQuery.sizeOf(context).height - 80),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/icons/icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    l.get('sign_in_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1B2838),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.get('sign_in_subtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 22),
                  GlassCard(
                    borderRadius: 24,
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LightTextField(
                            controller: _usernameController,
                            hintText: l.get('username_hint'),
                            prefixIcon: Icons.person_outline,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l.get('username_empty_error');
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 12),
                          LightTextField(
                            controller: _passwordController,
                            hintText: l.get('password_hint'),
                            prefixIcon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            suffixIcon: IconButton(
                              tooltip: l.get(
                                _obscurePassword
                                    ? 'show_password'
                                    : 'hide_password',
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: const Color(0xFF777777),
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return l.get('password_empty_error');
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: _rememberMe,
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              _onRememberMeChanged(value);
                            },
                            activeColor: AppColors.accentGreen,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              l.get('remember_me'),
                              style: const TextStyle(
                                color: Color(0xFF344054),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          GreenButton(
                            text: l.get('sign_in_action'),
                            icon: Icons.login_rounded,
                            isLoading: auth.isLoading,
                            onPressed: auth.isLoading ? null : _submit,
                          ),
                          if (auth.error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              l.get(auth.error ?? ''),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l.get('version'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF98A2B3),
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
