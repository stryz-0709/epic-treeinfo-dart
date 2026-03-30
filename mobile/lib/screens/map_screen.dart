import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class MapScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const MapScreen({super.key, this.onBack});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final erUrl = dotenv.env['ER_WEB_URL'] ?? 'https://epictech.pamdas.org';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(erUrl));
  }

  @override
  Widget build(BuildContext context) {
    context.read<AuthProvider>();
    final l = context.read<SettingsProvider>().l;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppTopToolbar(
        title: l.get('maps'),
        showBackButton: true,
        onBack: widget.onBack,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: WebViewWidget(controller: _controller),
          ),
          if (_loading)
            const ColoredBox(
              color: Color(0xE6FFFFFF),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.accentGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
