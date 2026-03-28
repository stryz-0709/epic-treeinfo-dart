import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/work_management_provider.dart';

class AppOpenCheckinLifecycle extends StatefulWidget {
  final Widget child;

  const AppOpenCheckinLifecycle({
    super.key,
    required this.child,
  });

  @override
  State<AppOpenCheckinLifecycle> createState() => _AppOpenCheckinLifecycleState();
}

class _AppOpenCheckinLifecycleState extends State<AppOpenCheckinLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _triggerCheckin());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerCheckin();
    }
  }

  Future<void> _triggerCheckin() async {
    if (!mounted) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final workProvider = context.read<WorkManagementProvider>();
    await workProvider.triggerAppOpenCheckin(authProvider: authProvider);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
