import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/settings_provider.dart';
import '../services/mobile_api_service.dart';
import '../services/schedule_note_codec.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class ScheduleScreenArguments {
  final DateTime? focusDay;
  final bool openDetails;

  const ScheduleScreenArguments({this.focusDay, this.openDetails = false});

  static DateTime? _parseFocusDay(dynamic raw) {
    if (raw is DateTime) {
      return DateTime(raw.year, raw.month, raw.day);
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw.trim());
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
    }
    return null;
  }

  static bool _parseOpenDetails(dynamic raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    if (raw is num) {
      return raw != 0;
    }
    return false;
  }

  static ScheduleScreenArguments? tryParse(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is ScheduleScreenArguments) {
      return raw;
    }
    if (raw is DateTime || raw is String) {
      final focusDay = _parseFocusDay(raw);
      if (focusDay == null) {
        return null;
      }
      return ScheduleScreenArguments(focusDay: focusDay, openDetails: true);
    }
    if (raw is Map<Object?, Object?>) {
      final focusDay = _parseFocusDay(
        raw['focusDay'] ?? raw['focus_day'] ?? raw['day'],
      );
      final openDetails = _parseOpenDetails(
        raw['openDetails'] ?? raw['open_details'] ?? false,
      );
      if (focusDay == null && !openDetails) {
        return null;
      }
      return ScheduleScreenArguments(
        focusDay: focusDay,
        openDetails: openDetails,
      );
    }
    return null;
  }
}

enum _ScheduleDayActionType { create, edit, delete }

class _ScheduleDayAction {
  final _ScheduleDayActionType type;
  final MobileScheduleItem? item;

  const _ScheduleDayAction._({required this.type, this.item});

  factory _ScheduleDayAction.create() =>
      const _ScheduleDayAction._(type: _ScheduleDayActionType.create);

  factory _ScheduleDayAction.edit(MobileScheduleItem item) =>
      _ScheduleDayAction._(type: _ScheduleDayActionType.edit, item: item);

  factory _ScheduleDayAction.delete(MobileScheduleItem item) =>
      _ScheduleDayAction._(type: _ScheduleDayActionType.delete, item: item);
}

class _ScheduleBackdropPainter extends CustomPainter {
  final Rect? cutoutRect;
  final Color color;
  final double radius;

