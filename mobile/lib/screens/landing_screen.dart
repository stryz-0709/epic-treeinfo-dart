import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/external_app_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';
import 'main_shell.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  static const List<_FeatureCardData> _features = [
    _FeatureCardData(
      titleKey: 'landing_function_work',
      routeName: '/work-management',
      icon: Icons.trending_up_rounded,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_incident',
      routeName: '/compartment-management',
      icon: Icons.account_tree_rounded,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_resource',
      routeName: '/resource-management',
      icon: Icons.eco_rounded,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_schedule',
      routeName: '/schedule-management',
      icon: Icons.calendar_today_rounded,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_reports',
      routeName: '/reports-management',
      icon: Icons.bar_chart_rounded,
    ),
    _FeatureCardData(
      titleKey: 'landing_function_patrol',
      routeName: '/patrol-management',
      icon: Icons.explore_rounded,
    ),
  ];

  final List<String> _uploadedImages = [];
  final ImagePicker _picker = ImagePicker();
  late final PageController _carouselController;
  Timer? _carouselTimer;
  int _carouselIndex = 0;

  @override
  void initState() {
    super.initState();
    _carouselController = PageController();
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted ||
          !_carouselController.hasClients ||
          _uploadedImages.isEmpty) {
        return;
      }
      final next = (_carouselIndex + 1) % _uploadedImages.length;
      _carouselController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _carouselController.dispose();
    super.dispose();
  }

  Future<void> _pickCarouselImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _uploadedImages.addAll(picked.map((e) => e.path));
      _carouselIndex = 0;
      if (_carouselController.hasClients) {
        _carouselController.jumpToPage(0);
      }
    });
  }

  String _resolvedUserName(AuthProvider auth, SettingsProvider settings) {
    final displayName = auth.mobileDisplayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final username = auth.mobileUsername?.trim();
    if (username != null && username.isNotEmpty) return username;
    return settings.l.get('landing_user_name');
  }

  String _resolvedUserRole(AuthProvider auth, SettingsProvider settings) {
    if (auth.isLeaderSession) {
      return settings.l.get('work_calendar_role_leader');
    }
    if (auth.isRangerSession) {
      return settings.l.get('work_calendar_role_ranger');
    }
    return settings.l.get('landing_user_role');
  }

  String _formattedDutyDate(String locale) {
    final n = DateTime.now();
    if (locale == 'en') {
      const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const mo = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${wd[n.weekday - 1]}, ${mo[n.month - 1]} ${n.day} ${n.year}';
    }
    const wd = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];
    return '${wd[n.weekday - 1]}, ${n.day}/${n.month}/${n.year}';
  }

  void _showEarthRangerUnavailable(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleFeatureTap(_FeatureCardData feature) async {
    HapticFeedback.lightImpact();

    if (feature.routeName == '/patrol-management') {
      final unavailableMessage = context.read<SettingsProvider>().l.get(
        'landing_open_earthranger_failed',
      );
      final opened = await EarthRangerLauncher.open();
      if (!opened) {
        _showEarthRangerUnavailable(unavailableMessage);
      }
      return;
    }

    final shell = MainShellScope.of(context);
    if (shell != null) {
      shell.openFunctionRoute(feature.routeName);
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushNamed(feature.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final l = settings.l;

    final userName = _resolvedUserName(auth, settings);
    final userRole = _resolvedUserRole(auth, settings);
    final dutyDate = _formattedDutyDate(settings.locale);

    final canUpload = !auth.isRangerSession;
    final hasImages = _uploadedImages.isNotEmpty;
    final showCarousel = hasImages || canUpload;

    return Stack(
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
              errorBuilder: (_, error, stackTrace) =>
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
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.forest,
                      color: Color(0xFF2E7D32),
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.get('landing_title'),
                        style: AppTypography.title.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1B2838),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _UserInfoCard(
                  userName: userName,
                  userRole: userRole,
                  dutyStatus: l.get('landing_user_status_on_duty'),
                  dutyDate: dutyDate,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final shell = MainShellScope.of(context);
                    if (shell != null) {
                      shell.switchTab(4);
                    } else {
                      Navigator.of(context).pushNamed('/account');
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      const horizontalCardGap = 24.0;
                      final cardW = (screenW - 28 - horizontalCardGap) / 2;
                      const minRatio = 1.72;
                      final compactCardH = cardW / minRatio;
                      final compactGridH =
                          compactCardH * 3 + (horizontalCardGap * 2);
                      const reservedBottom = 88.0;
                      final usableHeight = (box.maxHeight - reservedBottom)
                          .clamp(0.0, box.maxHeight);

                      final carouselH = showCarousel
                          ? ((screenW - 28) * 9 / 16).clamp(70.0, 130.0)
                          : 0.0;
                      final gapH = showCarousel ? 14.0 : 0.0;
                      final maxGridH = (usableHeight - carouselH - gapH).clamp(
                        0.0,
                        usableHeight,
                      );
                      final gridH = compactGridH <= maxGridH
                          ? compactGridH
                          : maxGridH;
                      final cardH = ((gridH - horizontalCardGap) / 3).clamp(
                        1.0,
                        10000.0,
                      );
                      final ratio = (cardW / cardH).clamp(minRatio, 10.0);

                      return Column(
                        children: [
                          SizedBox(
                            height: gridH,
                            child: GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: _features.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: horizontalCardGap,
                                    mainAxisSpacing: 18,
                                    childAspectRatio: ratio,
                                  ),
                              itemBuilder: (context, index) {
                                final f = _features[index];
                                return _FunctionCard(
                                  title: l.get(f.titleKey),
                                  icon: f.icon,
                                  onTap: () => unawaited(_handleFeatureTap(f)),
                                );
                              },
                            ),
                          ),
                          if (showCarousel) ...[
                            SizedBox(height: gapH),
                            SizedBox(
                              height: carouselH,
                              child: hasImages
                                  ? _CarouselCard(
                                      images: _uploadedImages,
                                      controller: _carouselController,
                                      onPageChanged: (i) =>
                                          setState(() => _carouselIndex = i),
                                      currentIndex: _carouselIndex,
                                      canEdit: canUpload,
                                      onEditTap: _pickCarouselImages,
                                    )
                                  : _CarouselPlaceholder(
                                      label: l.get('carousel_add_media'),
                                      onTap: _pickCarouselImages,
                                    ),
                            ),
                          ],
                          const SizedBox(height: reservedBottom),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MaterialGradientFeatureIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  const _MaterialGradientFeatureIcon({required this.icon, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF43A047).withValues(alpha: 0.32),
                blurRadius: 18,
              ),
            ],
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF81C784), Color(0xFF1B5E20)],
          ).createShader(bounds),
          child: Icon(icon, size: size, color: Colors.white),
        ),
      ],
    );
  }
}

