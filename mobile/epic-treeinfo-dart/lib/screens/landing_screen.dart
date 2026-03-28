import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  static const List<String> _navRoutes = [
    '/',
    '/maps',
    '/alerts',
    '/notifications',
    '/account',
  ];

  static const List<_FeatureCardData> _features = [
    _FeatureCardData(
      titleKey: 'landing_function_work',
      routeName: '/work-management',
      leadingIcon: Icons.insert_chart_rounded,
      trailingIcon: Icons.timer_outlined,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_incident',
      routeName: '/incident-management',
      leadingIcon: Icons.warning_amber_rounded,
      trailingIcon: Icons.assignment_outlined,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_resource',
      routeName: '/resource-management',
      leadingIcon: Icons.inventory_2_outlined,
      trailingIcon: Icons.handyman_outlined,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_schedule',
      routeName: '/schedule-management',
      leadingIcon: Icons.calendar_month_rounded,
      trailingIcon: Icons.task_alt_rounded,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_reports',
      routeName: '/reports-management',
      leadingIcon: Icons.bar_chart_rounded,
      trailingIcon: Icons.analytics_outlined,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_patrol',
      routeName: '/patrol-management',
      leadingIcon: Icons.map_outlined,
      trailingIcon: Icons.person_pin_circle_outlined,
    ),
  ];

  void _onBottomNavTapped(int index) {
    HapticFeedback.selectionClick();
    final routeName = _navRoutes[index];
    if (routeName == '/') {
      return;
    }
    Navigator.of(context).pushNamed(routeName);
  }

  String _resolvedUserName({
    required AuthProvider auth,
    required SettingsProvider settings,
  }) {
    final displayName = auth.mobileDisplayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final username = auth.mobileUsername?.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
    return settings.l.get('landing_user_name');
  }

  String _resolvedUserRole({
    required AuthProvider auth,
    required SettingsProvider settings,
  }) {
    final l = settings.l;

    if (auth.isLeaderSession) {
      return l.get('work_calendar_role_leader');
    }
    if (auth.isRangerSession) {
      return l.get('work_calendar_role_ranger');
    }

    final normalizedRole = auth.mobileRole?.trim().toLowerCase();
    if (normalizedRole == 'leader') {
      return l.get('work_calendar_role_leader');
    }
    if (normalizedRole == 'ranger') {
      return l.get('work_calendar_role_ranger');
    }

    return l.get('landing_user_role');
  }

  String _formattedDutyDate(String locale) {
    final now = DateTime.now();

    if (locale == 'en') {
      const weekdayNamesEn = <String>[
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      const monthNamesEn = <String>[
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];

      final weekday = weekdayNamesEn[now.weekday - 1];
      final month = monthNamesEn[now.month - 1];
      return '$weekday, $month ${now.day} ${now.year}';
    }

    const weekdayNamesVi = <String>[
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật',
    ];

    final weekday = weekdayNamesVi[now.weekday - 1];
    return '$weekday, ${now.day} Tháng ${now.month} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final l = settings.l;

    final userName = _resolvedUserName(auth: auth, settings: settings);
    final userRole = _resolvedUserRole(auth: auth, settings: settings);
    final dutyDate = _formattedDutyDate(settings.locale);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Background: white top → gradient → image bottom ──
          Positioned(
            top: screenH * 0.15,
            left: 0,
            right: 0,
            bottom: 0,
            child: Image.asset(
              'assets/icons/background.jpeg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, e, s) =>
                  Container(color: const Color(0xFF1B2838)),
            ),
          ),

          // Long gradual gradient: white → transparent
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenH * 0.55,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.4, 0.7, 1.0],
                  colors: [
                    Colors.white,
                    Colors.white,
                    Color(0xBBFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                ),
              ),
            ),
          ),

          // ── Content ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.forest,
                        color: Color(0xFF2E7D32),
                        size: 34,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l.get('landing_title'),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B2838),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _UserInfoCard(
                    userName: userName,
                    userRole: userRole,
                    dutyStatus: l.get('landing_user_status_on_duty'),
                    dutyDate: dutyDate,
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: GridView.builder(
                      itemCount: _features.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 1.05,
                          ),
                      itemBuilder: (context, index) {
                        final item = _features[index];
                        return _FunctionCard(
                          title: l.get(item.titleKey),
                          leadingIcon: item.leadingIcon,
                          trailingIcon: item.trailingIcon,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pushNamed(item.routeName);
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      l.get('version'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: _onBottomNavTapped,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: l.get('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map_rounded),
            label: l.get('maps'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.warning_amber_outlined),
            selectedIcon: const Icon(Icons.warning_amber_rounded),
            label: l.get('alerts'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_none_rounded),
            selectedIcon: const Icon(Icons.notifications_rounded),
            label: l.get('notifications'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: l.get('account'),
          ),
        ],
      ),
    );
  }
}

class _UserInfoCard extends StatelessWidget {
  final String userName;
  final String userRole;
  final String dutyStatus;
  final String dutyDate;

  const _UserInfoCard({
    required this.userName,
    required this.userRole,
    required this.dutyStatus,
    required this.dutyDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xAA2E7D32), Color(0xCC0B4D3B)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE7EFE9),
            ),
            padding: const EdgeInsets.all(4),
            child: ClipOval(
              child: Image.asset('assets/icons/icon.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  userRole,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE2F4E5),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Color(0xFF6DFF79),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        dutyStatus,
                        style: const TextStyle(
                          color: Color(0xFFE8FFEA),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  dutyDate,
                  style: const TextStyle(
                    color: Color(0xFFE2F4E5),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FunctionCard extends StatelessWidget {
  final String title;
  final IconData leadingIcon;
  final IconData trailingIcon;
  final VoidCallback? onTap;

  const _FunctionCard({
    required this.title,
    required this.leadingIcon,
    required this.trailingIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.09),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(leadingIcon, color: const Color(0xFF2F8E4D), size: 44),
                    Icon(
                      trailingIcon,
                      color: const Color(0xFF2A7A43),
                      size: 42,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF173B42),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCardData {
  final String titleKey;
  final String routeName;
  final IconData leadingIcon;
  final IconData trailingIcon;

  const _FeatureCardData({
    required this.titleKey,
    required this.routeName,
    required this.leadingIcon,
    required this.trailingIcon,
  });
}
