import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Light-mode card with subtle shadow and white background.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final bool blur;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.margin,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.blur = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark
        ? AppColors.darkCardBg.withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.88);
    final defaultBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.05);

    final content = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? defaultBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? defaultBorder,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );

    if (blur) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: content,
        ),
      );
    }
    return content;
  }
}

/// Circular button with subtle border.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? AppColors.darkCardBg.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.85);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.06);
    final defaultIconColor = isDark
        ? Colors.white.withValues(alpha: 0.8)
        : const Color(0xFF555555);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.accentGreen.withValues(alpha: 0.15),
          highlightColor: AppColors.accentGreen.withValues(alpha: 0.08),
          child: Center(
            child:
                Icon(icon, color: iconColor ?? defaultIconColor, size: size * 0.5),
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

/// Green accent button.
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
      height: 56,
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
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
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
                        fontWeight: FontWeight.w600,
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
                    colors: [
                      bgColor,
                      bgColor,
                      bgColor.withValues(alpha: 0.0),
                    ],
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

/// Light-mode text input field.
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
          color: Color(0xFF1B2838), fontSize: 16, fontWeight: FontWeight.w500),
      cursorColor: AppColors.accentGreen,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF999999), fontSize: 15),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: const Color(0xFF777777), size: 22)
            : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF2F3F5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.accentGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        errorStyle: const TextStyle(color: AppColors.error),
      ),
    );
  }
}