class _UserInfoCard extends StatelessWidget {
  final String userName;
  final String userRole;
  final String dutyStatus;
  final String dutyDate;
  final VoidCallback? onTap;

  const _UserInfoCard({
    required this.userName,
    required this.userRole,
    required this.dutyStatus,
    required this.dutyDate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        borderRadius: 20,
        padding: EdgeInsets.zero,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xCC2E7D32),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: ClipOval(
                  child: Image.asset(
                    'assets/icons/icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      userRole,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF6DFF79),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                dutyStatus,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            dutyDate,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.55),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FunctionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  const _FunctionCard({required this.title, required this.icon, this.onTap});

  String _displayTitle(String source) {
    final upper = source.toUpperCase().trim();
    if (upper == 'LỊCH LÀM VIỆC') {
      return 'LỊCH\nLÀM VIỆC';
    }

    final words = upper
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length <= 2) return upper;

    return '${words.take(2).join(' ')}\n${words.skip(2).join(' ')}';
  }

  @override
  Widget build(BuildContext context) {
    final titleUpper = _displayTitle(title);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        splashColor: AppColors.accentGreen.withValues(alpha: 0.10),
        highlightColor: Colors.white.withValues(alpha: 0.06),
        child: GlassCard(
          borderRadius: 18,
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 112;
              final iconSize = compact ? 28.0 : 34.0;

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MaterialGradientFeatureIcon(icon: icon, size: iconSize),
                  SizedBox(height: compact ? 4 : 6),
                  Text(
                    titleUpper,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF101820),
                      fontSize: compact ? 13.2 : 14.2,
                      fontWeight: FontWeight.w700,
                      height: 1.14,
                      letterSpacing: 0.08,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CarouselCard extends StatelessWidget {
  final List<String> images;
  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final int currentIndex;
  final bool canEdit;
  final VoidCallback? onEditTap;

  const _CarouselCard({
    required this.images,
    required this.controller,
    required this.onPageChanged,
    required this.currentIndex,
    this.canEdit = false,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            PageView.builder(
              controller: controller,
              onPageChanged: onPageChanged,
              itemCount: images.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(5),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildImage(images[i]),
                ),
              ),
            ),
            if (images.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) {
                    final active = i == currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    );
                  }),
                ),
              ),
            if (canEdit)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: onEditTap,
                  child: GlassCard(
                    borderRadius: 999,
                    padding: const EdgeInsets.all(8),
                    tintColor: const Color(0xFF2E7D32),
                    child: const Icon(
                      Icons.add_photo_alternate_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String path) {
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, error, stackTrace) => _errorPlaceholder(),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, error, stackTrace) => _errorPlaceholder(),
    );
  }

  Widget _errorPlaceholder() {
    return Container(
      color: const Color(0xFFE8F5E9),
      child: const Center(
        child: Icon(Icons.image_rounded, color: Color(0xFF81C784), size: 28),
      ),
    );
  }
}

class _CarouselPlaceholder extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _CarouselPlaceholder({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF2E7D32,
                          ).withValues(alpha: 0.22),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                  ),
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF66BB6A), Color(0xFF1B5E20)],
                    ).createShader(bounds),
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF555555),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCardData {
  final String titleKey;
  final String routeName;
  final IconData icon;

  const _FeatureCardData({
    required this.titleKey,
    required this.routeName,
    required this.icon,
  });
}
