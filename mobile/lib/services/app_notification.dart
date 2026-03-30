import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppNotificationType { success, error, info }

class AppNotification {
  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _activeEntry?.remove();
    _activeEntry = null;
  }

  static void showTop(
    BuildContext context, {
    required String message,
    AppNotificationType type = AppNotificationType.info,
    Duration? duration = const Duration(seconds: 2),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final media = MediaQuery.maybeOf(context);
    if (overlay == null || media == null) return;

    dismiss();

    final topOffset = media.padding.top + 12;

    Color backgroundColor = const Color(0xFF546E7A);
    IconData icon = Icons.info_outline;

    if (type == AppNotificationType.success) {
      backgroundColor = AppColors.success;
      icon = Icons.check_circle_outline;
    } else if (type == AppNotificationType.error) {
      backgroundColor = AppColors.error;
      icon = Icons.error_outline;
    }

    final entry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          top: topOffset,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 200),
                tween: Tween<double>(begin: 0, end: 1),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, -12 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 72),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _activeEntry = entry;
    overlay.insert(entry);

    if (duration != null) {
      _dismissTimer = Timer(duration, dismiss);
    }
  }
}
