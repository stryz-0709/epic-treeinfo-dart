import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../widgets/glass_widgets.dart';
import 'forest_compartment_management_screen.dart';
import 'forest_resource_management_screen.dart';
import 'incident_management_screen.dart';
import 'landing_screen.dart';
import 'map_screen.dart';
import 'alerts_screen.dart';
import 'account_screen.dart';
import 'reports_screen.dart';
import 'schedule_management_screen.dart';
import 'work_management_screen.dart';

typedef OpenFunctionRoute = void Function(
  String routeName, {
  Object? arguments,
});

/// Provides shell controls to descendants.
class MainShellScope extends InheritedWidget {
  final ValueChanged<int> switchTab;
  final OpenFunctionRoute openFunctionRoute;

  const MainShellScope({
    super.key,
    required this.switchTab,
    required this.openFunctionRoute,
    required super.child,
  });

  static MainShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MainShellScope>();

  @override
  bool updateShouldNotify(MainShellScope old) => false;
}

class MainShell extends StatefulWidget {
  final int initialTab;

  const MainShell({super.key, this.initialTab = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const String _tabsRouteName = '/';

  int _currentTab = 0;
  bool _navStateUpdateScheduled = false;
  final GlobalKey<NavigatorState> _contentNavigatorKey =
      GlobalKey<NavigatorState>();
  _MainShellNavigatorObserver? _navigatorObserver;

  _MainShellNavigatorObserver get _resolvedNavigatorObserver =>
      _navigatorObserver ??= _MainShellNavigatorObserver(_onContentRouteChanged);

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab.clamp(0, 4).toInt();
    _navigatorObserver = _MainShellNavigatorObserver(_onContentRouteChanged);
  }

  void _onContentRouteChanged() {
    if (!mounted || _navStateUpdateScheduled) return;

    _navStateUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navStateUpdateScheduled = false;
      if (!mounted) return;
      setState(() {});
    });
  }

  bool get _isFunctionRouteVisible =>
      _contentNavigatorKey.currentState?.canPop() ?? false;

  void _handleBottomNavTap(int index) {
    final navigator = _contentNavigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }

    _switchTab(index);
  }

  void _switchTab(int index) {
    if (index == _currentTab) return;
    HapticFeedback.selectionClick();
    setState(() => _currentTab = index);
  }

  void _openFunctionRoute(String routeName, {Object? arguments}) {
    final navigator = _contentNavigatorKey.currentState;
    if (navigator == null) return;

    HapticFeedback.selectionClick();
    navigator.pushNamed(routeName, arguments: arguments);
  }

  Route<dynamic> _onGenerateContentRoute(RouteSettings settings) {
    switch (settings.name) {
      case _tabsRouteName:
        return MaterialPageRoute(
          settings: const RouteSettings(name: _tabsRouteName),
          builder: (_) => _buildTabsContent(),
        );
      case '/work-management':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const WorkManagementScreen(),
        );
      case '/compartment-management':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ForestCompartmentManagementScreen(),
        );
      case '/resource-management':
        final initialQuery = settings.arguments as String?;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ForestResourceManagementScreen(
            initialQuery: initialQuery,
          ),
        );
      case '/schedule-management':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ScheduleManagementScreen(),
        );
      case '/reports-management':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ReportsScreen(),
        );
      case '/patrol-management':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const IncidentManagementScreen(),
        );
      default:
        return MaterialPageRoute(
          settings: const RouteSettings(name: _tabsRouteName),
          builder: (_) => _buildTabsContent(),
        );
    }
  }

  Widget _buildTabsContent() {
    return IndexedStack(
      index: _currentTab,
      children: [
        const LandingScreen(),
        MapScreen(onBack: () => _switchTab(0)),
        AlertsScreen(onBack: () => _switchTab(0)),
        _buildNotificationsTab(context.read<SettingsProvider>().l),
        const AccountScreen(),
      ],
    );
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
      openFunctionRoute: _openFunctionRoute,
      child: Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,
        body: Navigator(
          key: _contentNavigatorKey,
          initialRoute: _tabsRouteName,
          observers: [_resolvedNavigatorObserver],
          onGenerateRoute: _onGenerateContentRoute,
        ),
        bottomNavigationBar: GlassBottomNavBar(
          selectedIndex: _isFunctionRouteVisible ? -1 : _currentTab,
          onTap: _handleBottomNavTap,
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

class _MainShellNavigatorObserver extends NavigatorObserver {
  final VoidCallback onChanged;

  _MainShellNavigatorObserver(this.onChanged);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onChanged();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    onChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onChanged();
  }
}
