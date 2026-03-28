import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/work_management_provider.dart';

class WorkManagementScreen extends StatefulWidget {
  const WorkManagementScreen({super.key});

  @override
  State<WorkManagementScreen> createState() => _WorkManagementScreenState();
}

class _WorkManagementScreenState extends State<WorkManagementScreen> {
  static const List<String> _navRoutes = [
    '/',
    '/maps',
    '/alerts',
    '/notifications',
    '/account',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final authProvider = context.read<AuthProvider>();
      final workProvider = context.read<WorkManagementProvider>();
      workProvider.refreshCheckinSyncStatus(authProvider: authProvider);
      workProvider.loadWorkSummaryForMonth(authProvider: authProvider);
    });
  }

  void _onBottomNavTapped(BuildContext context, int index) {
    HapticFeedback.selectionClick();
    final routeName = _navRoutes[index];
    if (index == 0) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
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

  String _formatDateTime(String? value, String locale, String fallback) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return fallback;
    }

    final parsed = DateTime.tryParse(raw.replaceAll('Z', '+00:00'));
    if (parsed == null) {
      return raw;
    }

    final local = parsed.toLocal();
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');

    if (locale == 'en') {
      return '$yyyy-$mm-$dd $hh:$min';
    }
    return '$dd/$mm/$yyyy $hh:$min';
  }

  String _checkinStatusLabel(SettingsProvider settings, String? status) {
    final l = settings.l;
    switch (status) {
      case 'created':
        return l.get('work_checkin_status_created');
      case 'already_exists':
        return l.get('work_checkin_status_exists');
      case 'pending':
        return l.get('work_checkin_status_pending');
      default:
        return l.get('work_checkin_status_unknown');
    }
  }

  String _syncStatusLabel(SettingsProvider settings, String status) {
    final l = settings.l;
    switch (status) {
      case 'pending':
        return l.get('work_sync_status_pending');
      case 'synced':
        return l.get('work_sync_status_synced');
      case 'failed':
        return l.get('work_sync_status_failed');
      default:
        return status;
    }
  }

  Color _syncStatusTextColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFB54708);
      case 'synced':
        return const Color(0xFF2E7D32);
      case 'failed':
        return const Color(0xFFB42318);
      default:
        return const Color(0xFF475467);
    }
  }

  Color _syncStatusBackgroundColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFFFF4E5);
      case 'synced':
        return const Color(0xFFE8F5E9);
      case 'failed':
        return const Color(0xFFFFE8E8);
      default:
        return const Color(0xFFF2F4F7);
    }
  }

  String _formatDateTimeValue(DateTime? value, String locale, String fallback) {
    if (value == null) {
      return fallback;
    }
    return _formatDateTime(value.toIso8601String(), locale, fallback);
  }

  Widget _buildSyncCountChip({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Color _indicatorColor({required int checked, required int total}) {
    if (total <= 0) {
      return Colors.transparent;
    }
    if (checked <= 0) {
      return const Color(0xFFB0BEC5);
    }
    if (checked >= total) {
      return const Color(0xFF2E7D32);
    }
    return const Color(0xFFF9A825);
  }

  String _selectedDayCoverageText(
    BuildContext context,
    WorkManagementProvider provider,
  ) {
    final l = context.read<SettingsProvider>().l;
    final selectedDay = provider.selectedDay;
    final total = provider.totalCountForDay(selectedDay);
    final checked = provider.checkinCountForDay(selectedDay);

    if (total <= 0) {
      return l.get('work_calendar_day_no_data');
    }
    if (checked <= 0) {
      return l.get('work_calendar_day_none_checked');
    }
    if (checked >= total) {
      return l.get('work_calendar_day_all_checked');
    }
    return '${l.get('work_calendar_day_partial_prefix')}$checked/$total ${l.get('work_calendar_day_partial_suffix')}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final l = settings.l;
    final authProvider = context.watch<AuthProvider>();
    final workProvider = context.watch<WorkManagementProvider>();
    final screenH = MediaQuery.sizeOf(context).height;

    final focusedMonth = workProvider.focusedMonth;
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysInMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final leadingEmptyCells = (firstDayOfMonth.weekday + 6) % 7;
    final totalGridCells = ((leadingEmptyCells + daysInMonth + 6) ~/ 7) * 7;
    final weekdayLabels = _weekdayLabels(settings.locale);
    final lastSyncedText = _formatDateTime(
      workProvider.summaryLastSyncedAt?.toIso8601String(),
      settings.locale,
      l.get('work_calendar_last_sync_unknown'),
    );
    final syncStatusItems = workProvider.checkinSyncItems;

    final isLeader = workProvider.isLeaderScope;
    final roleLabel = isLeader
        ? l.get('work_calendar_role_leader')
        : l.get('work_calendar_role_ranger');
    final scopeLabel = workProvider.teamScope
        ? l.get('work_calendar_scope_team')
        : l.get('work_calendar_scope_self');
    final leaderFilterValue = workProvider.selectedRangerId != null &&
            workProvider.availableRangerIds
                .contains(workProvider.selectedRangerId)
        ? workProvider.selectedRangerId
        : null;

    return Scaffold(
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: const Color(0xFF1B2838),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          l.get('landing_function_work'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1B2838),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.93),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.07),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                l.get('work_calendar_role_label'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF4B5563),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isLeader
                                      ? const Color(0xFFE8F5E9)
                                      : const Color(0xFFE3F2FD),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  roleLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isLeader
                                        ? const Color(0xFF2E7D32)
                                        : const Color(0xFF1565C0),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  scopeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF4B5563),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${l.get('work_calendar_last_sync_prefix')}$lastSyncedText',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF667085),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (workProvider.isSummaryOfflineFallback)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0x33B54708)),
                              ),
                              child: Text(
                                l.get('work_calendar_offline_banner'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB54708),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else if (workProvider.isSummaryStaleData)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0x33B54708)),
                              ),
                              child: Text(
                                l.get('work_calendar_stale_banner'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB54708),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (workProvider.summaryRefreshError != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF5F4),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0x1AB42318)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${l.get('work_calendar_refresh_error_prefix')}${workProvider.summaryRefreshError}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFB42318),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton.tonal(
                                    onPressed: workProvider.isLoadingSummary
                                        ? null
                                        : () {
                                            workProvider.retryLoadSummary(
                                              authProvider: authProvider,
                                            );
                                          },
                                    child: Text(l.get('work_calendar_retry')),
                                  ),
                                ],
                              ),
                            ),
                          if (authProvider.isRangerSession) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4FAF5),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: const Color(0x332E7D32)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.get('work_checkin_title'),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1B2838),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    workProvider.isSyncingCheckin
                                        ? l.get('work_checkin_syncing')
                                        : workProvider.checkinError != null
                                            ? '${l.get('work_checkin_error_prefix')}${workProvider.checkinError}'
                                            : _checkinStatusLabel(
                                                settings,
                                                workProvider.lastCheckinStatus,
                                              ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: workProvider.checkinError != null
                                          ? const Color(0xFFB42318)
                                          : const Color(0xFF2E7D32),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    workProvider.lastCheckinDayKey == null
                                        ? l.get('work_checkin_day_pending')
                                        : '${l.get('work_checkin_day_prefix')}${workProvider.lastCheckinDayKey}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF4B5563),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              key: const Key('work_sync_status_panel'),
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          l.get('work_sync_status_title'),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1B2838),
                                          ),
                                        ),
                                      ),
                                      if (workProvider.isReplayingCheckins)
                                        Text(
                                          l.get('work_sync_status_retrying'),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF475467),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _buildSyncCountChip(
                                        label:
                                            l.get('work_sync_status_count_pending'),
                                        count: workProvider.pendingCheckinCount,
                                        color: const Color(0xFFB54708),
                                      ),
                                      _buildSyncCountChip(
                                        label:
                                            l.get('work_sync_status_count_failed'),
                                        count: workProvider.failedCheckinCount,
                                        color: const Color(0xFFB42318),
                                      ),
                                      _buildSyncCountChip(
                                        label:
                                            l.get('work_sync_status_count_synced'),
                                        count: workProvider.syncedCheckinCount,
                                        color: const Color(0xFF2E7D32),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (syncStatusItems.isEmpty)
                                    Text(
                                      l.get('work_sync_status_empty'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF667085),
                                      ),
                                    )
                                  else
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxHeight: 160),
                                      child: ListView.separated(
                                        key: const Key('work_sync_status_list'),
                                        shrinkWrap: true,
                                        physics: syncStatusItems.length > 2
                                            ? const ClampingScrollPhysics()
                                            : const NeverScrollableScrollPhysics(),
                                        itemCount: syncStatusItems.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 6),
                                        itemBuilder: (context, index) {
                                          final syncItem = syncStatusItems[index];
                                          return Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.black
                                                    .withValues(alpha: 0.06),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '${l.get('work_checkin_day_prefix')}${syncItem.dayKey}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              Color(0xFF344054),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${l.get('work_sync_status_updated_prefix')}${_formatDateTimeValue(syncItem.updatedAt, settings.locale, l.get('work_calendar_last_sync_unknown'))}',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              Color(0xFF667085),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        _syncStatusBackgroundColor(
                                                      syncItem.status,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(999),
                                                  ),
                                                  child: Text(
                                                    _syncStatusLabel(
                                                      settings,
                                                      syncItem.status,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          _syncStatusTextColor(
                                                        syncItem.status,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (syncItem.isFailed)
                                                  IconButton(
                                                    key: Key(
                                                      'work_sync_retry_${syncItem.queueId}',
                                                    ),
                                                    tooltip: l.get(
                                                      'work_sync_status_retry_item',
                                                    ),
                                                    onPressed: workProvider
                                                                .isReplayingCheckins ||
                                                            workProvider
                                                                .isSyncingCheckin
                                                        ? null
                                                        : () async {
                                                            await workProvider
                                                                .retryFailedCheckins(
                                                              authProvider:
                                                                  authProvider,
                                                              queueId:
                                                                  syncItem.queueId,
                                                            );
                                                          },
                                                    icon: const Icon(
                                                      Icons.refresh_rounded,
                                                      size: 18,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  if (workProvider.failedCheckinCount > 1) ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.tonalIcon(
                                        key: const Key(
                                          'work_sync_retry_all_button',
                                        ),
                                        onPressed: workProvider
                                                    .isReplayingCheckins ||
                                                workProvider.isSyncingCheckin
                                            ? null
                                            : () async {
                                                await workProvider
                                                    .retryFailedCheckins(
                                                  authProvider: authProvider,
                                                );
                                              },
                                        icon:
                                            const Icon(Icons.refresh_rounded),
                                        label: Text(
                                          l.get('work_sync_status_retry_all'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          if (isLeader) ...[
                            const SizedBox(height: 12),
                            Text(
                              l.get('work_calendar_filter_label'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4B5563),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String?>(
                              key: ValueKey<String?>(leaderFilterValue),
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
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(l.get('work_calendar_filter_all')),
                                ),
                                ...workProvider.availableRangerIds.map(
                                  (rangerId) => DropdownMenuItem<String?>(
                                    value: rangerId,
                                    child: Text(rangerId),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                workProvider.selectRangerFilter(
                                  authProvider: authProvider,
                                  rangerId: value,
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: workProvider.isLoadingSummary
                                    ? null
                                    : () {
                                        workProvider.goToPreviousMonth(
                                          authProvider: authProvider,
                                        );
                                      },
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                              Expanded(
                                child: Text(
                                  _monthLabel(focusedMonth, settings.locale),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1B2838),
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: workProvider.isLoadingSummary
                                    ? null
                                    : () {
                                        workProvider.goToNextMonth(
                                          authProvider: authProvider,
                                        );
                                      },
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (workProvider.isLoadingSummary)
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
                                      l.get('work_calendar_loading'),
                                      style: const TextStyle(
                                        color: Color(0xFF4B5563),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (workProvider.summaryError != null)
                            Expanded(
                              child: Center(
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF5F4),
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: const Color(0x1AB42318)),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Color(0xFFB42318),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        l.get('work_calendar_error'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFFB42318),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        workProvider.summaryError!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFB42318),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      FilledButton.tonal(
                                        onPressed: () {
                                          workProvider.retryLoadSummary(
                                            authProvider: authProvider,
                                          );
                                        },
                                        child: Text(l.get('work_calendar_retry')),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else if (!workProvider.hasCalendarData)
                            Expanded(
                              child: Center(
                                child: Text(
                                  l.get('work_calendar_empty'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF4B5563),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: Column(
                                children: [
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
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: totalGridCells,
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 7,
                                        childAspectRatio: 0.9,
                                      ),
                                      itemBuilder: (context, index) {
                                        final dayNumber =
                                            index - leadingEmptyCells + 1;
                                        if (dayNumber < 1 || dayNumber > daysInMonth) {
                                          return const SizedBox.shrink();
                                        }

                                        final day = DateTime(
                                          focusedMonth.year,
                                          focusedMonth.month,
                                          dayNumber,
                                        );
                                        final total =
                                            workProvider.totalCountForDay(day);
                                        final checked =
                                            workProvider.checkinCountForDay(day);
                                        final indicatorColor = _indicatorColor(
                                          checked: checked,
                                          total: total,
                                        );
                                        final selected =
                                            _isSameDay(day, workProvider.selectedDay);

                                        return InkWell(
                                          borderRadius: BorderRadius.circular(10),
                                          onTap: () => workProvider.selectDay(day),
                                          child: Container(
                                            margin: const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? const Color(0x152E7D32)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: selected
                                                    ? const Color(0xFF2E7D32)
                                                    : Colors.transparent,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  '$dayNumber',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: selected
                                                        ? FontWeight.w800
                                                        : FontWeight.w600,
                                                    color:
                                                        const Color(0xFF1B2838),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                if (total > 0)
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color: indicatorColor,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  )
                                                else
                                                  Container(
                                                    width: 4,
                                                    height: 4,
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Color(0xFFD1D5DB),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.black.withValues(alpha: 0.06),
                                      ),
                                    ),
                                    child: Text(
                                      _selectedDayCoverageText(
                                        context,
                                        workProvider,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF334155),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
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
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) => _onBottomNavTapped(context, index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: l.get('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map_rounded),
            label: l.get('maps'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.warning_amber_outlined),
            selectedIcon: const Icon(Icons.warning_amber_rounded),
            label: l.get('alerts'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_none_rounded),
            selectedIcon: const Icon(Icons.notifications_rounded),
            label: l.get('notifications'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: l.get('account'),
          ),
        ],
      ),
    );
  }
}
