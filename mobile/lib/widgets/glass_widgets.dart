import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Frosted-glass card used everywhere: login form, account fields, alerts, etc.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Color? tintColor;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.margin,
    this.padding,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final tint = tintColor ?? Colors.white;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: AppShadows.surface,
      ),
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );
  }
}

/// Circular button with glass background — for avatar camera overlay, etc.
class GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? iconColor;

  const GlassCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.94),
          border: Border.all(color: Colors.white, width: 1),
          boxShadow: AppShadows.surface,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: AppColors.accentGreen.withValues(alpha: 0.15),
            child: Center(
              child: Icon(
                icon,
                color: iconColor ?? const Color(0xFF555555),
                size: size * 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon background — a rounded square behind an icon.
class GlassIconBox extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final double size;

  const GlassIconBox({
    super.key,
    required this.icon,
    this.iconColor = const Color(0xFF4CAF50),
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: iconColor, size: size * 0.55),
    );
  }
}

/// Green accent button with glass highlight on edges.
class GreenButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const GreenButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.md),
          gradient: const LinearGradient(
            colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
          ),
          boxShadow: AppShadows.accent,
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Danger / red button.
class GlassDangerButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;

  const GlassDangerButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          color: const Color(0xFFB42318),
          boxShadow: AppShadows.danger,
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
          ),
          icon: icon != null ? Icon(icon) : const SizedBox.shrink(),
          label: Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// Light scaffold with background image fading into white at the top.
class LightScaffold extends StatelessWidget {
  final Widget child;
  final bool showBackground;
  final PreferredSizeWidget? appBar;

  const LightScaffold({
    super.key,
    required this.child,
    this.showBackground = true,
    this.appBar,
  });

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBackground : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: Stack(
        children: [
          if (showBackground)
            Positioned(
              top: screenH * 0.15,
              left: 0,
              right: 0,
              bottom: 0,
              child: Opacity(
                opacity: isDark ? 0.08 : 0.18,
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
          if (showBackground)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: screenH * 0.45,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.5, 1.0],
                    colors: [bgColor, bgColor, bgColor.withValues(alpha: 0.0)],
                  ),
                ),
              ),
            ),
          if (showBackground)
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
                      bgColor.withValues(alpha: 0.73),
                      bgColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Floating bottom bar with consistent Material styling.
class GlassBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<String> labels;

  const GlassBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.labels,
  });

  static const _icons = [
    Icons.cottage_rounded,
    Icons.public_rounded,
    Icons.shield_rounded,
    Icons.notifications_rounded,
    Icons.person_rounded,
  ];
  static const _iconsOutlined = [
    Icons.cottage_outlined,
    Icons.public_outlined,
    Icons.shield_outlined,
    Icons.notifications_none_rounded,
    Icons.person_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs - 2,
        vertical: AppSpacing.xs - 2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white),
        boxShadow: AppShadows.surface,
      ),
      child: Row(
        children: List.generate(_icons.length, (i) {
          final selected = i == selectedIndex;
          final lab = i < labels.length ? labels[i] : '';
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                    horizontal: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: selected
                        ? AppColors.accentGreen.withValues(alpha: 0.12)
                        : Colors.transparent,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected ? _icons[i] : _iconsOutlined[i],
                        size: 22,
                        color: selected
                            ? AppColors.accentGreenDark
                            : const Color(0xFF111111),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        lab,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: selected
                              ? AppColors.accentGreenDark
                              : const Color(0xFF111111),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Unified top toolbar used by all pages.
class AppTopToolbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? trailing;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool? showBackButton;
  final VoidCallback? onBack;
  final double contentTopPadding;
  final bool reserveLeadingSpaceWhenNoBack;

  const AppTopToolbar({
    super.key,
    required this.title,
    this.trailing,
    this.actions,
    this.bottom,
    this.showBackButton,
    this.onBack,
    this.contentTopPadding = AppSpacing.lg,
    this.reserveLeadingSpaceWhenNoBack = false,
  });

  static const double _toolbarContentHeight = 108.0;

  @override
  Size get preferredSize => Size.fromHeight(
    _toolbarContentHeight + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final showBack = showBackButton ?? Navigator.of(context).canPop();
    const backButtonSize = 40.0;

    final trailingWidgets = <Widget>[
      if (trailing != null) trailing!,
      if (actions != null) ...actions!,
    ];

    final header = Row(
      children: [
        if (showBack)
          SizedBox(
            width: backButtonSize,
            height: backButtonSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                color: const Color(0xFF1B2838),
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                padding: EdgeInsets.zero,
                splashRadius: 20,
              ),
            ),
          ),
        if (showBack) const SizedBox(width: AppSpacing.xs),
        if (!showBack && reserveLeadingSpaceWhenNoBack)
          const SizedBox(width: backButtonSize + AppSpacing.xs),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B2838),
            ),
          ),
        ),
        for (var i = 0; i < trailingWidgets.length; i++) ...[
          if (i == 0) const SizedBox(width: AppSpacing.xs),
          trailingWidgets[i],
        ],
      ],
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: Colors.white.withValues(alpha: 0.78),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                contentTopPadding,
                AppSpacing.xl,
                AppSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  if (bottom != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    bottom!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Backward-compatible wrapper.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool? showBackButton;
  final VoidCallback? onBack;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.showBackButton,
    this.onBack,
  });

  static const double _toolbarContentHeight = 108.0;

  @override
  Size get preferredSize => Size.fromHeight(
    _toolbarContentHeight + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    return AppTopToolbar(
      title: title,
      actions: actions,
      bottom: bottom,
      showBackButton: showBackButton,
      onBack: onBack,
    );
  }
}

class GlassPageTopToolbar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  const GlassPageTopToolbar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return AppTopToolbar(title: title, onBack: onBack, trailing: trailing);
  }
}

/// Returns a glass-style [BoxDecoration] for any Container that needs the
/// frosted glass look without the full GlassCard widget tree.
BoxDecoration glassContentDecoration({double borderRadius = 24}) {
  return BoxDecoration(
    color: Colors.white.withValues(alpha: 0.72),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Glass-style text input field with frosted background.
class LightTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final FocusNode? focusNode;

  const LightTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onFieldSubmitted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(
        color: Color(0xFF1B2838),
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: AppColors.accentGreen,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF999999), fontSize: 15),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: const Color(0xFF777777), size: 22)
            : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.55),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(
            color: AppColors.accentGreen,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        errorStyle: const TextStyle(color: AppColors.error),
      ),
    );
  }
}