  const _ScheduleBackdropPainter({
    required this.cutoutRect,
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final fullPath = Path()..addRect(Offset.zero & size);

    final rect = cutoutRect?.intersect(Offset.zero & size);
    if (rect == null || rect.isEmpty) {
      canvas.drawPath(fullPath, paint);
      return;
    }

    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final dimmedPath = Path.combine(
      PathOperation.difference,
      fullPath,
      holePath,
    );
    canvas.drawPath(dimmedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _ScheduleBackdropPainter oldDelegate) {
    return oldDelegate.cutoutRect != cutoutRect ||
        oldDelegate.color != color ||
        oldDelegate.radius != radius;
  }
}

class ScheduleManagementScreen extends StatefulWidget {
  final ScheduleScreenArguments? initialArguments;

  const ScheduleManagementScreen({super.key, this.initialArguments});

  static ScheduleScreenArguments? parseArguments(Object? rawArguments) {
    return ScheduleScreenArguments.tryParse(rawArguments);
  }

  @override
  State<ScheduleManagementScreen> createState() =>
      _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  static const String _leaderAllValue = '__leader_all__';
  static const int _calendarVisibleRows = 5;

  final Map<String, GlobalKey> _dayCellKeys = <String, GlobalKey>{};

  bool _showPersonalOnly = false;
  DateTime? _selectedDay;
  DateTime? _pendingAutoOpenDay;
  bool _autoOpenScheduled = false;

  @override
  void initState() {
    super.initState();

    final today = _normalizeDay(DateTime.now());
    final initialFocus = _normalizeNullable(widget.initialArguments?.focusDay);

    _selectedDay = initialFocus ?? today;
    if (initialFocus != null &&
        (widget.initialArguments?.openDetails ?? false)) {
      _pendingAutoOpenDay = initialFocus;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final authProvider = context.read<AuthProvider>();
      final scheduleProvider = context.read<ScheduleProvider>();
      final dayTarget = _selectedDay ?? today;
      final monthTarget = _resolveFocusedMonthForVisibleDay(dayTarget);

      scheduleProvider.loadSchedules(
        authProvider: authProvider,
        month: monthTarget,
      );
    });
  }

  DateTime _normalizeDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime? _normalizeNullable(DateTime? value) {
    if (value == null) {
      return null;
    }
    return _normalizeDay(value);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameMonth(DateTime day, DateTime month) {
    return day.year == month.year && day.month == month.month;
  }

  bool _isFutureDay(DateTime day) {
    final today = _normalizeDay(DateTime.now());
    return day.isAfter(today);
  }

  String _isoDay(DateTime day) {
    final yyyy = day.year.toString().padLeft(4, '0');
    final mm = day.month.toString().padLeft(2, '0');
    final dd = day.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  String _monthLabel(DateTime month, String locale) {
    const monthNamesVi = <String>[
      'Tháng 1',
      'Tháng 2',
      'Tháng 3',
      'Tháng 4',
      'Tháng 5',
      'Tháng 6',
      'Tháng 7',
      'Tháng 8',
      'Tháng 9',
      'Tháng 10',
      'Tháng 11',
      'Tháng 12',
    ];
    const monthNamesEn = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final names = locale == 'en' ? monthNamesEn : monthNamesVi;
    return '${names[month.month - 1]} ${month.year}';
  }

  List<String> _weekdayLabels(String locale) {
    if (locale == 'en') {
      return const <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    }
    return const <String>['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  }

  String _formatDay(DateTime day, String locale) {
    final yyyy = day.year.toString().padLeft(4, '0');
    final mm = day.month.toString().padLeft(2, '0');
    final dd = day.day.toString().padLeft(2, '0');
    if (locale == 'en') {
      return '$yyyy-$mm-$dd';
    }
    return '$dd/$mm/$yyyy';
  }

  String _formatDayMonth(DateTime day) {
    final dd = day.day.toString().padLeft(2, '0');
    final mm = day.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  String _formatDateTime(String? value, String locale, String fallback) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return fallback;
    }

    final parsed = DateTime.tryParse(raw.replaceAll('Z', '+00:00'));
    if (parsed == null) {
      return raw;
    }

    return _formatDay(parsed.toLocal(), locale);
  }

  String _resolveScheduleErrorMessage({
    required String rawMessage,
    required SettingsProvider settings,
  }) {
    final message = rawMessage.trim();
    final normalized = message.toLowerCase();
    if (normalized.contains('schedule service is temporarily unavailable')) {
      return settings.l.get('schedule_error_service_unavailable');
    }
    if (normalized.contains('not authorized for this schedule operation')) {
      return settings.l.get('schedule_error_not_authorized');
    }
    return message;
  }

  Map<String, List<MobileScheduleItem>> _groupedByDay(
    ScheduleProvider scheduleProvider,
  ) {
    final grouped = <String, List<MobileScheduleItem>>{};
    for (final item in scheduleProvider.schedules) {
      final parsedDay = scheduleProvider.parseWorkDate(item.workDate);
      if (parsedDay == null) {
        continue;
      }
      final key = _isoDay(parsedDay);
      grouped.putIfAbsent(key, () => <MobileScheduleItem>[]).add(item);
    }
    return grouped;
  }

  List<String> _assignmentNames(
    List<MobileScheduleItem> items,
    ScheduleProvider scheduleProvider,
  ) {
    final names = <String>[];
    final seen = <String>{};

    for (final item in items) {
      final displayName = scheduleProvider
          .rangerDisplayName(item.rangerId)
          .trim();
      if (displayName.isEmpty) {
        continue;
      }
      final normalized = displayName.toLowerCase();
      if (seen.add(normalized)) {
        names.add(displayName);
      }
    }

    return names;
  }

  String? _resolveCurrentRangerId(
    AuthProvider authProvider,
    ScheduleProvider scheduleProvider,
  ) {
    final username = authProvider.mobileUsername?.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }

    final effective = scheduleProvider.effectiveRangerId?.trim();
    if (effective != null && effective.isNotEmpty) {
      return effective;
    }

    final selected = scheduleProvider.selectedRangerId?.trim();
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }

    return null;
  }

  GlobalKey _cellKeyForDay(DateTime day) {
    return _dayCellKeys.putIfAbsent(_isoDay(day), () => GlobalKey());
  }

  Offset? _anchorForDay(DateTime day) {
    final cellContext = _dayCellKeys[_isoDay(day)]?.currentContext;
    if (cellContext == null) {
      return null;
    }

    final render = cellContext.findRenderObject();
    if (render is! RenderBox || !render.attached) {
      return null;
    }

    return render.localToGlobal(render.size.center(Offset.zero));
  }

  Offset _fallbackAnchor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Offset(size.width / 2, size.height * 0.46);
  }

  double _estimateOverlayHeight({
    required int itemCount,
    required bool canManageDay,
  }) {
    const baseHeight = 98.0;
    const emptyStateHeight = 58.0;
    const perItemHeight = 106.0;
    const actionsHeight = 46.0;

    final contentHeight = itemCount == 0
        ? emptyStateHeight
        : math.min(3, itemCount) * perItemHeight;
    final total =
        baseHeight + contentHeight + (canManageDay ? actionsHeight : 0);
    return total.clamp(152.0, 360.0);
  }

  Rect? _cellRectForDay(DateTime day) {
    final cellContext = _dayCellKeys[_isoDay(day)]?.currentContext;
    if (cellContext == null) {
      return null;
    }

    final render = cellContext.findRenderObject();
    if (render is! RenderBox || !render.attached) {
      return null;
    }

    final topLeft = render.localToGlobal(Offset.zero);
    return topLeft & render.size;
  }

  DateTime _calendarGridStart({
    required DateTime focusedMonth,
    required int visibleRows,
  }) {
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final leadingDays = (firstDayOfMonth.weekday + 6) % 7;
    final baseStart = firstDayOfMonth.subtract(Duration(days: leadingDays));
    // Keep row 1 anchored to the week that contains day 1 of focused month.
    // This intentionally lets day 30/31 overflow to next month in 6-row months.
    if (visibleRows <= 0) {
      return baseStart;
    }
    return baseStart;
  }

  bool _isDayVisibleInMonthGrid({
    required DateTime day,
    required DateTime focusedMonth,
  }) {
    final normalizedDay = _normalizeDay(day);
    final gridStart = _calendarGridStart(
      focusedMonth: focusedMonth,
      visibleRows: _calendarVisibleRows,
    );
    final gridEnd = gridStart.add(
      const Duration(days: _calendarVisibleRows * 7 - 1),
    );

    return !normalizedDay.isBefore(gridStart) &&
        !normalizedDay.isAfter(gridEnd);
  }

  DateTime _resolveFocusedMonthForVisibleDay(DateTime day) {
    final normalizedDay = _normalizeDay(day);
    final currentMonth = DateTime(normalizedDay.year, normalizedDay.month, 1);
    if (_isDayVisibleInMonthGrid(
      day: normalizedDay,
      focusedMonth: currentMonth,
    )) {
      return currentMonth;
    }

    final nextMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
    if (_isDayVisibleInMonthGrid(day: normalizedDay, focusedMonth: nextMonth)) {
      return nextMonth;
    }

    final previousMonth = DateTime(
      currentMonth.year,
      currentMonth.month - 1,
      1,
    );
    if (_isDayVisibleInMonthGrid(
      day: normalizedDay,
      focusedMonth: previousMonth,
    )) {
      return previousMonth;
    }

    return currentMonth;
  }

  DateTime _defaultSelectedDayForMonth({
    required DateTime focusedMonth,
    required DateTime today,
  }) {
    final monthStart = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final normalizedToday = _normalizeDay(today);
    if (_isDayVisibleInMonthGrid(
      day: normalizedToday,
      focusedMonth: monthStart,
    )) {
      return normalizedToday;
    }
    return monthStart;
  }

  Future<void> _goToPreviousMonth(
    AuthProvider authProvider,
    ScheduleProvider scheduleProvider,
  ) async {
    await scheduleProvider.goToPreviousMonth(authProvider: authProvider);
    if (!mounted) {
      return;
    }
    final focusedMonth = DateTime(
      scheduleProvider.focusedMonth.year,
      scheduleProvider.focusedMonth.month,
      1,
    );
    setState(() {
      _selectedDay = _defaultSelectedDayForMonth(
        focusedMonth: focusedMonth,
        today: DateTime.now(),
      );
    });
  }

  Future<void> _goToNextMonth(
    AuthProvider authProvider,
    ScheduleProvider scheduleProvider,
  ) async {
    await scheduleProvider.goToNextMonth(authProvider: authProvider);
    if (!mounted) {
      return;
    }
    final focusedMonth = DateTime(
      scheduleProvider.focusedMonth.year,
      scheduleProvider.focusedMonth.month,
      1,
    );
    setState(() {
      _selectedDay = _defaultSelectedDayForMonth(
        focusedMonth: focusedMonth,
        today: DateTime.now(),
      );
    });
  }

  Future<void> _jumpToCurrentDate(
    AuthProvider authProvider,
    ScheduleProvider scheduleProvider,
  ) async {
    final today = _normalizeDay(DateTime.now());
    final monthTarget = _resolveFocusedMonthForVisibleDay(today);
    await scheduleProvider.loadSchedules(
      authProvider: authProvider,
      month: monthTarget,
      rangerId: scheduleProvider.selectedRangerId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedDay = today;
    });
  }

