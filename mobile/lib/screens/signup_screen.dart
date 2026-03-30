import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/mobile_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _regionController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;
  bool _registrationSucceeded = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    _regionController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _goToLogin() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed('/login');
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    final api = context.read<MobileApiService>();
    final l = context.read<SettingsProvider>().l;

    setState(() => _isSubmitting = true);

    try {
      final result = await api.registerMobile(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim(),
        region: _regionController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      if (result.ok) {
        setState(() {
          _isSubmitting = false;
          _registrationSucceeded = true;
        });
        return;
      }

      setState(() => _isSubmitting = false);

      final msg = result.message.trim();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              msg.isNotEmpty ? msg : l.get('signup_registration_failed'),
            ),
          ),
        );
    } on MobileApiException {
      if (!mounted) {
        return;
      }
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l.get('signup_registration_failed'))),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l.get('signup_registration_failed'))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsProvider>().l;

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
                  if (_registrationSucceeded) ...[
                    Text(
                      l.get('signup_success_title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B2838),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.get('signup_success_pending'),
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
                      child: GreenButton(
                        text: l.get('signup_back_to_login'),
                        icon: Icons.arrow_back_rounded,
                        onPressed: _goToLogin,
                        isLoading: false,
                      ),
                    ),
                  ] else ...[
                    Text(
                      l.get('signup_title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B2838),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.get('signup_subtitle'),
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
                              hintText: l.get('signup_username_hint'),
                              prefixIcon: Icons.person_outline,
                              validator: (value) {
                                final t = value?.trim() ?? '';
                                if (t.isEmpty) {
                                  return l.get('signup_username_empty_error');
                                }
                                if (t.length < 3) {
                                  return l.get('signup_username_min_error');
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 12),
                            LightTextField(
                              controller: _passwordController,
                              hintText: l.get('signup_password_hint'),
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
                                  return l.get('signup_password_empty_error');
                                }
                                if (value.length < 6) {
                                  return l.get('signup_password_min_error');
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 12),
                            LightTextField(
                              controller: _confirmPasswordController,
                              hintText: l.get('signup_confirm_password_hint'),
                              prefixIcon: Icons.lock_outline,
                              obscureText: _obscureConfirmPassword,
                              suffixIcon: IconButton(
                                tooltip: l.get(
                                  _obscureConfirmPassword
                                      ? 'show_password'
                                      : 'hide_password',
                                ),
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: const Color(0xFF777777),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword;
                                  });
                                },
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l.get(
                                    'signup_confirm_password_empty_error',
                                  );
                                }
                                if (value != _passwordController.text) {
                                  return l.get(
                                    'signup_password_mismatch_error',
                                  );
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 12),
                            LightTextField(
                              controller: _displayNameController,
                              hintText: l.get('signup_display_name_hint'),
                              prefixIcon: Icons.badge_outlined,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l.get(
                                    'signup_display_name_empty_error',
                                  );
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 12),
                            LightTextField(
                              controller: _regionController,
                              hintText: l.get('signup_region_hint'),
                              prefixIcon: Icons.map_outlined,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 12),
                            LightTextField(
                              controller: _phoneController,
                              hintText: l.get('signup_phone_hint'),
                              prefixIcon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 16),
                            GreenButton(
                              text: l.get('signup_submit'),
                              icon: Icons.person_add_rounded,
                              isLoading: _isSubmitting,
                              onPressed: _isSubmitting ? null : _submit,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l.get('signup_already_have_account'),
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _goToLogin,
                          child: Text(
                            l.get('signup_sign_in'),
                            style: const TextStyle(
                              color: AppColors.accentGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    l.get('version'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.versionLabel,
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
