import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/work_management_provider.dart';
import '../services/mobile_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class _DevAccount {
  final String label;
  final String role;
  final String username;
  final String password;
  final IconData icon;
  final Color color;

  const _DevAccount({
    required this.label,
    required this.role,
    required this.username,
    required this.password,
    required this.icon,
    required this.color,
  });
}

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
  bool _devModeEnabled = false;
  int _devModeTapCount = 0;
  DateTime? _lastDevTapTime;

  static const int _devModeTapsRequired = 5;
  static const Duration _devModeTapWindow = Duration(seconds: 3);

  List<_DevAccount> get _devAccounts {
    final defaultPw = dotenv.env['DEV_DEFAULT_PASSWORD'] ?? 'admin123';
    return [
      _DevAccount(
        label: 'Admin / Leader',
        role: 'leader',
        username: dotenv.env['DEV_ADMIN_USERNAME'] ?? 'admin',
        password: dotenv.env['DEV_ADMIN_PASSWORD'] ?? defaultPw,
        icon: Icons.admin_panel_settings_rounded,
        color: const Color(0xFF6A1B9A),
      ),
      _DevAccount(
        label: 'Leader',
        role: 'leader',
        username: dotenv.env['DEV_LEADER_USERNAME'] ?? 'leader1',
        password: dotenv.env['DEV_LEADER_PASSWORD'] ?? defaultPw,
        icon: Icons.supervisor_account_rounded,
        color: const Color(0xFF1565C0),
      ),
      _DevAccount(
        label: 'Ranger',
        role: 'ranger',
        username: dotenv.env['DEV_RANGER_USERNAME'] ?? 'ranger1',
        password: dotenv.env['DEV_RANGER_PASSWORD'] ?? defaultPw,
        icon: Icons.forest_rounded,
        color: const Color(0xFF2E7D32),
      ),
    ];
  }

  void _onVersionTap() {
    final now = DateTime.now();
    if (_lastDevTapTime == null ||
        now.difference(_lastDevTapTime!) > _devModeTapWindow) {
      _devModeTapCount = 1;
    } else {
      _devModeTapCount++;
    }
    _lastDevTapTime = now;

    if (_devModeTapCount >= _devModeTapsRequired) {
      HapticFeedback.heavyImpact();
      setState(() {
        _devModeEnabled = !_devModeEnabled;
        _devModeTapCount = 0;
      });
    }
  }

  Future<void> _loginWithDevAccount(_DevAccount account) async {
    HapticFeedback.mediumImpact();
    _usernameController.text = account.username;
    _passwordController.text = account.password;
    _rememberMe = true;
    await context.read<AuthProvider>().setRememberMe(true);
    await _submit();
  }

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
      ..showSnackBar(SnackBar(content: Text(l.get(errorKey))));
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
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: GlassCard(
                        borderRadius: 22,
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/icons/icon.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l.get('sign_in_title'),
                    textAlign: TextAlign.center,
                    style: AppTypography.title,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l.get('sign_in_subtitle'),
                    textAlign: TextAlign.center,
                    style: AppTypography.subtitle,
                  ),
                  const SizedBox(height: AppSpacing.lg + 2),
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
                              style: AppTypography.subtitle.copyWith(
                                color: const Color(0xFF344054),
                                fontWeight: FontWeight.w600,
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
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l.get('login_no_account'),
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
                        onPressed: () {
                          Navigator.of(context).pushNamed('/signup');
                        },
                        child: Text(
                          l.get('login_create_account'),
                          style: const TextStyle(
                            color: AppColors.accentGreen,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_devModeEnabled) ...[
                    const SizedBox(height: 14),
                    GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(14),
                      tintColor: const Color(0xFFFFF8E1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.bug_report_rounded,
                                size: 18,
                                color: Color(0xFFB54708),
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'Developer Mode',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB54708),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _devModeEnabled = false),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Color(0xFFB54708),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Quick login with test accounts:',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF93733A),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._devAccounts.map(
                            (account) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: auth.isLoading
                                      ? null
                                      : () => _loginWithDevAccount(account),
                                  child: GlassCard(
                                    borderRadius: 12,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    tintColor: Colors.white,
                                    child: Row(
                                      children: [
                                        Icon(
                                          account.icon,
                                          size: 20,
                                          color: account.color,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                account.label,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: account.color,
                                                ),
                                              ),
                                              Text(
                                                '${account.username} · ${account.role}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF667085),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          size: 14,
                                          color: account.color.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _onVersionTap,
                    child: Text(
                      _devModeEnabled
                          ? '${l.get('version')} · DEV'
                          : l.get('version'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: _devModeEnabled
                            ? const Color(0xFFB54708)
                            : AppColors.versionLabel,
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
