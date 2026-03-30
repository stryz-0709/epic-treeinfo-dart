import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../widgets/glass_widgets.dart';
import 'landing_screen.dart';
import 'map_screen.dart';
import 'alerts_screen.dart';
import 'account_screen.dart';

/// Provides [switchTab] to descendants so any child can change the active tab.
class MainShellScope extends InheritedWidget {
  final ValueChanged<int> switchTab;

  const MainShellScope({
    super.key,
    required this.switchTab,
    required super.child,
  });

  static MainShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MainShellScope>();

  @override
  bool updateShouldNotify(MainShellScope old) => false;
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentTab = 0;

  void _switchTab(int index) {
    if (index == _currentTab) return;
    HapticFeedback.selectionClick();
    setState(() => _currentTab = index);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsProvider>().l;
    final navLabels = [
      l.get('home'),
      l.get('maps'),
      l.get('alerts'),
      l.get('notifications'),
      l.get('account'),
    ];

    return MainShellScope(
      switchTab: _switchTab,
      child: Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,
        body: IndexedStack(
          index: _currentTab,
          children: [
            const LandingScreen(),
            MapScreen(onBack: () => _switchTab(0)),
            AlertsScreen(onBack: () => _switchTab(0)),
            _buildNotificationsTab(l),
            const AccountScreen(),
          ],
        ),
        bottomNavigationBar: GlassBottomNavBar(
          selectedIndex: _currentTab,
          onTap: _switchTab,
          labels: navLabels,
        ),
      ),
    );
  }

  Widget _buildNotificationsTab(dynamic l) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTopToolbar(
        title: l.get('notifications'),
        showBackButton: true,
        onBack: () => _switchTab(0),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_off_outlined,
                  size: 56, color: Colors.black.withValues(alpha: 0.22)),
              const SizedBox(height: 16),
              Text(
                l.get('placeholder_coming_soon'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475467),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
