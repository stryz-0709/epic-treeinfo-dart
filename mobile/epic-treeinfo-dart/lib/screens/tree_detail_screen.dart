import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tree_provider.dart';
import '../models/tree_model.dart';
import '../services/app_notification.dart';
import '../services/earthranger_auth.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class TreeDetailScreen extends StatefulWidget {
  final String queryId;
  const TreeDetailScreen({super.key, required this.queryId});

  @override
  State<TreeDetailScreen> createState() => _TreeDetailScreenState();
}

class _TreeDetailScreenState extends State<TreeDetailScreen>
    with TickerProviderStateMixin {
  // ── Image carousel ──
  final PageController _carouselController = PageController(initialPage: 5000);
  int _currentPage = 0;

  // ── Scroll / snap state ──
  final ScrollController _scrollController = ScrollController();
  double _spacerHeight = 0;
  bool _isScrolledUp = false;

  // ── Pull-down to full-image mode ──
  bool _isFullImageMode = false;
  bool _isPullingDown = false;
  double _pullDownStartY = 0;
  double _pullTranslateY = 0;
  AnimationController? _snapAnimController;

  // ── Spring scroll controller (for scroll-based spring animations) ──
  AnimationController? _scrollSpringController;

  // ── Scroll-based zoom fraction ──
  double _zoomFraction = 0;

  // ── Full-image swipe-up exit ──
  double _fullImageTouchStartY = 0;
  double _fullImageTouchStartX = 0;
  bool _fullImageSwipeDecided = false;
  bool _fullImageSwipeTracking = false;

  bool _matchesCurrentTreeQuery(TreeModel? tree, String queryId) {
    if (tree == null) return false;

    final normalizedQuery = queryId.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return false;

    final treeId = tree.treeId?.trim().toLowerCase();
    final nfcId = tree.nfcId?.trim().toLowerCase();

    return normalizedQuery == treeId || normalizedQuery == nfcId;
  }

  void _ensureTreeLoadedForQuery() {
    if (!mounted) return;

    final provider = context.read<TreeProvider>();
    final isAlreadyLoaded = _matchesCurrentTreeQuery(
      provider.currentTree,
      widget.queryId,
    );

    if (!isAlreadyLoaded && !provider.isLoading) {
      provider.searchTree(widget.queryId);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTreeLoadedForQuery();
    });
  }

  @override
  void didUpdateWidget(covariant TreeDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queryId != widget.queryId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureTreeLoadedForQuery();
      });
    }
  }

  @override
  void dispose() {
    _carouselController.dispose();
    _scrollController.dispose();
    _snapAnimController?.dispose();
    _scrollSpringController?.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════
  // Scroll listener — drives indicator fade, snap icon direction
  // ════════════════════════════════════════════════════════════════════

  void _onScroll() {
    if (_spacerHeight <= 0) return;
    final scrollY = _scrollController.offset;
    final newFraction = (scrollY / (_spacerHeight * 0.7)).clamp(0.0, 1.0);
    final newScrolled = scrollY > _spacerHeight / 3;
    if (newFraction != _zoomFraction || newScrolled != _isScrolledUp) {
      setState(() {
        _zoomFraction = newFraction;
        _isScrolledUp = newScrolled;
      });
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Snap scroll (matching Android ACTION_UP snap)
  // ════════════════════════════════════════════════════════════════════

  void _snapScroll() {
    if (_spacerHeight <= 0 || !_scrollController.hasClients) return;
    if (_scrollSpringController?.isAnimating == true) return;
    final scrollY = _scrollController.offset;
    final threshold = _spacerHeight / 3;
    // Snap target: cards sit at y ≈ 280 from top of screen
    final snapTarget = (_spacerHeight - 100).clamp(0.0, _spacerHeight);

    if (scrollY > 0 && scrollY < _spacerHeight) {
      if (scrollY > threshold) {
        HapticFeedback.mediumImpact();
        _springScrollTo(snapTarget);
      } else {
        HapticFeedback.mediumImpact();
        _springScrollTo(0);
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Spring-animated scroll helper
  // ════════════════════════════════════════════════════════════════════

  void _springScrollTo(double target) {
    final from = _scrollController.offset;
    if ((from - target).abs() < 1) return;
    _scrollSpringController?.dispose();
    _scrollSpringController = AnimationController.unbounded(
      vsync: this,
      value: 0,
    );

    _scrollSpringController!.addListener(() {
      if (_scrollController.hasClients) {
        final value = _scrollSpringController!.value;
        final scrollPos = from + (target - from) * value;
        _scrollController.jumpTo(
          scrollPos.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
    });

    const spring = SpringDescription(mass: 1, stiffness: 100, damping: 14);
    _scrollSpringController!.animateWith(SpringSimulation(spring, 0, 1, 0));
  }

  // ════════════════════════════════════════════════════════════════════
  // Scroll toggle button
  // ════════════════════════════════════════════════════════════════════

  void _toggleScrollPosition() {
    if (_isFullImageMode) {
      _animateFromFullImage();
    } else if (_isScrolledUp) {
      HapticFeedback.mediumImpact();
      _springScrollTo(0);
    } else {
      HapticFeedback.mediumImpact();
      final target = (_spacerHeight - 100).clamp(0.0, _spacerHeight);
      _springScrollTo(target);
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Pull-down → full image mode animations
  // ════════════════════════════════════════════════════════════════════

  void _animateToFullImage(double fromTranslateY) {
    HapticFeedback.mediumImpact();
    final screenH = MediaQuery.sizeOf(context).height;
    _snapAnimController?.dispose();
    _snapAnimController = AnimationController(vsync: this);
    final tween = Tween<double>(begin: fromTranslateY, end: screenH);

    _snapAnimController!.addListener(() {
      setState(() {
        _pullTranslateY = tween.evaluate(_snapAnimController!);
        final maxPull = _spacerHeight * 0.7;
        _zoomFraction = (_pullTranslateY / maxPull).clamp(0.0, 1.0);
      });
    });
    _snapAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isFullImageMode = true;
          _pullTranslateY = 0;
        });
      }
    });
    final spring = SpringDescription(mass: 1, stiffness: 300, damping: 25);
    _snapAnimController!.animateWith(SpringSimulation(spring, 0, 1, 0));
  }

  void _animateFromFullImage() {
    HapticFeedback.mediumImpact();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);

    // Smoothly transition: set _isFullImageMode false but keep carousel expanded
    final expandAmount = (MediaQuery.sizeOf(context).height - _spacerHeight)
        .clamp(0.0, MediaQuery.sizeOf(context).height);
    setState(() {
      _isFullImageMode = false;
      _pullTranslateY = expandAmount;
      _zoomFraction = 1.0;
    });

    // Spring-animate back to default
    _animateSnapBack(expandAmount);
  }

  void _animateSnapBack(double fromTranslateY) {
    _snapAnimController?.dispose();
    _snapAnimController = AnimationController(vsync: this);
    final tween = Tween<double>(begin: fromTranslateY, end: 0.0);

    _snapAnimController!.addListener(() {
      setState(() {
        _pullTranslateY = tween.evaluate(_snapAnimController!);
        final maxPull = _spacerHeight * 0.7;
        _zoomFraction = (_pullTranslateY / maxPull).clamp(0.0, 1.0);
      });
    });
    _snapAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _pullTranslateY = 0;
          _zoomFraction = 0;
        });
      }
    });
    final spring = SpringDescription(mass: 1, stiffness: 300, damping: 25);
    _snapAnimController!.animateWith(SpringSimulation(spring, 0, 1, 0));
  }

  // ════════════════════════════════════════════════════════════════════
  // Edit dialog
  // ════════════════════════════════════════════════════════════════════

  void _showEditDialog(TreeModel tree) {
    final l = context.read<SettingsProvider>().l;
    final treeIdC = TextEditingController(text: tree.treeId ?? '');
    final speciesC = TextEditingController(text: tree.species ?? '');
    final ageC = TextEditingController(text: tree.age ?? '');
    final heightC = TextEditingController(text: tree.height ?? '');
    final diameterC = TextEditingController(text: tree.diameter ?? '');
    final canopyC = TextEditingController(text: tree.canopy ?? '');

    final conditions = [
      l.get('condition_good'),
      l.get('condition_average'),
      l.get('condition_bad'),
    ];
    var selectedCondition = conditions[0];
    final currentCond = (tree.condition ?? '').toLowerCase();
    if (currentCond.contains('trung bình') || currentCond.contains('average')) {
      selectedCondition = conditions[1];
    } else if (currentCond.contains('xấu') ||
        currentCond.contains('tệ') ||
        currentCond.contains('bad')) {
      selectedCondition = conditions[2];
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            final isDark = Theme.of(ctx2).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkCardBg : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                l.get('edit_tree'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${l.get('nfc_id')}: ${tree.nfcId ?? l.get('not_available')}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _editField(treeIdC, l.get('tree_id_label')),
                    _editField(speciesC, l.get('species')),
                    _editField(ageC, l.get('age')),
                    _editField(heightC, l.get('height')),
                    _editField(diameterC, l.get('diameter')),
                    _editField(canopyC, l.get('canopy')),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCondition,
                      items: conditions
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedCondition = v);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: l.get('condition'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: Text(l.get('cancel')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final provider = context.read<TreeProvider>();
                    final ok = await provider.updateTree(
                      treeId: treeIdC.text.trim(),
                      species: speciesC.text.trim(),
                      age: ageC.text.trim(),
                      height: heightC.text.trim(),
                      diameter: diameterC.text.trim(),
                      canopy: canopyC.text.trim(),
                      condition: selectedCondition,
                    );
                    if (ctx2.mounted) Navigator.pop(ctx2);
                    if (mounted) {
                      AppNotification.showTop(
                        context,
                        message: ok
                            ? l.get('update_success')
                            : l.get('update_failed'),
                        type: ok
                            ? AppNotificationType.success
                            : AppNotificationType.error,
                      );
                    }
                  },
                  child: Text(l.get('save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _editField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Settings sheet (same as home page)
  // ════════════════════════════════════════════════════════════════════

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer<SettingsProvider>(
          builder: (ctx2, settings, _) {
            final isDark = Theme.of(ctx2).brightness == Brightness.dark;
            final bgColor = isDark ? AppColors.darkCardBg : Colors.white;
            final textColor = isDark
                ? AppColors.darkTextPrimary
                : AppColors.textPrimary;

            return Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    settings.l.get('language'),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _settingsChip(
                        label: settings.l.get('vietnamese'),
                        selected: settings.locale == 'vi',
                        onTap: () => settings.setLocale('vi'),
                      ),
                      const SizedBox(width: 8),
                      _settingsChip(
                        label: settings.l.get('english'),
                        selected: settings.locale == 'en',
                        onTap: () => settings.setLocale('en'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    settings.l.get('theme'),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _settingsChip(
                        label: settings.l.get('light_mode'),
                        selected: settings.themeMode == ThemeMode.light,
                        onTap: () => settings.setThemeMode(ThemeMode.light),
                      ),
                      const SizedBox(width: 8),
                      _settingsChip(
                        label: settings.l.get('dark_mode'),
                        selected: settings.themeMode == ThemeMode.dark,
                        onTap: () => settings.setThemeMode(ThemeMode.dark),
                      ),
                      const SizedBox(width: 8),
                      _settingsChip(
                        label: settings.l.get('system_mode'),
                        selected: settings.themeMode == ThemeMode.system,
                        onTap: () => settings.setThemeMode(ThemeMode.system),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _settingsChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentGreen.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.accentGreen
                : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accentGreen : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsProvider>().l;
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? AppColors.darkTextPrimary
        : const Color(0xFF1B2838);

    return Consumer<TreeProvider>(
      builder: (context, provider, _) {
        // Loading
        if (provider.isLoading && provider.currentTree == null) {
          return _buildLoading(isDark);
        }

        // Not found — handled on home screen, pop back
        if (provider.notFound) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
          return _buildLoading(isDark);
        }

        // Error
        if (provider.error != null && provider.currentTree == null) {
          return _buildError(l, provider, textColor, isDark);
        }

        final tree = provider.currentTree;
        if (tree == null) {
          return _buildLoading(isDark);
        }

        final imageUrls = tree.imageUrls;
        final screenH = MediaQuery.sizeOf(context).height;

        // Spacer so tree ID + species + condition are fully visible at bottom
        _spacerHeight = screenH - 250;
        if (_spacerHeight < 300) _spacerHeight = 300;

        // Image carousel height matches spacer (area above cards)
        final carouselHeight = _spacerHeight;

        // Indicator fade based on scroll
        final indicatorAlpha = (1.0 - (_zoomFraction / 0.5).clamp(0.0, 1.0));

        return Scaffold(
          backgroundColor: isDark ? Colors.black : Colors.white,
          body: _buildDefaultMode(
            imageUrls,
            tree,
            l,
            auth,
            provider,
            isDark,
            textColor,
            carouselHeight,
            indicatorAlpha,
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Default + scrolled-up mode
  // ════════════════════════════════════════════════════════════════════

  Widget _buildDefaultMode(
    List<String> imageUrls,
    TreeModel tree,
    dynamic l,
    AuthProvider auth,
    TreeProvider provider,
    bool isDark,
    Color textColor,
    double carouselHeight,
    double indicatorAlpha,
  ) {
    // Theme-aware card colors
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final primaryText = isDark ? Colors.white : const Color(0xFF1B2838);
    final secondaryText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    // Carousel expands during pull-down AND scroll-up (zoom effect)
    final screenH = MediaQuery.sizeOf(context).height;
    final scrollExpansion = _scrollController.hasClients
        ? (_scrollController.offset / _spacerHeight).clamp(0.0, 1.0) *
              (screenH - _spacerHeight)
        : 0.0;
    final effectiveCarouselHeight = _isFullImageMode
        ? screenH
        : (_spacerHeight + scrollExpansion + _pullTranslateY).clamp(
            _spacerHeight,
            screenH,
          );

    Widget content = Stack(
      children: [
        // ── Fixed background: looping image carousel ──
        if (imageUrls.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: effectiveCarouselHeight,
            child: PageView.builder(
              controller: _carouselController,
              physics: (_isScrolledUp && !_isFullImageMode)
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (i) {
                setState(() => _currentPage = i % imageUrls.length);
              },
              itemBuilder: (ctx, i) {
                final realIndex = i % imageUrls.length;
                return _AuthenticatedImage(
                  url: imageUrls[realIndex],
                  fit: BoxFit.cover,
                );
              },
            ),
          )
        else
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: effectiveCarouselHeight,
            child: Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('\u{1F333}', style: TextStyle(fontSize: 72)),
                    const SizedBox(height: 8),
                    Text(
                      l.get('no_images'),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Gradient overlay pinned to bottom of visible image area ──
        Builder(
          builder: (context) {
            // Gradient always at full intensity, pinned to image bottom
            return Stack(
              children: [
                // Gradient
                Positioned(
                  left: 0,
                  right: 0,
                  top: effectiveCarouselHeight - 100,
                  height: 100,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            (isDark ? Colors.black : Colors.white).withValues(
                              alpha: 0,
                            ),
                            isDark ? Colors.black : Colors.white,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Fill below image
                if (!_isFullImageMode)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: effectiveCarouselHeight,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        color: isDark ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        // ── Page indicator (default mode) ──
        if (imageUrls.length > 1 && !_isFullImageMode)
          Positioned(
            top:
                _spacerHeight -
                40 +
                _pullTranslateY -
                (_scrollController.hasClients ? _scrollController.offset : 0.0),
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: indicatorAlpha.clamp(0.0, 1.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    imageUrls.length,
                    (i) => Container(
                      width: _currentPage == i ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: _currentPage == i
                            ? AppColors.accentGreen
                            : Colors.white38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ── Readability overlay behind cards (fades in as scrolled up) ──
        if (!_isFullImageMode)
          Builder(
            builder: (context) {
              final scrollOnlyFraction = _scrollController.hasClients
                  ? (_scrollController.offset / (_spacerHeight * 0.7)).clamp(
                      0.0,
                      1.0,
                    )
                  : 0.0;
              return Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: (isDark ? Colors.black : Colors.white).withValues(
                      alpha: (scrollOnlyFraction * 0.88).clamp(0.0, 0.88),
                    ),
                  ),
                ),
              );
            },
          ),

        // ── Scrollable content layer ──
        if (!_isFullImageMode)
          Transform.translate(
            offset: Offset(0, _pullTranslateY),
            child: Listener(
              onPointerDown: (e) {
                _pullDownStartY = e.position.dy;
                _isPullingDown = false;
                _snapAnimController?.stop();
                _scrollSpringController?.stop();
              },
              onPointerMove: (e) {
                final scrollY = _scrollController.hasClients
                    ? _scrollController.offset
                    : 0.0;

                // Pull-down at top of scroll
                if (scrollY <= 0 && !_isFullImageMode) {
                  final rawDy = e.position.dy - _pullDownStartY;
                  if (rawDy > 15 && !_isPullingDown) {
                    _isPullingDown = true;
                  }
                  if (_isPullingDown && rawDy > 0) {
                    final dampedPull = (rawDy * 0.5).clamp(
                      0.0,
                      MediaQuery.sizeOf(context).height.toDouble(),
                    );
                    setState(() {
                      _pullTranslateY = dampedPull;
                      final maxPull = _spacerHeight * 0.7;
                      _zoomFraction = (dampedPull / maxPull).clamp(0.0, 1.0);
                    });
                  }
                }
              },
              onPointerUp: (e) {
                if (_isPullingDown && _pullTranslateY > 0) {
                  _isPullingDown = false;
                  final maxPull = _spacerHeight * 0.7;
                  final threshold = maxPull * 0.3;
                  if (_pullTranslateY > threshold) {
                    _animateToFullImage(_pullTranslateY);
                  } else {
                    _animateSnapBack(_pullTranslateY);
                  }
                } else {
                  _isPullingDown = false;
                  // Snap scroll with delay
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) _snapScroll();
                  });
                }
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  // Image spacer — forwards horizontal swipes to carousel
                  SliverToBoxAdapter(
                    child: GestureDetector(
                      onHorizontalDragUpdate: (details) {
                        if (!_isScrolledUp && _carouselController.hasClients) {
                          _carouselController.position.moveTo(
                            _carouselController.position.pixels -
                                details.delta.dx,
                          );
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        if (!_isScrolledUp && _carouselController.hasClients) {
                          final page = _carouselController.page;
                          if (page != null) {
                            final v = details.primaryVelocity ?? 0;
                            int target;
                            if (v < -300) {
                              target = page.ceil();
                            } else if (v > 300) {
                              target = page.floor();
                            } else {
                              target = page.round();
                            }
                            _carouselController.animateToPage(
                              target,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        }
                      },
                      behavior: HitTestBehavior.translucent,
                      child: SizedBox(height: _spacerHeight),
                    ),
                  ),

                  // ── Tree ID pill + scroll toggle ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: cardBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.eco,
                                    color: AppColors.accentGreen,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      tree.display(
                                        tree.treeId,
                                        l.get('not_available'),
                                      ),
                                      style: TextStyle(
                                        color: primaryText,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              _toggleScrollPosition();
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: cardBg,
                                shape: BoxShape.circle,
                                border: Border.all(color: cardBorder),
                              ),
                              child: AnimatedRotation(
                                turns: _isScrolledUp ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.keyboard_arrow_up,
                                  color: primaryText,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Species card ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.get('species'),
                                    style: TextStyle(
                                      color: secondaryText,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tree.display(
                                      tree.species,
                                      l.get('not_available'),
                                    ),
                                    style: TextStyle(
                                      color: primaryText,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.accentGreen.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.park,
                                color: AppColors.accentGreen,
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // ── Condition card ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ConditionCard(
                        condition: tree.display(
                          tree.condition,
                          l.get('not_available'),
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // ═══════ Detail cards (visible on scroll-up) ═══════

                  // Stats grid
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _StatsGrid(tree: tree, l: l),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // Location map
                  if (tree.latitude != null && tree.longitude != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _MapCard(
                          latitude: tree.latitude!,
                          longitude: tree.longitude!,
                          l: l,
                        ),
                      ),
                    ),

                  if (tree.latitude != null && tree.longitude != null)
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // History
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _SectionCard(
                        title: l.get('history'),
                        icon: Icons.history,
                        children: [
                          _InfoRow(
                            label: l.get('created_at'),
                            value: tree.display(
                              tree.createdAt,
                              l.get('not_available'),
                            ),
                          ),
                          _InfoRow(
                            label: l.get('creator'),
                            value: tree.display(
                              tree.creator,
                              l.get('not_available'),
                            ),
                          ),
                          _InfoRow(
                            label: l.get('last_reported'),
                            value: tree.display(
                              tree.lastReported,
                              l.get('not_available'),
                            ),
                          ),
                          _InfoRow(
                            label: l.get('updater'),
                            value: tree.display(
                              tree.updater,
                              l.get('not_available'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // Technical
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _SectionCard(
                        title: l.get('technical'),
                        icon: Icons.developer_board_outlined,
                        children: [
                          _InfoRow(
                            label: l.get('event_status'),
                            value: tree.display(
                              tree.eventStatus,
                              l.get('not_available'),
                            ),
                          ),
                          _InfoRow(
                            label: l.get('sn'),
                            value: tree.display(
                              tree.sn,
                              l.get('not_available'),
                            ),
                          ),
                          _InfoRow(
                            label: l.get('synced_at'),
                            value: tree.display(
                              tree.syncedAt,
                              l.get('not_available'),
                            ),
                          ),
                          _InfoRow(
                            label: l.get('nfc_id'),
                            value: tree.display(
                              tree.nfcId,
                              l.get('not_available'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),

        // ── Full image mode: page indicator at bottom ──
        if (_isFullImageMode && imageUrls.length > 1)
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                imageUrls.length,
                (i) => Container(
                  width: _currentPage == i ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _currentPage == i
                        ? AppColors.accentGreen
                        : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),

        // ── Full image mode: swipe up hint ──
        if (_isFullImageMode)
          const Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Icon(
                Icons.keyboard_arrow_up,
                color: Colors.white38,
                size: 28,
              ),
            ),
          ),

        // ── Top bar ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GlassCircleButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  Row(
                    children: [
                      GlassCircleButton(
                        icon: Icons.refresh,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          provider.refresh();
                        },
                      ),
                      const SizedBox(width: 8),
                      GlassCircleButton(
                        icon: Icons.settings_outlined,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _showSettingsSheet();
                        },
                      ),
                      if (auth.isAdmin) ...[
                        const SizedBox(width: 8),
                        GlassCircleButton(
                          icon: Icons.edit_outlined,
                          iconColor: AppColors.accentGreen,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            _showEditDialog(tree);
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Loading overlay
        if (provider.isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
      ],
    );

    // Always wrap in GestureDetector to preserve widget tree (and carousel
    // page position) across full-image mode transitions. Null callbacks mean
    // the recogniser is not registered, so scrolling works normally.
    content = GestureDetector(
      onVerticalDragStart: _isFullImageMode
          ? (d) {
              _fullImageTouchStartY = d.globalPosition.dy;
              _fullImageTouchStartX = d.globalPosition.dx;
              _fullImageSwipeDecided = false;
              _fullImageSwipeTracking = false;
            }
          : null,
      onVerticalDragUpdate: _isFullImageMode
          ? (d) {
              if (!_fullImageSwipeDecided) {
                final adx = (d.globalPosition.dx - _fullImageTouchStartX).abs();
                final rawDy = d.globalPosition.dy - _fullImageTouchStartY;
                if (adx > 25 || rawDy.abs() > 25) {
                  _fullImageSwipeDecided = true;
                  if (rawDy < -25 && rawDy.abs() > adx * 1.2) {
                    _fullImageSwipeTracking = true;
                  }
                }
              }
            }
          : null,
      onVerticalDragEnd: _isFullImageMode
          ? (d) {
              if (_fullImageSwipeTracking) {
                _fullImageSwipeTracking = false;
                _animateFromFullImage();
              }
            }
          : null,
      child: content,
    );

    return content;
  }

  // ════════════════════════════════════════════════════════════════════
  // Loading state
  // ════════════════════════════════════════════════════════════════════

  Widget _buildLoading(bool isDark) {
    final screenH = MediaQuery.sizeOf(context).height;
    final bgColor = isDark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ── Background image ──
          Positioned(
            top: screenH * 0.15,
            left: 0,
            right: 0,
            bottom: 0,
            child: Image.asset(
              'assets/icons/background.jpeg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, e, s) => Container(
                color: isDark ? const Color(0xFF1B2838) : Colors.white,
              ),
            ),
          ),

          // ── Gradient overlay ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenH * 0.55,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.4, 0.7, 1.0],
                  colors: [
                    bgColor,
                    bgColor,
                    bgColor.withValues(alpha: 0.73),
                    bgColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),

          // ── Centered spinner ──
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Error state
  // ════════════════════════════════════════════════════════════════════

  Widget _buildError(
    dynamic l,
    TreeProvider provider,
    Color textColor,
    bool isDark,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppColors.error),
                const SizedBox(height: 16),
                Text(
                  l.get('fetch_failed'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.error ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 24),
                GreenButton(
                  text: l.get('go_back'),
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Authenticated Image Widget
// ══════════════════════════════════════════════════════════════════════

class _AuthenticatedImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const _AuthenticatedImage({required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final token = EarthRangerAuth.cachedToken;
    final headers = token != null
        ? {'Authorization': 'Bearer $token'}
        : <String, String>{};

    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
      fit: fit,
      placeholder: (context1, url1) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
      ),
      errorWidget: (context2, url2, error) => Container(
        color: Colors.grey.withValues(alpha: 0.1),
        child: const Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: Colors.grey,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Condition Card (glass style, matching Android's card_condition)
// ══════════════════════════════════════════════════════════════════════

class _ConditionCard extends StatelessWidget {
  final String condition;
  const _ConditionCard({required this.condition});

  Color _color() {
    final lower = condition.toLowerCase();
    if (lower.contains('xấu') ||
        lower.contains('tệ') ||
        lower.contains('bad') ||
        lower.contains('die') ||
        lower.contains('not_good')) {
      return AppColors.error;
    }
    if (lower.contains('trung bình') || lower.contains('average')) {
      return AppColors.warning;
    }
    return AppColors.success;
  }

  IconData _icon() {
    final lower = condition.toLowerCase();
    if (lower.contains('xấu') ||
        lower.contains('tệ') ||
        lower.contains('bad') ||
        lower.contains('die') ||
        lower.contains('not_good')) {
      return Icons.warning_amber_rounded;
    }
    if (lower.contains('trung bình') || lower.contains('average')) {
      return Icons.info_outline;
    }
    return Icons.check_circle_outline;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(_icon(), color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              condition,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Map Card — shows the tree's location on a mini map
// ══════════════════════════════════════════════════════════════════════

class _MapCard extends StatelessWidget {
  final double latitude;
  final double longitude;
  final dynamic l;

  const _MapCard({
    required this.latitude,
    required this.longitude,
    required this.l,
  });

  void _openInMaps() async {
    final mapsQueryLabel = Uri.encodeComponent(l.get('app_name'));
    final uri = Platform.isIOS
        ? Uri.parse(
            'https://maps.apple.com/?ll=$latitude,$longitude&q=$mapsQueryLabel',
          )
        : Uri.parse(
            'geo:$latitude,$longitude?q=$latitude,$longitude($mapsQueryLabel)',
          );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback to Google Maps web
      final webUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final primaryText = isDark ? Colors.white : const Color(0xFF1B2838);
    final secondaryText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Map
          SizedBox(
            height: 180,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(latitude, longitude),
                initialZoom: 15.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.epic.treeinfo',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(latitude, longitude),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Coordinates + open in maps
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: AppColors.accentGreen,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l.get('latitude'),
                        style: TextStyle(color: secondaryText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _openInMaps,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_new,
                          color: AppColors.accentGreen,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l.get('maps'),
                          style: TextStyle(
                            color: AppColors.accentGreen,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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

// ══════════════════════════════════════════════════════════════════════
// Stats Grid
// ══════════════════════════════════════════════════════════════════════

class _StatsGrid extends StatelessWidget {
  final TreeModel tree;
  final dynamic l;
  const _StatsGrid({required this.tree, required this.l});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  icon: Icons.calendar_today_outlined,
                  label: l.get('age'),
                  value: tree.display(tree.age, l.get('not_available')),
                ),
              ),
              Expanded(
                child: _StatItem(
                  icon: Icons.height,
                  label: l.get('height'),
                  value: tree.display(tree.height, l.get('not_available')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  icon: Icons.circle_outlined,
                  label: l.get('diameter'),
                  value: tree.display(tree.diameter, l.get('not_available')),
                ),
              ),
              Expanded(
                child: _StatItem(
                  icon: Icons.forest_outlined,
                  label: l.get('canopy'),
                  value: tree.display(tree.canopy, l.get('not_available')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF1B2838);
    final secondaryText = isDark ? Colors.white54 : const Color(0xFF6B7280);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accentGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.accentGreen, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: secondaryText, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Section Card
// ══════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final primaryText = isDark ? Colors.white : const Color(0xFF1B2838);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.accentGreen, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF1B2838);
    final secondaryText = isDark ? Colors.white54 : const Color(0xFF6B7280);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: secondaryText, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: primaryText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