  void _maybeAutoOpenDayDropdown({
    required AuthProvider authProvider,
    required ScheduleProvider scheduleProvider,
    required DateTime focusedMonth,
  }) {
    final pending = _pendingAutoOpenDay;
    if (pending == null || _autoOpenScheduled) {
      return;
    }

    final normalizedPending = _normalizeDay(pending);
    if (!_isSameMonth(normalizedPending, focusedMonth)) {
      _autoOpenScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _autoOpenScheduled = false;
        if (!mounted) {
          return;
        }
        await scheduleProvider.loadSchedules(
          authProvider: authProvider,
          month: DateTime(normalizedPending.year, normalizedPending.month),
          rangerId: scheduleProvider.selectedRangerId,
        );
      });
      return;
    }

    if (scheduleProvider.isLoading) {
      return;
    }

    _autoOpenScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoOpenScheduled = false;
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDay = normalizedPending;
      });

      await _openDayDetailsDropdown(normalizedPending);

      if (!mounted) {
        return;
      }

      setState(() {
        _pendingAutoOpenDay = null;
      });
    });
  }

  Future<void> _openDayDetailsDropdown(DateTime day, {Offset? anchor}) async {
    final scheduleProvider = context.read<ScheduleProvider>();
    final settings = context.read<SettingsProvider>();
    final hasAdminOrLeaderRole =
        scheduleProvider.accountRole == 'admin' ||
        scheduleProvider.accountRole == 'leader';

    final groupedByDay = _groupedByDay(scheduleProvider);
    final dayItems = groupedByDay[_isoDay(day)] ?? const <MobileScheduleItem>[];
    final canManageDay =
        scheduleProvider.isLeaderScope &&
        hasAdminOrLeaderRole &&
        _isFutureDay(day);
    final canDeleteItems = scheduleProvider.canDeleteSchedules && canManageDay;
    final anchorRect = _cellRectForDay(day);

    final action = await _showDayOverlay(
      day: day,
      dayItems: dayItems,
      settings: settings,
      scheduleProvider: scheduleProvider,
      canManageDay: canManageDay,
      canDeleteItems: canDeleteItems,
      anchor: anchor ?? _anchorForDay(day) ?? _fallbackAnchor(context),
      anchorRect: anchorRect,
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action.type) {
      case _ScheduleDayActionType.create:
        await _openScheduleEditor(context, presetDate: day);
        return;
      case _ScheduleDayActionType.edit:
        final editingItem = action.item;
        if (editingItem == null) {
          return;
        }
        await _openScheduleEditor(
          context,
          editingItem: editingItem,
          presetDate: day,
        );
        return;
      case _ScheduleDayActionType.delete:
        final deletingItem = action.item;
        if (deletingItem == null) {
          return;
        }
        await _confirmDeleteSchedule(context, item: deletingItem);
        return;
    }
  }

  Future<_ScheduleDayAction?> _showDayOverlay({
    required DateTime day,
    required List<MobileScheduleItem> dayItems,
    required SettingsProvider settings,
    required ScheduleProvider scheduleProvider,
    required bool canManageDay,
    required bool canDeleteItems,
    required Offset anchor,
    required Rect? anchorRect,
  }) async {
    final overlay = Overlay.of(context);
    final overlayRender = overlay.context.findRenderObject();
    if (overlayRender is! RenderBox) {
      return null;
    }

    final overlaySize = overlayRender.size;
    const panelWidth = 324.0;
    final estimatedHeight = _estimateOverlayHeight(
      itemCount: dayItems.length,
      canManageDay: canManageDay,
    );
    const panelGap = 0.0;

    Rect? localAnchorRect;
    if (anchorRect != null) {
      final topLeft = overlayRender.globalToLocal(anchorRect.topLeft);
      final bottomRight = overlayRender.globalToLocal(anchorRect.bottomRight);
      localAnchorRect = Rect.fromPoints(topLeft, bottomRight);
    }

    final maxLeft = math.max(8.0, overlaySize.width - panelWidth - 8.0);
    final maxTop = math.max(12.0, overlaySize.height - estimatedHeight - 12.0);

    double left;
    double top;

    if (localAnchorRect != null) {
      final spaceAbove = localAnchorRect.top - 12.0;
      final spaceBelow = overlaySize.height - localAnchorRect.bottom - 12.0;
      final openBelow =
          spaceBelow >= estimatedHeight || spaceBelow >= spaceAbove;
      final openAboveYOffset = ((estimatedHeight - 120.0) * 0.30)
          .clamp(30.0, 56.0)
          .toDouble();
      const topAttachOverlap = 8.0;

      final alignLeft = localAnchorRect.left;
      final alignRight = localAnchorRect.right - panelWidth;
      final alignCenter = localAnchorRect.center.dx - panelWidth / 2;

      final canAlignLeft = alignLeft >= 8.0 && alignLeft <= maxLeft;
      final canAlignRight = alignRight >= 8.0 && alignRight <= maxLeft;

      final preferredLeft = canAlignLeft
          ? alignLeft
          : canAlignRight
          ? alignRight
          : alignCenter;

      left = preferredLeft.clamp(8.0, maxLeft);

      final preferredTop = openBelow
          ? localAnchorRect.bottom + panelGap
          : localAnchorRect.top -
                estimatedHeight +
                openAboveYOffset +
                topAttachOverlap;
      top = preferredTop.clamp(12.0, maxTop);
    } else {
      final proposedLeft = anchor.dx - panelWidth / 2;
      left = proposedLeft.clamp(8.0, maxLeft);
      final openUpward = anchor.dy > overlaySize.height * 0.58;
      final proposedTop = openUpward
          ? anchor.dy - estimatedHeight - panelGap
          : anchor.dy + panelGap;
      top = proposedTop.clamp(12.0, maxTop);
    }

    return showGeneralDialog<_ScheduleDayAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final l = settings.l;
        final locale = settings.locale;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).maybePop(),
                child: CustomPaint(
                  painter: _ScheduleBackdropPainter(
                    cutoutRect: localAnchorRect,
                    color: Colors.black.withValues(alpha: 0.16),
                    radius: 10,
                  ),
                ),
              ),
            ),
            Positioned(
              left: left.toDouble(),
              top: top.toDouble(),
              width: panelWidth,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.get('schedule_dropdown_title'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1B2838),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDay(day, locale),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF475467),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: l.get('schedule_dropdown_close'),
                              onPressed: () {
                                Navigator.of(dialogContext).maybePop();
                              },
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (dayItems.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Text(
                              l.get('schedule_calendar_empty_day'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: dayItems.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = dayItems[index];
                                final noteDetails = ScheduleMissionNote.fromRaw(
                                  item.note,
                                );
                                final missionText =
                                    noteDetails.mission.trim().isEmpty
                                    ? l.get('schedule_note_empty')
                                    : noteDetails.mission.trim();
                                final updatedAtText = _formatDateTime(
                                  item.updatedAt,
                                  locale,
                                  l.get('schedule_updated_at_unknown'),
                                );
                                final canDeleteItem =
                                    canDeleteItems &&
                                    item.scheduleId.trim().isNotEmpty;

                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        scheduleProvider.rangerDisplayName(
                                          item.rangerId,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1B2838),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${l.get('schedule_dropdown_note_label')}: $missionText',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF475467),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (noteDetails.area
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          '${l.get('schedule_form_area_label')}: ${noteDetails.area.trim()}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF475467),
                                          ),
                                        ),
                                      ],
                                      if (noteDetails.reason
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          '${l.get('schedule_form_reason_label')}: ${noteDetails.reason.trim()}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF475467),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        '${l.get('schedule_updated_at_prefix')}$updatedAtText',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF667085),
                                        ),
                                      ),
                                      if (canManageDay) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            TextButton.icon(
                                              onPressed: () {
                                                Navigator.of(dialogContext).pop(
                                                  _ScheduleDayAction.edit(item),
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.edit_rounded,
                                                size: 16,
                                              ),
                                              label: Text(
                                                l.get('schedule_edit'),
                                              ),
                                            ),
                                            if (canDeleteItem)
                                              TextButton.icon(
                                                onPressed: () {
                                                  Navigator.of(
                                                    dialogContext,
                                                  ).pop(
                                                    _ScheduleDayAction.delete(
                                                      item,
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 16,
                                                ),
                                                label: Text(
                                                  l.get('schedule_delete'),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        if (canManageDay) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.of(
                                  dialogContext,
                                ).pop(_ScheduleDayAction.create());
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: Text(l.get('schedule_create')),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openScheduleEditor(
    BuildContext context, {
    MobileScheduleItem? editingItem,
    DateTime? presetDate,
  }) async {
    final authProvider = context.read<AuthProvider>();
    final scheduleProvider = context.read<ScheduleProvider>();
    final settings = context.read<SettingsProvider>();
    final l = settings.l;
    final hasAdminOrLeaderRole =
        scheduleProvider.accountRole == 'admin' ||
        scheduleProvider.accountRole == 'leader';

    if (!scheduleProvider.isLeaderScope || !hasAdminOrLeaderRole) {
      return;
    }

    final formKey = GlobalKey<FormState>();
    final assigneeIds = <String>[...scheduleProvider.availableRangerIds];
    final initialRangerId =
        (editingItem?.rangerId ?? scheduleProvider.selectedRangerId ?? '')
            .trim();
    if (initialRangerId.isNotEmpty && !assigneeIds.contains(initialRangerId)) {
      assigneeIds.insert(0, initialRangerId);
    }

    String? selectedRangerId;
    if (assigneeIds.isNotEmpty) {
      selectedRangerId = initialRangerId.isNotEmpty
          ? initialRangerId
          : assigneeIds.first;
    }

    final existingNote = ScheduleMissionNote.fromRaw(editingItem?.note ?? '');
    final rangerController = TextEditingController(text: initialRangerId);
    final noteController = TextEditingController(text: existingNote.mission);
    final areaController = TextEditingController(text: existingNote.area);
    final reasonController = TextEditingController(text: existingNote.reason);

    DateTime? selectedDate = presetDate != null
        ? _normalizeDay(presetDate)
        : editingItem == null
        ? _normalizeDay(DateTime.now())
        : scheduleProvider.parseWorkDate(editingItem.workDate);

    selectedDate ??= _normalizeDay(DateTime.now());

    bool isSaving = false;
    String? submitError;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> saveSchedule() async {
                if (isSaving || scheduleProvider.isSubmitting) {
                  return;
                }

                final valid = formKey.currentState?.validate() ?? false;
                if (!valid) {
                  return;
                }

                if (selectedDate == null) {
                  setModalState(() {
                    submitError = l.get(
                      'schedule_validation_work_date_required',
                    );
                  });
                  return;
                }

                if (!_isFutureDay(selectedDate!)) {
                  setModalState(() {
                    submitError = l.get('schedule_validation_future_only');
                  });
                  return;
                }

                final requiresReason = editingItem != null;
                if (requiresReason && reasonController.text.trim().isEmpty) {
                  setModalState(() {
                    submitError = l.get('schedule_validation_reason_required');
                  });
                  return;
                }

                setModalState(() {
                  isSaving = true;
                  submitError = null;
                });

                final normalizedRangerId = assigneeIds.isNotEmpty
                    ? (selectedRangerId ?? '').trim()
                    : rangerController.text.trim();

                final notePayload = ScheduleMissionNote(
                  mission: noteController.text,
                  area: areaController.text,
                  reason: reasonController.text,
                ).encode();

                final success = editingItem == null
                    ? await scheduleProvider.createSchedule(
                        authProvider: authProvider,
                        rangerId: normalizedRangerId,
                        workDate: selectedDate,
                        note: notePayload,
                      )
                    : await scheduleProvider.updateSchedule(
                        authProvider: authProvider,
                        scheduleId: editingItem.scheduleId,
                        rangerId: normalizedRangerId,
                        workDate: selectedDate,
                        note: notePayload,
                      );

                if (!mounted || !sheetContext.mounted) {
                  return;
                }

                if (success) {
                  Navigator.of(sheetContext).maybePop();
                  return;
                }

                if (!sheetContext.mounted) {
                  return;
                }

                setModalState(() {
                  isSaving = false;
                  submitError =
                      scheduleProvider.submitError ?? l.get('schedule_error');
                });
              }

              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          editingItem == null
                              ? l.get('schedule_form_title_create')
                              : l.get('schedule_form_title_edit'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1B2838),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (assigneeIds.isNotEmpty)
                          DropdownButtonFormField<String>(
                            initialValue: selectedRangerId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l.get('schedule_form_ranger_label'),
                              border: const OutlineInputBorder(),
                            ),
                            items: assigneeIds
                                .map(
                                  (rangerId) => DropdownMenuItem<String>(
                                    value: rangerId,
                                    child: Text(
                                      scheduleProvider.rangerDisplayName(
                                        rangerId,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: isSaving
                                ? null
                                : (value) {
                                    setModalState(() {
                                      selectedRangerId = value;
                                    });
                                  },
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l.get(
                                  'schedule_validation_ranger_required',
                                );
                              }
                              return null;
                            },
                          )
                        else
                          TextFormField(
                            controller: rangerController,
                            decoration: InputDecoration(
                              labelText: l.get('schedule_form_ranger_label'),
                              border: const OutlineInputBorder(),
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l.get(
                                  'schedule_validation_ranger_required',
                                );
                              }
                              return null;
                            },
                          ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: isSaving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: sheetContext,
                                    initialDate: selectedDate ?? DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null && sheetContext.mounted) {
                                    setModalState(() {
                                      selectedDate = DateTime(
                                        picked.year,
                                        picked.month,
                                        picked.day,
                                      );
                                    });
                                  }
                                },
                          borderRadius: BorderRadius.circular(8),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: l.get('schedule_form_date_label'),
                              border: const OutlineInputBorder(),
                              errorText: selectedDate == null
                                  ? l.get(
                                      'schedule_validation_work_date_required',
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedDate == null
                                        ? l.get(
                                            'schedule_validation_work_date_required',
                                          )
                                        : _formatDay(
                                            selectedDate!,
                                            settings.locale,
                                          ),
                                  ),
                                ),
                                const Icon(Icons.calendar_month_rounded),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: noteController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: l.get('schedule_form_note_label'),
                            hintText: l.get('schedule_form_note_hint'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: areaController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: l.get('schedule_form_area_label'),
                            hintText: l.get('schedule_form_area_hint'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: reasonController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: l.get('schedule_form_reason_label'),
                            hintText: l.get('schedule_form_reason_hint'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        if (submitError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            '${l.get('schedule_submit_error_prefix')}$submitError',
                            style: const TextStyle(
                              color: Color(0xFFB42318),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.of(sheetContext).pop(),
                              child: Text(l.get('schedule_form_cancel')),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: isSaving ? null : saveSchedule,
                              child: Text(
                                isSaving
                                    ? l.get('schedule_form_saving')
                                    : l.get('schedule_form_save'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      rangerController.dispose();
      noteController.dispose();
      areaController.dispose();
      reasonController.dispose();
    }
  }

  Future<void> _confirmDeleteSchedule(
    BuildContext context, {
    required MobileScheduleItem item,
  }) async {
    final authProvider = context.read<AuthProvider>();
    final scheduleProvider = context.read<ScheduleProvider>();
    final settings = context.read<SettingsProvider>();
    final l = settings.l;

    final scheduleId = item.scheduleId.trim();
    if (!scheduleProvider.canDeleteSchedules || scheduleId.isEmpty) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(l.get('schedule_delete_confirm_title')),
              content: Text(l.get('schedule_delete_confirm_message')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l.get('schedule_form_cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l.get('schedule_delete_confirm_action')),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    final success = await scheduleProvider.deleteSchedule(
      authProvider: authProvider,
      scheduleId: scheduleId,
    );

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(this.context);
    if (success) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.get('schedule_delete_success'))),
      );
      return;
    }

    final error =
        scheduleProvider.submitError ?? l.get('schedule_delete_error');
    messenger.showSnackBar(
      SnackBar(content: Text('${l.get('schedule_delete_error_prefix')}$error')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final authProvider = context.watch<AuthProvider>();
    final scheduleProvider = context.watch<ScheduleProvider>();
    final l = settings.l;
    final screenH = MediaQuery.sizeOf(context).height;

    final focusedMonth = scheduleProvider.focusedMonth;
    final weekdayLabels = _weekdayLabels(settings.locale);

    final groupedByDay = _groupedByDay(scheduleProvider);
    final normalizedToday = _normalizeDay(DateTime.now());
    final currentRangerId = _resolveCurrentRangerId(
      authProvider,
      scheduleProvider,
    );

    final monthStart = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final defaultSelectedDay = _defaultSelectedDayForMonth(
      focusedMonth: monthStart,
      today: normalizedToday,
    );
    final selectedDay =
        _selectedDay != null &&
            _isDayVisibleInMonthGrid(
              day: _selectedDay!,
              focusedMonth: monthStart,
            )
        ? _normalizeDay(_selectedDay!)
        : defaultSelectedDay;
    final calendarGridStart = _calendarGridStart(
      focusedMonth: focusedMonth,
      visibleRows: _calendarVisibleRows,
    );
    final totalGridCells = _calendarVisibleRows * 7;
    final isCurrentDateFocused = _isSameDay(selectedDay, normalizedToday);

    final isLeader = scheduleProvider.isLeaderScope;
    final hasAdminOrLeaderRole =
        scheduleProvider.accountRole == 'admin' ||
        scheduleProvider.accountRole == 'leader';
    final canShowManagementControls = isLeader && hasAdminOrLeaderRole;
    final leaderSelectedRangerId = scheduleProvider.selectedRangerId;
    final leaderFilterValue =
        leaderSelectedRangerId != null &&
            !scheduleProvider.availableRangerIds.contains(
              leaderSelectedRangerId,
            )
        ? _leaderAllValue
        : (leaderSelectedRangerId ?? _leaderAllValue);
    final leaderFilterAllLabel = scheduleProvider.canViewLeaderAssignments
        ? l.get('schedule_filter_all_staff')
        : l.get('schedule_filter_all');
    final rectangleButtonStyle = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, 34),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    final lastSyncedText = _formatDateTime(
      scheduleProvider.lastSyncedAt?.toIso8601String(),
      settings.locale,
      l.get('schedule_last_sync_unknown'),
    );
    final resolvedRefreshError = scheduleProvider.refreshError == null
        ? null
        : _resolveScheduleErrorMessage(
            rawMessage: scheduleProvider.refreshError!,
            settings: settings,
          );
    final resolvedLoadError = scheduleProvider.loadError == null
        ? null
        : _resolveScheduleErrorMessage(
            rawMessage: scheduleProvider.loadError!,
            settings: settings,
          );

    _maybeAutoOpenDayDropdown(
      authProvider: authProvider,
      scheduleProvider: scheduleProvider,
      focusedMonth: focusedMonth,
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppTopToolbar(
        title: l.get('landing_function_schedule'),
        onBack: () => Navigator.of(context).pop(),
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
                errorBuilder: (_, e, s) =>
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
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                0,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xs,
                        0,
                        AppSpacing.xs,
                        AppSpacing.xxs,
                      ),
                      decoration: glassContentDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${l.get('schedule_last_sync_prefix')}$lastSyncedText',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF667085),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.tonalIcon(
                                onPressed: scheduleProvider.isLoading
                                    ? null
                                    : () {
                                        scheduleProvider.retryLoad(
                                          authProvider: authProvider,
                                        );
                                      },
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                ),
                                label: Text(l.get('schedule_retry')),
                                style: rectangleButtonStyle,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (scheduleProvider.isOfflineFallback)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0x33B54708),
                                ),
                              ),
                              child: Text(
                                l.get('schedule_offline_banner'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB54708),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else if (scheduleProvider.isStaleData)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0x33B54708),
                                ),
                              ),
                              child: Text(
                                l.get('schedule_stale_banner'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB54708),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (resolvedRefreshError != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF5F4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0x1AB42318),
                                ),
                              ),
                              child: Text(
                                '${l.get('schedule_refresh_error_prefix')}$resolvedRefreshError',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB42318),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (canShowManagementControls) ...[
                            Text(
                              l.get('schedule_filter_label'),
                              style: AppTypography.sectionLabel.copyWith(
                                color: const Color(0xFF4B5563),
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              key: ValueKey<String>(leaderFilterValue),
                              initialValue: leaderFilterValue,
                              isExpanded: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.12),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.12),
                                  ),
                                ),
                              ),
                              items: [
                                DropdownMenuItem<String>(
                                  value: _leaderAllValue,
                                  child: Text(leaderFilterAllLabel),
                                ),
                                ...scheduleProvider.availableRangerIds.map(
                                  (rangerId) => DropdownMenuItem<String>(
                                    value: rangerId,
                                    child: Text(
                                      scheduleProvider.rangerDisplayName(
                                        rangerId,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                final selected = value == _leaderAllValue
                                    ? null
                                    : value;
                                scheduleProvider.selectRangerFilter(
                                  authProvider: authProvider,
                                  rangerId: selected,
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: scheduleProvider.isLoading
                                    ? null
                                    : () {
                                        _goToPreviousMonth(
                                          authProvider,
                                          scheduleProvider,
                                        );
                                      },
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                              Expanded(
                                child: Text(
                                  _monthLabel(
                                    scheduleProvider.focusedMonth,
                                    settings.locale,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1B2838),
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: scheduleProvider.isLoading
                                    ? null
                                    : () {
                                        _goToNextMonth(
                                          authProvider,
                                          scheduleProvider,
                                        );
                                      },
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                              const SizedBox(width: 4),
                              FilledButton(
                                onPressed: scheduleProvider.isLoading
                                    ? null
                                    : () {
                                        _jumpToCurrentDate(
                                          authProvider,
                                          scheduleProvider,
                                        );
                                      },
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  minimumSize: const Size(0, 34),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  backgroundColor: isCurrentDateFocused
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFE5E7EB),
                                  foregroundColor: isCurrentDateFocused
                                      ? Colors.white
                                      : const Color(0xFF334155),
                                ),
                                child: Text(
                                  _formatDayMonth(normalizedToday),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (scheduleProvider.isLoading)
                            Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Color(0xFF2E7D32),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      l.get('schedule_loading'),
                                      style: const TextStyle(
                                        color: Color(0xFF4B5563),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: Column(
                                children: [
                                  if (resolvedLoadError != null)
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF5F4),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: const Color(0x1AB42318),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${l.get('schedule_error')} $resolvedLoadError',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFB42318),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Row(
                                    children: weekdayLabels
                                        .map(
                                          (label) => Expanded(
                                            child: Center(
                                              child: Text(
                                                label,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF6B7280),
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: GridView.builder(
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: totalGridCells,
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 7,
                                            childAspectRatio: 0.9,
                                            crossAxisSpacing: 0,
                                            mainAxisSpacing: 0,
                                          ),
                                      itemBuilder: (context, index) {
                                        final day = calendarGridStart.add(
                                          Duration(days: index),
                                        );
                                        final dayNumber = day.day;
                                        final dayMonth = day.month
                                            .toString()
                                            .padLeft(2, '0');
                                        final isOutsideCurrentMonth =
                                            !_isSameMonth(day, focusedMonth);
                                        final isPastDate = day.isBefore(
                                          normalizedToday,
                                        );
                                        final isPastDateCell = isPastDate;
                                        final dayItems =
                                            groupedByDay[_isoDay(day)] ??
                                            const <MobileScheduleItem>[];
                                        final assigneeNames = _assignmentNames(
                                          dayItems,
                                          scheduleProvider,
                                        );
                                        final previewNames = assigneeNames
                                            .take(2)
                                            .toList(growable: false);
                                        final hiddenCount =
                                            assigneeNames.length -
                                            previewNames.length;

                                        final hasAssignments =
                                            dayItems.isNotEmpty;
                                        final isToday = _isSameDay(
                                          day,
                                          normalizedToday,
                                        );
                                        final isSelected = _isSameDay(
                                          day,
                                          selectedDay,
                                        );
                                        final hasPersonalAssignment =
                                            currentRangerId != null &&
                                            dayItems.any(
                                              (item) =>
                                                  item.rangerId.trim() ==
                                                  currentRangerId,
                                            );
                                        final shouldDim =
                                            _showPersonalOnly &&
                                            !hasPersonalAssignment;
                                        final isMonthStartDay =
                                            !isOutsideCurrentMonth &&
                                            dayNumber == 1;

                                        final borderColor = isSelected
                                            ? const Color(0xFF2E7D32)
                                            : isPastDateCell
                                            ? const Color(0xFFD0D5DD)
                                            : isToday
                                            ? const Color(0xFF2E7D32)
                                            : hasPersonalAssignment
                                            ? const Color(0xFF43A047)
                                            : Colors.black.withValues(
                                                alpha: 0.08,
                                              );
                                        final backgroundColor = isSelected
                                            ? Colors.white
                                            : isPastDateCell
                                            ? const Color(0xFFF3F4F6)
                                            : isToday
                                            ? const Color(0x122E7D32)
                                            : hasPersonalAssignment
                                            ? const Color(0x1243A047)
                                            : const Color(0xFFF8FAFC);
                                        final dayTextColor = isPastDateCell
                                            ? const Color(0xFF9AA3AF)
                                            : const Color(0xFF1B2838);
                                        final assignmentTextColor =
                                            isPastDateCell
                                            ? const Color(0xFF97A2B2)
                                            : const Color(0xFF334155);
                                        final hiddenCountColor = isPastDateCell
                                            ? const Color(0xFFA5AFBE)
                                            : const Color(0xFF475467);
                                        final dayLabelColor = isToday
                                            ? (isSelected
                                                  ? Colors.white
                                                  : const Color(0xFF1B5E20))
                                            : dayTextColor;

                                        return InkWell(
                                          key: _cellKeyForDay(day),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          onTap: () async {
                                            HapticFeedback.selectionClick();
                                            setState(() {
                                              _selectedDay = day;
                                            });
                                            await _openDayDetailsDropdown(day);
                                          },
                                          child: Opacity(
                                            opacity: shouldDim ? 0.34 : 1,
                                            child: Container(
                                              margin: EdgeInsets.zero,
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    4,
                                                    4,
                                                    4,
                                                    3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: backgroundColor,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: borderColor,
                                                  width: isSelected ? 1.3 : 1,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      if (isOutsideCurrentMonth)
                                                        SizedBox(
                                                          height: 14,
                                                          child: FittedBox(
                                                            fit: BoxFit
                                                                .scaleDown,
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child: Text(
                                                              _formatDayMonth(
                                                                day,
                                                              ),
                                                              maxLines: 1,
                                                              softWrap: false,
                                                              style: TextStyle(
                                                                fontSize: 9.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    dayTextColor,
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                      else
                                                        Container(
                                                          padding: isToday
                                                              ? const EdgeInsets.symmetric(
                                                                  horizontal: 5,
                                                                  vertical: 1,
                                                                )
                                                              : EdgeInsets.zero,
                                                          decoration: isToday
                                                              ? BoxDecoration(
                                                                  color:
                                                                      isSelected
                                                                      ? const Color(
                                                                          0xFF2E7D32,
                                                                        )
                                                                      : const Color(
                                                                          0xFFEAF6EC,
                                                                        ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        999,
                                                                      ),
                                                                  border: Border.all(
                                                                    color: const Color(
                                                                      0xFF2E7D32,
                                                                    ),
                                                                    width: 0.9,
                                                                  ),
                                                                )
                                                              : null,
                                                          child: isMonthStartDay
                                                              ? RichText(
                                                                  text: TextSpan(
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          11.2,
                                                                      fontWeight:
                                                                          isSelected
                                                                          ? FontWeight.w800
                                                                          : FontWeight.w700,
                                                                      color:
                                                                          dayLabelColor,
                                                                    ),
                                                                    children: [
                                                                      const TextSpan(
                                                                        text:
                                                                            '01/',
                                                                      ),
                                                                      TextSpan(
                                                                        text:
                                                                            dayMonth,
                                                                        style: const TextStyle(
                                                                          color: Color(
                                                                            0xFFC62828,
                                                                          ),
                                                                          fontWeight:
                                                                              FontWeight.w800,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                )
                                                              : Text(
                                                                  '$dayNumber',
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        isSelected
                                                                        ? FontWeight
                                                                              .w800
                                                                        : FontWeight
                                                                              .w700,
                                                                    color:
                                                                        dayLabelColor,
                                                                  ),
                                                                ),
                                                        ),
                                                      if (!isOutsideCurrentMonth)
                                                        const Spacer(),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  if (hasAssignments)
                                                    Expanded(
                                                      child: Text(
                                                        previewNames.join('\n'),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 10.3,
                                                          height: 1.15,
                                                          color:
                                                              assignmentTextColor,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    )
                                                  else
                                                    const Spacer(),
                                                  if (hiddenCount > 0)
                                                    Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Text(
                                                        '+$hiddenCount',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color:
                                                              hiddenCountColor,
                                                          fontWeight:
                                                              FontWeight.w700,
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
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _showPersonalOnly = !_showPersonalOnly;
                                });
                              },
                              style: FilledButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                backgroundColor: _showPersonalOnly
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFE5E7EB),
                                foregroundColor: _showPersonalOnly
                                    ? Colors.white
                                    : const Color(0xFF334155),
                              ),
                              child: Text(l.get('schedule_scope_self')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l.get('version'),
                    style: const TextStyle(
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
    );
  }
}
