import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class PlantIdentificationScreen extends StatefulWidget {
  const PlantIdentificationScreen({super.key});

  @override
  State<PlantIdentificationScreen> createState() =>
      _PlantIdentificationScreenState();
}

class _PlantIdentificationScreenState extends State<PlantIdentificationScreen> {
  static final Uri _identifyUri = Uri.parse(
    'https://forestry.ifee.edu.vn/identify/plant',
  );

  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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
      ..loadRequest(_identifyUri);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<SettingsProvider>().l;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppTopToolbar(
        title: l.get('resource_identify_plant'),
        showBackButton: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (_loading)
            const ColoredBox(
              color: Color(0xE6FFFFFF),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accentGreen),
              ),
            ),
        ],
      ),
    );
  }
}
