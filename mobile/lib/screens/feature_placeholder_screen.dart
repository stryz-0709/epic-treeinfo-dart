import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/work_management_provider.dart';
import '../providers/settings_provider.dart';
import '../services/mobile_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class FeaturePlaceholderScreen extends StatelessWidget {
  final String titleKey;
  final int navIndex;

  const FeaturePlaceholderScreen({
    super.key,
    required this.titleKey,
    this.navIndex = 0,
  });

  Future<void> _logoutFromAccount(BuildContext context) async {
    HapticFeedback.mediumImpact();

    final auth = context.read<AuthProvider>();
    final authApi = context.read<MobileApiService>();
    final l = context.read<SettingsProvider>().l;

    try {
      if (auth.isAuthenticated) {
        await auth.logoutMobileSession(authApi: authApi);
      } else if (auth.isAdmin) {
        auth.logout();
      } else {
        auth.clearMobileSession();
      }
    } catch (_) {
      auth.clearMobileSession();
    }

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.get('signed_out'))));

    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final l = context.watch<SettingsProvider>().l;
    final workProvider = context.watch<WorkManagementProvider>();
    final screenH = MediaQuery.sizeOf(context).height;
    final isWorkManagementScreen = titleKey == 'landing_function_work';
    final isAccountScreen = titleKey == 'account' || navIndex == 4;
    final canLogout = isAccountScreen && (auth.isAuthenticated || auth.isAdmin);

    String _checkinStatusLabel(String? status) {
      switch (status) {
        case 'created':
          return l.get('work_checkin_status_created');
        case 'already_exists':
          return l.get('work_checkin_status_exists');
        default:
          return l.get('work_checkin_status_unknown');
      }
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppTopToolbar(
        title: l.get(titleKey),
        onBack: () => Navigator.of(context).pop(),
      ),
      body: Stack(
        children: [
          Positioned(
            top: screenH * 0.15,
            left: 0,
            right: 0,
            bottom: 0,
            child: Opacity(
              opacity: 0.18,
              child: Image.asset(
                'assets/icons/background.jpeg',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, e, s) =>
                    Container(color: const Color(0xFFF0F0F0)),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenH * 0.45,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.5, 1.0],
                  colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 80,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.73),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                0,
              ),
              child: Column(
                children: [
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.07),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.construction_rounded,
                          size: 42,
                          color: Color(0xFF2E7D32),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l.get(titleKey),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1B2838),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.get('placeholder_coming_soon'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF666666),
                          ),
                        ),
                        if (canLogout) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              key: const Key('account_logout_button'),
                              onPressed: () => _logoutFromAccount(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB42318),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.logout_rounded),
                              label: Text(l.get('logout')),
                            ),
                          ),
                        ],
                        if (isWorkManagementScreen) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4FAF5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0x332E7D32),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.get('work_checkin_title'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1B2838),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (workProvider.isSyncingCheckin)
                                  Text(
                                    l.get('work_checkin_syncing'),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF2E7D32),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                else
                                  Text(
                                    _checkinStatusLabel(
                                      workProvider.lastCheckinStatus,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF2E7D32),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  workProvider.lastCheckinDayKey == null
                                      ? l.get('work_checkin_day_pending')
                                      : '${l.get('work_checkin_day_prefix')}${workProvider.lastCheckinDayKey}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF4B5563),
                                  ),
                                ),
                                if (workProvider.checkinError != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${l.get('work_checkin_error_prefix')}${workProvider.checkinError}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFB42318),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      l.get('version'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.versionLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
