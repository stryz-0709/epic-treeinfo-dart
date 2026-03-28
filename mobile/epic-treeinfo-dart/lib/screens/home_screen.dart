import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tree_provider.dart';
import '../services/app_notification.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nfcController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _nfcFocusNode = FocusNode();

  bool _isScanningNfc = false;

  void _startNfcScan() async {
    final l = context.read<SettingsProvider>().l;

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      if (mounted) {
        AppNotification.showTop(
          context,
          message: l.get('nfc_ios_unavailable_temp'),
        );
      }
      return;
    }

    final availability = await NfcManager.instance.checkAvailability();
    if (!mounted) return;
    if (availability != NfcAvailability.enabled) {
      AppNotification.showTop(
        context,
        message: l.get('nfc_unavailable_error'),
        type: AppNotificationType.error,
      );
      return;
    }

    AppNotification.showTop(
      context,
      message: l.get('nfc_scan_prompt'),
      duration: null,
    );

    setState(() => _isScanningNfc = true);

    NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
        NfcPollingOption.iso18092,
      },
      onDiscovered: (NfcTag tag) async {
        NfcManager.instance.stopSession();
        AppNotification.dismiss();
        if (!mounted) return;
        setState(() => _isScanningNfc = false);

        List<int>? uidBytes;

        if (Theme.of(context).platform == TargetPlatform.android) {
          final androidTag = NfcTagAndroid.from(tag);
          if (androidTag != null) {
            uidBytes = androidTag.id.toList();
          }
        } else if (Theme.of(context).platform == TargetPlatform.iOS) {
          final mifare = MiFareIos.from(tag);
          final iso7816 = Iso7816Ios.from(tag);
          final iso15693 = Iso15693Ios.from(tag);
          final felica = FeliCaIos.from(tag);

          if (mifare != null) {
            uidBytes = mifare.identifier.toList();
          } else if (iso7816 != null) {
            uidBytes = iso7816.identifier.toList();
          } else if (iso15693 != null) {
            uidBytes = iso15693.identifier.toList();
          } else if (felica != null) {
            uidBytes = felica.currentIDm.toList();
          }
        }

        if (uidBytes != null && uidBytes.isNotEmpty) {
          final uidString = uidBytes
              .map((e) => e.toRadixString(16).padLeft(2, '0'))
              .join('')
              .toUpperCase();

          _nfcController.text = uidString;
          setState(() {});
          _search();
        } else {
          AppNotification.showTop(
            context,
            message: l.get('nfc_uid_read_error'),
            type: AppNotificationType.error,
          );
        }
      },
      onSessionErrorIos: (error) async {
        AppNotification.dismiss();
        if (!mounted) return;
        setState(() => _isScanningNfc = false);
      },
      alertMessageIos: l.get('nfc_scan_prompt'),
    );
  }

  void _stopNfcScan() {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      NfcManager.instance.stopSession();
    }
    AppNotification.dismiss();
    setState(() => _isScanningNfc = false);
  }

  @override
  void initState() {
    super.initState();
    _nfcController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      NfcManager.instance.stopSession();
    }
    AppNotification.dismiss();
    _nfcController.dispose();
    _nfcFocusNode.dispose();
    super.dispose();
  }

  bool _isSearching = false;

  void _search() async {
    HapticFeedback.mediumImpact();
    final l = context.read<SettingsProvider>().l;
    final query = _nfcController.text.trim();
    if (query.isEmpty) {
      _formKey.currentState?.validate();
      return;
    }
    _nfcFocusNode.unfocus();
    if (_isScanningNfc) {
      _stopNfcScan();
    }
    setState(() => _isSearching = true);

    final provider = context.read<TreeProvider>();
    await provider.searchTree(query);

    if (!mounted) return;
    setState(() => _isSearching = false);

    if (provider.error != null) {
      AppNotification.showTop(
        context,
        message: l.get('search_failed'),
        type: AppNotificationType.error,
      );
      return;
    }

    if (provider.currentTree != null) {
      Navigator.of(context).pushNamed('/detail', arguments: query);
    }
  }

  void _showLoginDialog() {
    _nfcFocusNode.unfocus();
    final auth = context.read<AuthProvider>();
    final l = context.read<SettingsProvider>().l;
    final usernameC = TextEditingController();
    final passwordC = TextEditingController();
    final loginFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            final isDark = Theme.of(ctx2).brightness == Brightness.dark;
            final textColor = isDark
                ? AppColors.darkTextPrimary
                : const Color(0xFF1B2838);

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              backgroundColor: isDark ? AppColors.darkCardBg : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                l.get('admin_login'),
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: MediaQuery.of(ctx2).size.width,
                child: Form(
                  key: loginFormKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        auth.isAdmin
                            ? l.get('login_status_logged_in')
                            : l.get('login_status_logged_out'),
                        style: TextStyle(
                          color: auth.isAdmin
                              ? AppColors.accentGreen
                              : AppColors.textHint,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!auth.isAdmin) ...[
                        LightTextField(
                          controller: usernameC,
                          hintText: l.get('username_hint'),
                          prefixIcon: Icons.person_outline,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return l.get('username_empty_error');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        LightTextField(
                          controller: passwordC,
                          hintText: l.get('password_hint'),
                          prefixIcon: Icons.lock_outline,
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return l.get('password_empty_error');
                            }
                            return null;
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: Text(
                    l.get('cancel'),
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: auth.isAdmin
                        ? AppColors.error
                        : AppColors.accentGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (auth.isAdmin) {
                      auth.logout();
                      Navigator.pop(ctx2);
                      AppNotification.showTop(
                        context,
                        message: l.get('logged_out'),
                      );
                    } else {
                      if (!(loginFormKey.currentState?.validate() ?? false)) {
                        return;
                      }

                      final ok = auth.login(
                        usernameC.text.trim(),
                        passwordC.text.trim(),
                      );
                      if (ok) {
                        Navigator.pop(ctx2);
                        AppNotification.showTop(
                          context,
                          message: l.get('login_success'),
                          type: AppNotificationType.success,
                        );
                      } else {
                        AppNotification.showTop(
                          context,
                          message: l.get('login_failed'),
                          type: AppNotificationType.error,
                        );
                      }
                    }
                    setDialogState(() {});
                  },
                  child: Text(auth.isAdmin ? l.get('logout') : l.get('login')),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _nfcFocusNode.unfocus();
    });
  }

  void _showSettingsSheet() {
    _nfcFocusNode.unfocus();
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
    ).then((_) {
      _nfcFocusNode.unfocus();
    });
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final l = context.watch<SettingsProvider>().l;
    final treeProvider = context.watch<TreeProvider>();
    final screenH = MediaQuery.sizeOf(context).height;
    final safeTop = MediaQuery.paddingOf(context).top;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardCardLift = keyboardInset > 0 ? 40.0 : 0.0;
    final keyboardScrollInset = keyboardInset > 0 ? keyboardInset : 0.0;
    const toolbarReservedSpace = 60.0;
    final showNotFound = treeProvider.notFound;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
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
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.only(bottom: keyboardScrollInset),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final verticalScrollPadding =
                              toolbarReservedSpace +
                              40.0 +
                              keyboardScrollInset +
                              16.0;
                          final contentMinHeight =
                              constraints.maxHeight - verticalScrollPadding;

                          return SingleChildScrollView(
                            physics: keyboardInset > 0
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            padding: EdgeInsets.fromLTRB(
                              24,
                              toolbarReservedSpace + 40.0,
                              24,
                              keyboardScrollInset + 16,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: contentMinHeight > 0
                                    ? contentMinHeight
                                    : 0,
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOut,
                                      transform: Matrix4.translationValues(
                                        0,
                                        -keyboardCardLift,
                                        0,
                                      ),
                                      child: Column(
                                        children: [
                                          Container(
                                            width: 120,
                                            height: 120,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              child: Image.asset(
                                                'assets/icons/icon.png',
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          Text(
                                            l.get('app_name'),
                                            style: const TextStyle(
                                              fontSize: 36,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF1B2838),
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            l.get('app_subtitle'),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF666666),
                                              letterSpacing: 3.0,
                                            ),
                                          ),
                                          const SizedBox(height: 40),
                                          if (showNotFound)
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.85,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                border: Border.all(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.08),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    blurRadius: 24,
                                                    offset: const Offset(0, 8),
                                                  ),
                                                ],
                                              ),
                                              padding: const EdgeInsets.all(20),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        width: 36,
                                                        height: 36,
                                                        decoration: BoxDecoration(
                                                          color: AppColors
                                                              .accentGreen
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                11,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.search_off,
                                                          color: AppColors
                                                              .accentGreen,
                                                          size: 20,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(
                                                        l
                                                            .get('not_found')
                                                            .toString()
                                                            .toUpperCase(),
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Color(
                                                            0xFF555555,
                                                          ),
                                                          letterSpacing: 1.0,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    l.get('not_found_detail'),
                                                    style: const TextStyle(
                                                      color: Color(0xFF4B5563),
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  if (auth.isAdmin) ...[
                                                    GreenButton(
                                                      text: l.get(
                                                        'link_tree_action',
                                                      ),
                                                      icon: Icons.link,
                                                      onPressed: () {
                                                        final queryId =
                                                            _nfcController.text
                                                                .trim();
                                                        treeProvider.clear();
                                                        Navigator.of(
                                                          context,
                                                        ).pushNamed(
                                                          '/link',
                                                          arguments: queryId,
                                                        );
                                                      },
                                                    ),
                                                    const SizedBox(height: 12),
                                                  ],
                                                  GreenButton(
                                                    text: l.get('go_back'),
                                                    icon: Icons.arrow_back,
                                                    onPressed: () {
                                                      treeProvider.clear();
                                                    },
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.85,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                border: Border.all(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.08),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    blurRadius: 24,
                                                    offset: const Offset(0, 8),
                                                  ),
                                                ],
                                              ),
                                              padding: const EdgeInsets.all(20),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        width: 36,
                                                        height: 36,
                                                        decoration: BoxDecoration(
                                                          color: AppColors
                                                              .accentGreen
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                11,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.nfc_outlined,
                                                          color: AppColors
                                                              .accentGreen,
                                                          size: 20,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(
                                                        l
                                                            .get('search')
                                                            .toUpperCase(),
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Color(
                                                            0xFF555555,
                                                          ),
                                                          letterSpacing: 1.0,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  LightTextField(
                                                    controller: _nfcController,
                                                    focusNode: _nfcFocusNode,
                                                    hintText: l.get('nfc_hint'),
                                                    prefixIcon: Icons.search,
                                                    suffixIcon:
                                                        _nfcController
                                                            .text
                                                            .isNotEmpty
                                                        ? IconButton(
                                                            icon: const Icon(
                                                              Icons.close,
                                                              color: Color(
                                                                0xFF999999,
                                                              ),
                                                              size: 20,
                                                            ),
                                                            onPressed: () {
                                                              _nfcController
                                                                  .clear();
                                                              setState(() {});
                                                            },
                                                          )
                                                        : IconButton(
                                                            icon: Icon(
                                                              _isScanningNfc
                                                                  ? Icons.nfc
                                                                  : Icons
                                                                        .nfc_outlined,
                                                              color:
                                                                  _isScanningNfc
                                                                  ? AppColors
                                                                        .accentGreen
                                                                  : const Color(
                                                                      0xFF999999,
                                                                    ),
                                                              size: 20,
                                                            ),
                                                            onPressed:
                                                                _isScanningNfc
                                                                ? _stopNfcScan
                                                                : _startNfcScan,
                                                          ),
                                                    validator: (v) {
                                                      if (v == null ||
                                                          v.trim().isEmpty) {
                                                        return l.get(
                                                          'nfc_empty_error',
                                                        );
                                                      }
                                                      return null;
                                                    },
                                                    onFieldSubmitted: (_) =>
                                                        _search(),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  GreenButton(
                                                    text: l.get('search'),
                                                    icon: Icons.search,
                                                    onPressed: _isSearching
                                                        ? null
                                                        : _search,
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                        top: 40,
                                      ),
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
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: safeTop + 16,
              left: 24,
              right: 24,
              child: Row(
                children: [
                  GlassCircleButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  GlassCircleButton(
                    icon: Icons.settings_outlined,
                    onTap: _showSettingsSheet,
                  ),
                  const SizedBox(width: 8),
                  GlassCircleButton(
                    icon: Icons.person_outline,
                    iconColor: auth.isAdmin ? AppColors.accentGreen : null,
                    onTap: _showLoginDialog,
                  ),
                ],
              ),
            ),
            if (_isSearching)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.2),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentGreen,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
