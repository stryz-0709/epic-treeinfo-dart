import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/settings_provider.dart';
import '../services/mobile_api_service.dart';

class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key});

  @override
  State<ScheduleManagementScreen> createState() => _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  static const List<String> _navRoutes = [
    '/',
    '/maps',
    '/alerts',
    '/notifications',
    '/account',
  ];

  static const String _leaderAllValue = '__leader_all__';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final authProvider = context.read<AuthProvider>();
      final scheduleProvider = context.read<ScheduleProvider>();
      scheduleProvider.loadSchedules(authProvider: authProvider);
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

  String _formatDay(DateTime day, String locale) {
    final yyyy = day.year.toString().padLeft(4, '0');
    final mm = day.month.toString().padLeft(2, '0');
    final dd = day.day.toString().padLeft(2, '0');
    if (locale == 'en') {
      return '$yyyy-$mm-$dd';
    }
    return '$dd/$mm/$yyyy';
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

  Future<void> _openScheduleEditor(
    BuildContext context, {
    MobileScheduleItem? editingItem,
  }) async {
    final authProvider = context.read<AuthProvider>();
    final scheduleProvider = context.read<ScheduleProvider>();
    final settings = context.read<SettingsProvider>();
    final l = settings.l;

    final formKey = GlobalKey<FormState>();
    final assigneeIds = <String>[...scheduleProvider.availableRangerIds];
    final initialRangerId =
        (editingItem?.rangerId ?? scheduleProvider.selectedRangerId ?? '').trim();
    if (initialRangerId.isNotEmpty && !assigneeIds.contains(initialRangerId)) {
      assigneeIds.insert(0, initialRangerId);
    }
    String? selectedRangerId;
    if (assigneeIds.isNotEmpty) {
      selectedRangerId =
          initialRangerId.isNotEmpty ? initialRangerId : assigneeIds.first;
    }

    final rangerController = TextEditingController(text: initialRangerId);
    final noteController = TextEditingController(text: editingItem?.note ?? '');

    DateTime? selectedDate = editingItem == null
        ? DateTime.now()
        : scheduleProvider.parseWorkDate(editingItem.workDate);

    if (selectedDate == null) {
      selectedDate = DateTime.now();
    }

    bool isSaving = false;
    String? submitError;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
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
                    submitError = l.get('schedule_validation_work_date_required');
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

                final success = editingItem == null
                    ? await scheduleProvider.createSchedule(
                        authProvider: authProvider,
                        rangerId: normalizedRangerId,
                        workDate: selectedDate,
                        note: noteController.text,
                      )
                    : await scheduleProvider.updateSchedule(
                        authProvider: authProvider,
                        scheduleId: editingItem.scheduleId,
                        rangerId: normalizedRangerId,
                        workDate: selectedDate,
                        note: noteController.text,
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
                  submitError = scheduleProvider.submitError ?? l.get('schedule_error');
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
                          value: selectedRangerId,
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
                                    scheduleProvider.rangerDisplayName(rangerId),
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
                              return l.get('schedule_validation_ranger_required');
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
                              return l.get('schedule_validation_ranger_required');
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
                                  firstDate: DateTime(2020),
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
                                ? l.get('schedule_validation_work_date_required')
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  selectedDate == null
                                      ? l.get('schedule_validation_work_date_required')
                                      : _formatDay(selectedDate!, settings.locale),
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
              );
            },
          );
        },
      );
    } finally {
      rangerController.dispose();
      noteController.dispose();
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

    final messenger = ScaffoldMessenger.of(context);
    if (success) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.get('schedule_delete_success'))),
      );
      return;
    }

    final error = scheduleProvider.submitError ?? l.get('schedule_delete_error');
    messenger.showSnackBar(
      SnackBar(
        content: Text('${l.get('schedule_delete_error_prefix')}$error'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final authProvider = context.watch<AuthProvider>();
    final scheduleProvider = context.watch<ScheduleProvider>();
    final l = settings.l;
    final screenH = MediaQuery.sizeOf(context).height;

    final isLeader = scheduleProvider.isLeaderScope;
    final leaderSelectedRangerId = scheduleProvider.selectedRangerId;
    final leaderFilterValue =
      leaderSelectedRangerId != null &&
        !scheduleProvider.availableRangerIds.contains(leaderSelectedRangerId)
      ? _leaderAllValue
      : (leaderSelectedRangerId ?? _leaderAllValue);
    final roleLabel = isLeader
        ? l.get('schedule_role_leader')
        : l.get('schedule_role_ranger');
    final leaderFilterAllLabel = scheduleProvider.canViewLeaderAssignments
      ? l.get('schedule_filter_all_staff')
      : l.get('schedule_filter_all');
    final scopeLabel = scheduleProvider.teamScope
        ? l.get('schedule_scope_team')
        : l.get('schedule_scope_self');
    final lastSyncedText = _formatDateTime(
      scheduleProvider.lastSyncedAt?.toIso8601String(),
      settings.locale,
      l.get('schedule_last_sync_unknown'),
    );

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
                          l.get('landing_function_schedule'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1B2838),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: scheduleProvider.isLoading
                            ? null
                            : () {
                                scheduleProvider.retryLoad(
                                  authProvider: authProvider,
                                );
                              },
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: l.get('schedule_retry'),
                        color: const Color(0xFF1B2838),
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
                                l.get('schedule_scope_label'),
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
                            '${l.get('schedule_last_sync_prefix')}$lastSyncedText',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF667085),
                            ),
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
                                border: Border.all(color: const Color(0x33B54708)),
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
                                border: Border.all(color: const Color(0x33B54708)),
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
                          if (scheduleProvider.refreshError != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF5F4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0x1AB42318)),
                              ),
                              child: Text(
                                '${l.get('schedule_refresh_error_prefix')}${scheduleProvider.refreshError}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB42318),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (isLeader) ...[
                            Text(
                              l.get('schedule_filter_label'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4B5563),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: leaderFilterValue,
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
                                      scheduleProvider.rangerDisplayName(rangerId),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                final selected = value == _leaderAllValue ? null : value;
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
                                        scheduleProvider.goToPreviousMonth(
                                          authProvider: authProvider,
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
                                        scheduleProvider.goToNextMonth(
                                          authProvider: authProvider,
                                        );
                                      },
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                          if (isLeader) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: () => _openScheduleEditor(context),
                                icon: const Icon(Icons.add_rounded),
                                label: Text(l.get('schedule_create')),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
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
                          else if (scheduleProvider.loadError != null)
                            Expanded(
                              child: Center(
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF5F4),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0x1AB42318)),
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
                                        l.get('schedule_error'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFFB42318),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        scheduleProvider.loadError!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFB42318),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      FilledButton.tonal(
                                        onPressed: () {
                                          scheduleProvider.retryLoad(
                                            authProvider: authProvider,
                                          );
                                        },
                                        child: Text(l.get('schedule_retry')),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else if (scheduleProvider.isEmptyState)
                            Expanded(
                              child: Center(
                                child: Text(
                                  l.get('schedule_empty'),
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
                              child: RefreshIndicator(
                                onRefresh: () => scheduleProvider.retryLoad(
                                  authProvider: authProvider,
                                ),
                                child: ListView.separated(
                                  itemCount: scheduleProvider.schedules.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final item = scheduleProvider.schedules[index];
                                    final parsedDay =
                                        scheduleProvider.parseWorkDate(item.workDate);
                                    final rangerDisplayName =
                                      scheduleProvider.rangerDisplayName(item.rangerId);
                                    final displayDay = parsedDay == null
                                        ? item.workDate
                                        : _formatDay(parsedDay, settings.locale);
                                    final canDeleteItem =
                                        scheduleProvider.canDeleteSchedules &&
                                        item.scheduleId.trim().isNotEmpty;
                                    final updatedAtText = _formatDateTime(
                                      item.updatedAt,
                                      settings.locale,
                                      l.get('schedule_updated_at_unknown'),
                                    );

                                    return Container(
                                      padding: const EdgeInsets.all(12),
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
                                                  '${l.get('schedule_date_prefix')}$displayDay',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF1B2838),
                                                  ),
                                                ),
                                              ),
                                              if (isLeader)
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      onPressed: () {
                                                        _openScheduleEditor(
                                                          context,
                                                          editingItem: item,
                                                        );
                                                      },
                                                      icon: const Icon(Icons.edit_rounded),
                                                      tooltip: l.get('schedule_edit'),
                                                      visualDensity: VisualDensity.compact,
                                                    ),
                                                    if (canDeleteItem)
                                                      IconButton(
                                                        onPressed: scheduleProvider.isSubmitting
                                                            ? null
                                                            : () {
                                                                _confirmDeleteSchedule(
                                                                  context,
                                                                  item: item,
                                                                );
                                                              },
                                                        icon: const Icon(
                                                          Icons.delete_outline_rounded,
                                                        ),
                                                        color: const Color(0xFFB42318),
                                                        tooltip: l.get('schedule_delete'),
                                                        visualDensity: VisualDensity.compact,
                                                      ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${l.get('schedule_ranger_prefix')}$rangerDisplayName',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF4B5563),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item.note.trim().isEmpty
                                                ? l.get('schedule_note_empty')
                                                : item.note,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF667085),
                                            ),
                                          ),
                                          if (isLeader) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              '${l.get('schedule_updated_by_prefix')}${item.updatedBy ?? l.get('schedule_updated_by_unknown')}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF667085),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${l.get('schedule_updated_at_prefix')}$updatedAtText',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF667085),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
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
