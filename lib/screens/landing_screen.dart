import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/settings_provider.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final l = context.watch<SettingsProvider>().l;

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
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 1),
                  // ── Logo ──
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/icons/icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    l.get('landing_title'),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1B2838),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(flex: 1),
                  // 2x2 Grid
                  Row(
                    children: [
                      const Expanded(
                        child: _LandingCard(title: '', isAccent: true),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: _LandingCard(title: '', isAccent: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _LandingCard(
                          title: l.get('landing_open_earthranger'),
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            final isIOS =
                                Theme.of(context).platform ==
                                TargetPlatform.iOS;
                            final appUrl = Uri.parse('earthranger://');
                            final storeUrl = isIOS
                                ? Uri.parse(
                                    'https://apps.apple.com/kw/app/earthranger/id1636950688',
                                  )
                                : Uri.parse(
                                    'https://play.google.com/store/apps/details?id=com.earthranger',
                                  );
                            try {
                              final launched = await launchUrl(
                                appUrl,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!launched) {
                                await launchUrl(
                                  storeUrl,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            } catch (e) {
                              try {
                                await launchUrl(
                                  storeUrl,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (e2) {
                                debugPrint('Could not launch: $e2');
                              }
                            }
                          },
                          isAccent: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _LandingCard(
                          title: l.get('landing_add_tree'),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pushNamed('/home');
                          },
                          isAccent: true,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(flex: 4),
                  Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      l.get('version'),
                      style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
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

class _LandingCard extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  final bool isAccent;

  const _LandingCard({required this.title, this.onTap, this.isAccent = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
