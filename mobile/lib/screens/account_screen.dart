import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/mobile_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';
import 'main_shell.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _displayNameController = TextEditingController();
  final _regionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _picker = ImagePicker();

  String _username = '';
  String _role = '';
  String _avatarUrl = '';
  bool _loadingProfile = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _regionController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _resolveAvatarUrl(MobileApiService api, String url) {
    final t = url.trim();
    if (t.isEmpty) return '';
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    final base = api.baseUrl.endsWith('/')
        ? api.baseUrl.substring(0, api.baseUrl.length - 1)
        : api.baseUrl;
    final path = t.startsWith('/') ? t : '/$t';
    return '$base$path';
  }

  String _initials(String displayName, String username) {
    final source = displayName.trim().isNotEmpty
        ? displayName.trim()
        : username.trim();
    if (source.isEmpty) return '?';
    final parts = source
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      final a = parts[0].isNotEmpty ? parts[0][0] : '';
      final b = parts[1].isNotEmpty ? parts[1][0] : '';
      return '$a$b'.toUpperCase();
    }
    if (source.length >= 2) {
      return source.substring(0, 2).toUpperCase();
    }
    return source[0].toUpperCase();
  }

  Future<void> _loadProfile() async {
    final auth = context.read<AuthProvider>();
    final api = context.read<MobileApiService>();
    final l = context.read<SettingsProvider>().l;
    final token = auth.mobileAccessToken?.trim() ?? '';

    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _loadError = null;
        _username = auth.mobileUsername ?? '';
        _role = auth.mobileRole ?? '';
        _displayNameController.text = auth.mobileDisplayName ?? '';
        _regionController.clear();
        _phoneController.clear();
        _avatarUrl = '';
      });
      return;
    }

    setState(() {
      _loadingProfile = true;
      _loadError = null;
    });

    try {
      final profile = await api.fetchProfile(accessToken: token);
      if (!mounted) return;
      setState(() {
        _username = profile.username;
        _role = profile.role;
        _displayNameController.text = profile.displayName;
        _regionController.text = profile.region;
        _phoneController.text = profile.phone;
        _avatarUrl = profile.avatarUrl;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _loadError = l.get('account_profile_load_error');
      });
    }
  }

  Future<void> _saveProfile() async {
    final auth = context.read<AuthProvider>();
    final api = context.read<MobileApiService>();
    final l = context.read<SettingsProvider>().l;
    final token = auth.mobileAccessToken?.trim() ?? '';

    if (token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.get('account_need_mobile_session'))),
      );
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    try {
      final result = await api.updateProfile(
        accessToken: token,
        displayName: _displayNameController.text.trim(),
        region: _regionController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      if (!mounted) return;

      if (result.ok) {
        setState(() {
          _displayNameController.text = result.displayName;
          _regionController.text = result.region;
          _phoneController.text = result.phone;
          _avatarUrl = result.avatarUrl.isNotEmpty
              ? result.avatarUrl
              : _avatarUrl;
          _saving = false;
        });

        final rt = auth.mobileRefreshToken?.trim() ?? '';
        var role = auth.mobileRole?.trim() ?? '';
        if (role.isEmpty) {
          role = _role.trim();
        }
        if (role.isEmpty) {
          role = 'ranger';
        }
        if (rt.isNotEmpty) {
          auth.setMobileSession(
            accessToken: token,
            refreshToken: rt,
            role: role,
            username: _username.isNotEmpty ? _username : auth.mobileUsername,
            displayName: result.displayName.trim().isEmpty
                ? null
                : result.displayName.trim(),
          );
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.get('update_success'))));
      } else {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.get('account_profile_save_error'))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.get('account_profile_save_error'))),
      );
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    final auth = context.read<AuthProvider>();
    final api = context.read<MobileApiService>();
    final l = context.read<SettingsProvider>().l;
    final token = auth.mobileAccessToken?.trim() ?? '';

    Navigator.of(context).pop();

    if (token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.get('account_need_mobile_session'))),
      );
      return;
    }

    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 88,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty || !mounted) return;

      setState(() => _uploadingAvatar = true);

      final name = picked.name.trim().isNotEmpty ? picked.name : 'avatar.jpg';
      final url = await api.uploadAvatar(
        accessToken: token,
        imageBytes: bytes,
        filename: name,
      );

      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _uploadingAvatar = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.get('account_avatar_upload_error'))),
      );
    }
  }

  void _showAvatarPickerSheet() {
    final l = context.read<SettingsProvider>().l;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: GlassCard(
              borderRadius: 22,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Text(
                      l.get('account_change_photo'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.photo_library_outlined,
                      color: AppColors.accentGreen,
                    ),
                    title: Text(l.get('account_pick_gallery')),
                    onTap: () => _pickAndUploadAvatar(ImageSource.gallery),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.photo_camera_outlined,
                      color: AppColors.accentGreen,
                    ),
                    title: Text(l.get('account_pick_camera')),
                    onTap: () => _pickAndUploadAvatar(ImageSource.camera),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    HapticFeedback.mediumImpact();

    final auth = context.read<AuthProvider>();
    final authApi = context.read<MobileApiService>();
    final l = context.read<SettingsProvider>().l;

    try {
      if (auth.isAuthenticated) {
        await auth.logoutMobileSession(authApi: authApi);
      } else if (auth.isAdmin) {
        auth.logout();
      } else {
        auth.clearMobileSession();
      }
    } catch (_) {
      auth.clearMobileSession();
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.get('signed_out'))));

    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final l = context.watch<SettingsProvider>().l;
    final api = context.watch<MobileApiService>();
    final screenH = MediaQuery.sizeOf(context).height;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.textPrimary;
    final subtitleColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    final resolvedAvatar = _resolveAvatarUrl(api, _avatarUrl);
    final canUseProfile = (auth.mobileAccessToken?.trim().isNotEmpty ?? false);
    final showLogout = auth.isAuthenticated || auth.isAdmin;
    final inShell = MainShellScope.of(context) != null;

    Widget profileBody;
    if (!canUseProfile) {
      profileBody = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          l.get('account_need_mobile_session'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: subtitleColor, height: 1.35),
        ),
      );
    } else if (_loadingProfile) {
      profileBody = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accentGreen),
        ),
      );
    } else if (_loadError != null) {
      profileBody = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.error, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadProfile, child: Text(l.get('retry'))),
          ],
        ),
      );
    } else {
      profileBody = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: GestureDetector(
              onTap: _uploadingAvatar ? null : _showAvatarPickerSheet,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.accentGreen.withValues(
                      alpha: 0.2,
                    ),
                    foregroundImage: resolvedAvatar.isNotEmpty
                        ? NetworkImage(resolvedAvatar)
                        : null,
                    child: resolvedAvatar.isEmpty
                        ? Text(
                            _initials(_displayNameController.text, _username),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.accentGreenDark,
                            ),
                          )
                        : null,
                  ),
                  if (_uploadingAvatar)
                    Positioned.fill(
                      child: ClipOval(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: GlassCircleButton(
                      icon: Icons.camera_alt_rounded,
                      size: 40,
                      onTap: _uploadingAvatar ? null : _showAvatarPickerSheet,
                      iconColor: AppColors.accentGreenDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _displayNameController.text.trim().isNotEmpty
                ? _displayNameController.text.trim()
                : _username,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '@$_username',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: subtitleColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          GlassCard(
            borderRadius: 24,
            padding: const EdgeInsets.fromLTRB(
              18,
              AppSpacing.lg,
              18,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.get('account_display_name'),
                  style: AppTypography.sectionLabel.copyWith(
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 8),
                LightTextField(
                  controller: _displayNameController,
                  hintText: l.get('account_display_name'),
                  prefixIcon: Icons.badge_outlined,
                ),
                const SizedBox(height: 16),
                Text(
                  l.get('account_username'),
                  style: AppTypography.sectionLabel.copyWith(
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 8),
                GlassCard(
                  borderRadius: 14,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        color: subtitleColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _username.isEmpty
                              ? l.get('not_available')
                              : _username,
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.get('account_role'),
                  style: AppTypography.sectionLabel.copyWith(
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GlassCard(
                    borderRadius: 20,
                    tintColor: AppColors.accentGreen.withValues(alpha: 0.16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      _role.isEmpty ? l.get('not_available') : _role,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentGreenDark,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.get('account_region'),
                  style: AppTypography.sectionLabel.copyWith(
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 8),
                LightTextField(
                  controller: _regionController,
                  hintText: l.get('account_region'),
                  prefixIcon: Icons.map_outlined,
                ),
                const SizedBox(height: 16),
                Text(
                  l.get('account_phone'),
                  style: AppTypography.sectionLabel.copyWith(
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 8),
                LightTextField(
                  controller: _phoneController,
                  hintText: l.get('account_phone'),
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),
                GreenButton(
                  text: l.get('save'),
                  icon: Icons.check_rounded,
                  isLoading: _saving,
                  onPressed: _saving ? null : _saveProfile,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppTopToolbar(
        title: l.get('account'),
        reserveLeadingSpaceWhenNoBack: true,
        onBack: () {
          if (inShell) {
            MainShellScope.of(context)?.switchTab(0);
            return;
          }
          Navigator.of(context).pop();
        },
      ),
      body: Stack(
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
                errorBuilder: (_, e, s) => Container(
                  color: isDark
                      ? AppColors.darkBackground
                      : const Color(0xFFF0F0F0),
                ),
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
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 92),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          profileBody,
                          if (showLogout) ...[
                            const SizedBox(height: 20),
                            GlassDangerButton(
                              key: const Key('account_logout_button'),
                              text: l.get('logout'),
                              icon: Icons.logout_rounded,
                              onPressed: () => _logout(context),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            l.get('version'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.versionLabel,
                            ),
                          ),
                        ],
                      ),
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
