import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/incident_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

class IncidentManagementScreen extends StatefulWidget {
  const IncidentManagementScreen({super.key});

  @override
  State<IncidentManagementScreen> createState() => _IncidentManagementScreenState();
}

class _IncidentManagementScreenState extends State<IncidentManagementScreen> {
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
      final incidentProvider = context.read<IncidentProvider>();
      incidentProvider.loadIncidents(authProvider: authProvider);
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

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
      case 'critical':
        return AppColors.incidentSeverityHigh;
      case 'medium':
        return AppColors.incidentSeverityMedium;
      case 'low':
        return AppColors.incidentSeverityLow;
      default:
        return AppColors.incidentSeverityDefault;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return AppColors.incidentStatusOpen;
      case 'in_progress':
      case 'processing':
        return AppColors.incidentStatusInProgress;
      case 'closed':
      case 'resolved':
        return AppColors.incidentStatusResolved;
      default:
        return AppColors.incidentStatusDefault;
    }
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

  String _resolveErrorMessage(String raw, SettingsProvider settings) {
    switch (raw.trim()) {
      case 'incident_error_timeout':
      case 'incident_error_network':
      case 'incident_error_unexpected':
        return settings.l.get(raw.trim());
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final authProvider = context.watch<AuthProvider>();
    final incidentProvider = context.watch<IncidentProvider>();
    final l = settings.l;
    final screenH = MediaQuery.sizeOf(context).height;

    final incidents = incidentProvider.visibleIncidents;
    final isLeaderScope = incidentProvider.scopeRole == 'leader';
    final roleLabel = isLeaderScope
        ? l.get('incident_role_leader')
        : l.get('incident_role_ranger');

    final scopeLabel = incidentProvider.teamScope
        ? l.get('incident_scope_team')
        : l.get('incident_scope_self');

    final lastSyncedText = _formatDateTime(
      incidentProvider.lastSyncedAt?.toIso8601String(),
      settings.locale,
      l.get('incident_last_sync_unknown'),
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
                          l.get('landing_function_incident'),
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
                        onPressed: incidentProvider.isLoading
                            ? null
                            : () {
                                incidentProvider.refreshIncidents(
                                  authProvider: authProvider,
                                );
                              },
                        icon: const Icon(Icons.refresh_rounded),
                        color: const Color(0xFF1B2838),
                        tooltip: l.get('incident_retry'),
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
                                l.get('incident_scope_label'),
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
                                  color: isLeaderScope
                                      ? const Color(0xFFE8F5E9)
                                      : const Color(0xFFE3F2FD),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  roleLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isLeaderScope
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
                            '${l.get('incident_last_sync_prefix')}$lastSyncedText',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF667085),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (incidentProvider.isOfflineFallback)
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
                                l.get('incident_offline_banner'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB54708),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (incidentProvider.isUsingCachedData &&
                              !incidentProvider.isOfflineFallback)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0x332E7D32)),
                              ),
                              child: Text(
                                l.get('incident_cached_banner'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (incidentProvider.isStaleData &&
                              !incidentProvider.isOfflineFallback)
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
                                l.get('incident_stale_banner'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB54708),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (incidentProvider.scopeRole == 'ranger' &&
                              incidentProvider.hasCrossRangerLeakage)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4E5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0x33B54708)),
                              ),
                              child: Text(
                                l.get('incident_leakage_filtered_banner'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB54708),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (incidentProvider.refreshError != null)
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
                                '${l.get('incident_refresh_error_prefix')}${_resolveErrorMessage(incidentProvider.refreshError!, settings)} ${l.get('incident_refresh_retry_hint')}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB42318),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (incidentProvider.isLoading && !incidentProvider.hasIncidents)
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
                                      l.get('incident_loading'),
                                      style: const TextStyle(
                                        color: Color(0xFF4B5563),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (incidentProvider.loadError != null &&
                              !incidentProvider.hasIncidents)
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
                                        l.get('incident_error'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFFB42318),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _resolveErrorMessage(
                                          incidentProvider.loadError!,
                                          settings,
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFB42318),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      FilledButton.tonal(
                                        onPressed: () {
                                          incidentProvider.loadIncidents(
                                            authProvider: authProvider,
                                          );
                                        },
                                        child: Text(l.get('incident_retry')),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else if (incidentProvider.isEmptyState)
                            Expanded(
                              child: Center(
                                child: Text(
                                  l.get('incident_empty'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF4B5563),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else if (!incidentProvider.hasIncidents &&
                              incidentProvider.isStaleData)
                            Expanded(
                              child: Center(
                                child: Text(
                                  l.get('incident_empty_stale'),
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
                                onRefresh: () => incidentProvider.refreshIncidents(
                                  authProvider: authProvider,
                                ),
                                child: ListView.separated(
                                  itemCount: incidents.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final item = incidents[index];
                                    final occurredAt = _formatDateTime(
                                      item.occurredAt,
                                      settings.locale,
                                      l.get('incident_unknown_time'),
                                    );
                                    final severityText = item.severity.trim().isEmpty
                                        ? l.get('incident_unknown_severity')
                                        : item.severity;
                                    final statusText = item.status.trim().isEmpty
                                        ? l.get('incident_unknown_status')
                                        : item.status;

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
                                                  item.title.isEmpty
                                                      ? l.get('incident_unknown_title')
                                                      : item.title,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF1B2838),
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _severityColor(item.severity)
                                                      .withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  severityText,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: _severityColor(severityText),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${l.get('incident_status_prefix')}$statusText',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _statusColor(statusText),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${l.get('incident_time_prefix')}$occurredAt',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF667085),
                                            ),
                                          ),
                                          if (isLeaderScope &&
                                              item.rangerId != null &&
                                              item.rangerId!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              '${l.get('incident_ranger_prefix')}${item.rangerId}',
                                              style: const TextStyle(
                                                fontSize: 12,
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
