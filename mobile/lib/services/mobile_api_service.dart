import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

String _normalizeBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
}

bool _isRetryableBackendError(Object error) {
  return error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is http.ClientException;
}

bool _parseBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

int _parseInt(dynamic value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

double _parseDouble(dynamic value, double fallback) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

String _firstNonEmptyString(Iterable<dynamic> candidates) {
  for (final candidate in candidates) {
    final value = (candidate ?? '').toString().trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

class MobileCheckinResult {
  final String status;
  final String dayKey;
  final String serverTime;
  final String timezone;
  final String idempotencyKey;

  const MobileCheckinResult({
    required this.status,
    required this.dayKey,
    required this.serverTime,
    required this.timezone,
    required this.idempotencyKey,
  });

  factory MobileCheckinResult.fromJson(Map<String, dynamic> json) {
    return MobileCheckinResult(
      status: (json['status'] ?? '').toString(),
      dayKey: (json['day_key'] ?? '').toString(),
      serverTime: (json['server_time'] ?? '').toString(),
      timezone: (json['timezone'] ?? '').toString(),
      idempotencyKey: (json['idempotency_key'] ?? '').toString(),
    );
  }
}

class MobileApiException implements Exception {
  final int statusCode;
  final String body;

  MobileApiException(this.statusCode, this.body);

  @override
  String toString() =>
      'MobileApiException($statusCode): ${body.length > 200 ? '${body.substring(0, 200)}…' : body}';
}

class MobileAuthSession {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final String role;
  final int expiresIn;
  final String? username;
  final String? displayName;

  const MobileAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.role,
    required this.expiresIn,
    required this.username,
    this.displayName,
  });

  factory MobileAuthSession.fromJson(
    Map<String, dynamic> json, {
    String? fallbackUsername,
  }) {
    final rawUsername = _firstNonEmptyString(<dynamic>[
      json['username'],
    ]);
    final username = rawUsername.isNotEmpty ? rawUsername : (fallbackUsername ?? '').trim();
    final displayName = _firstNonEmptyString(<dynamic>[
      json['display_name'],
      json['full_name'],
      json['name'],
    ]);

    return MobileAuthSession(
      accessToken: (json['access_token'] ?? '').toString().trim(),
      refreshToken: (json['refresh_token'] ?? '').toString().trim(),
      tokenType: (json['token_type'] ?? '').toString().trim(),
      role: _firstNonEmptyString(<dynamic>[
        json['role'],
        json['user_role'],
        json['account_role'],
      ]).toLowerCase(),
      expiresIn: _parseInt(json['expires_in'], 0),
      username: username.isEmpty ? null : username,
      displayName: displayName.isEmpty ? null : displayName,
    );
  }
}

class MobileAuthIdentity {
  final String username;
  final String role;
  final String displayName;

  const MobileAuthIdentity({
    required this.username,
    required this.role,
    this.displayName = '',
  });

  factory MobileAuthIdentity.fromJson(Map<String, dynamic> json) {
    final username = _firstNonEmptyString(<dynamic>[
      json['username'],
      json['email'],
    ]);
    final displayName = _firstNonEmptyString(<dynamic>[
      json['display_name'],
      json['full_name'],
      json['name'],
    ]);

    return MobileAuthIdentity(
      username: username,
      role: _firstNonEmptyString(<dynamic>[
        json['role'],
        json['user_role'],
        json['account_role'],
      ]).toLowerCase(),
      displayName: displayName,
    );
  }
}

abstract class MobileAuthApi {
  Future<MobileAuthSession> loginMobile({
    required String username,
    required String password,
  });

  Future<MobileAuthSession> refreshMobileSession({
    required String refreshToken,
  });

  Future<void> logoutMobileSession({
    required String refreshToken,
  });

  Future<MobileAuthIdentity> fetchCurrentMobileUser({
    required String accessToken,
  });
}

abstract class MobileRegisterApi {
  Future<MobileRegisterResult> registerMobile({
    required String username,
    required String password,
    String displayName,
    String region,
    String phone,
  });
}

class MobileRegisterResult {
  final bool ok;
  final String username;
  final String status;
  final String message;

  const MobileRegisterResult({
    required this.ok,
    required this.username,
    required this.status,
    required this.message,
  });

  factory MobileRegisterResult.fromJson(Map<String, dynamic> json) {
    return MobileRegisterResult(
      ok: _parseBool(json['ok']),
      username: (json['username'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

class MobileUserProfile {
  final String username;
  final String displayName;
  final String role;
  final String region;
  final String phone;
  final String avatarUrl;

  const MobileUserProfile({
    required this.username,
    required this.displayName,
    required this.role,
    this.region = '',
    this.phone = '',
    this.avatarUrl = '',
  });

  factory MobileUserProfile.fromJson(Map<String, dynamic> json) {
    return MobileUserProfile(
      username: (json['username'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      region: (json['region'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      avatarUrl: (json['avatar_url'] ?? '').toString(),
    );
  }
}

class MobileProfileUpdateResult {
  final bool ok;
  final String displayName;
  final String region;
  final String phone;
  final String avatarUrl;

  const MobileProfileUpdateResult({
    required this.ok,
    required this.displayName,
    required this.region,
    required this.phone,
    required this.avatarUrl,
  });

  factory MobileProfileUpdateResult.fromJson(Map<String, dynamic> json) {
    return MobileProfileUpdateResult(
      ok: _parseBool(json['ok']),
      displayName: (json['display_name'] ?? '').toString(),
      region: (json['region'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      avatarUrl: (json['avatar_url'] ?? '').toString(),
    );
  }
}

class MobileEmployeeItem {
  final String username;
  final String displayName;
  final String role;

  const MobileEmployeeItem({
    required this.username,
    required this.displayName,
    required this.role,
  });

  factory MobileEmployeeItem.fromJson(Map<String, dynamic> json) {
    final username = (json['username'] ?? '').toString().trim();
    final displayName = (json['display_name'] ?? '').toString().trim();
    return MobileEmployeeItem(
      username: username,
      displayName: displayName.isEmpty ? username : displayName,
      role: (json['role'] ?? '').toString().trim().toLowerCase(),
    );
  }
}

class MobileRangerStats {
  final String rangerId;
  final String displayName;
  final int totalDays;
  final int checkinDays;
  final int incidentsFound;

  const MobileRangerStats({
    required this.rangerId,
    required this.displayName,
    required this.totalDays,
    required this.checkinDays,
    required this.incidentsFound,
  });

  factory MobileRangerStats.fromJson(Map<String, dynamic> json) {
    return MobileRangerStats(
      rangerId: (json['ranger_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      totalDays: _parseInt(json['total_days'], 0),
      checkinDays: _parseInt(json['checkin_days'], 0),
      incidentsFound: _parseInt(json['incidents_found'], 0),
    );
  }
}

class MobileForestCompartment {
  final String id;
  final String name;
  final String region;
  final double areaHa;
  final String notes;
  final int totalIncidents;
  final int resolvedIncidents;
  final int unresolvedIncidents;
  final int resolutionPct;

  const MobileForestCompartment({
    required this.id,
    required this.name,
    required this.region,
    required this.areaHa,
    required this.notes,
    required this.totalIncidents,
    required this.resolvedIncidents,
    required this.unresolvedIncidents,
    required this.resolutionPct,
  });

  factory MobileForestCompartment.fromJson(Map<String, dynamic> json) {
    return MobileForestCompartment(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      region: (json['region'] ?? '').toString(),
      areaHa: _parseDouble(json['area_ha'], 0),
      notes: (json['notes'] ?? '').toString(),
      totalIncidents: _parseInt(json['total_incidents'], 0),
      resolvedIncidents: _parseInt(json['resolved_incidents'], 0),
      unresolvedIncidents: _parseInt(json['unresolved_incidents'], 0),
      resolutionPct: _parseInt(json['resolution_pct'], 0),
    );
  }
}

class MobileAlert {
  final String incidentId;
  final String title;
  final String severity;
  final String status;
  final String alertLevel;
  final String? occurredAt;
  final String? updatedAt;
  final String? rangerId;

  const MobileAlert({
    required this.incidentId,
    required this.title,
    required this.severity,
    required this.status,
    required this.alertLevel,
    this.occurredAt,
    this.updatedAt,
    this.rangerId,
  });

  factory MobileAlert.fromJson(Map<String, dynamic> json) {
    return MobileAlert(
      incidentId: (json['incident_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      severity: (json['severity'] ?? 'unknown').toString(),
      status: (json['status'] ?? 'open').toString(),
      alertLevel: (json['alert_level'] ?? 'info').toString(),
      occurredAt: json['occurred_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      rangerId: json['ranger_id']?.toString(),
    );
  }
}

class MobileReportData {
  final String reportType;
  final String fromDay;
  final String toDay;
  final Map<String, dynamic> data;

  const MobileReportData({
    required this.reportType,
    required this.fromDay,
    required this.toDay,
    required this.data,
  });

  factory MobileReportData.fromJson(Map<String, dynamic> json) {
    final period = json['period'] as Map<String, dynamic>? ?? {};
    return MobileReportData(
      reportType: (json['report_type'] ?? '').toString(),
      fromDay: (period['from'] ?? '').toString(),
      toDay: (period['to'] ?? '').toString(),
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }
}

abstract class MobileForestCompartmentApi {
  Future<List<MobileForestCompartment>> fetchForestCompartments({
    required String accessToken,
    DateTime? fromDay,
    DateTime? toDay,
  });
}

abstract class MobileAlertApi {
  Future<List<MobileAlert>> fetchAlerts({
    required String accessToken,
    int limit,
  });
}

abstract class MobileReportApi {
  Future<MobileReportData> fetchReport({
    required String accessToken,
    required String reportType,
    required DateTime fromDay,
    required DateTime toDay,
  });
}

abstract class MobileAccountApi {
  Future<MobileUserProfile> fetchProfile({required String accessToken});
  Future<MobileProfileUpdateResult> updateProfile({
    required String accessToken,
    required String displayName,
    required String region,
    required String phone,
  });
  Future<String> uploadAvatar({
    required String accessToken,
    required List<int> imageBytes,
    required String filename,
  });
}

abstract class MobileEmployeeApi {
  Future<List<MobileEmployeeItem>> fetchEmployees({required String accessToken});
}

abstract class MobileWorkStatsApi {
  Future<List<MobileRangerStats>> fetchWorkStats({
    required String accessToken,
    required DateTime fromDay,
    required DateTime toDay,
    String? rangerId,
  });
}

abstract class MobileCheckinApi {
  Future<MobileCheckinResult> submitAppOpenCheckin({
    required String accessToken,
    String idempotencyKey,
    String clientTime,
    String timezone,
    String appVersion,
    double? latitude,
    double? longitude,
  });
}

class MobileWorkSummaryItem {
  final String rangerId;
  final String dayKey;
  final bool hasCheckin;
  final String checkinIndicator;
  final Map<String, dynamic> summary;

  const MobileWorkSummaryItem({
    required this.rangerId,
    required this.dayKey,
    required this.hasCheckin,
    required this.checkinIndicator,
    required this.summary,
  });

  factory MobileWorkSummaryItem.fromJson(Map<String, dynamic> json) {
    final parsedSummary = json['summary'];
    return MobileWorkSummaryItem(
      rangerId: (json['ranger_id'] ?? '').toString(),
      dayKey: (json['day_key'] ?? '').toString(),
      hasCheckin: _parseBool(json['has_checkin']),
      checkinIndicator: (json['checkin_indicator'] ?? 'none').toString(),
      summary: parsedSummary is Map<String, dynamic>
          ? parsedSummary
          : <String, dynamic>{},
    );
  }
}

class MobileWorkScope {
  final String role;
  final bool teamScope;
  final String? requestedRangerId;
  final String? effectiveRangerId;

  const MobileWorkScope({
    required this.role,
    required this.teamScope,
    required this.requestedRangerId,
    required this.effectiveRangerId,
  });

  factory MobileWorkScope.fromJson(Map<String, dynamic> json) {
    final requestedRangerId =
        (json['requested_ranger_id'] ?? '').toString().trim();
    final effectiveRangerId =
        (json['effective_ranger_id'] ?? '').toString().trim();
    return MobileWorkScope(
      role: (json['role'] ?? '').toString(),
      teamScope: _parseBool(json['team_scope']),
      requestedRangerId: requestedRangerId.isEmpty ? null : requestedRangerId,
      effectiveRangerId: effectiveRangerId.isEmpty ? null : effectiveRangerId,
    );
  }
}

class MobileWorkPagination {
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  const MobileWorkPagination({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
  });

  factory MobileWorkPagination.fromJson(Map<String, dynamic> json) {
    return MobileWorkPagination(
      page: _parseInt(json['page'], 1),
      pageSize: _parseInt(json['page_size'], 31),
      total: _parseInt(json['total'], 0),
      totalPages: _parseInt(json['total_pages'], 0),
    );
  }
}

class MobileWorkSummaryResult {
  final List<MobileWorkSummaryItem> items;
  final MobileWorkScope scope;
  final MobileWorkPagination pagination;
  final String? fromDay;
  final String? toDay;

  const MobileWorkSummaryResult({
    required this.items,
    required this.scope,
    required this.pagination,
    required this.fromDay,
    required this.toDay,
  });

  factory MobileWorkSummaryResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final parsedItems = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(MobileWorkSummaryItem.fromJson)
              .toList(growable: false)
        : <MobileWorkSummaryItem>[];

    final rawScope = json['scope'];
    final parsedScope = rawScope is Map<String, dynamic>
        ? MobileWorkScope.fromJson(rawScope)
        : const MobileWorkScope(
            role: '',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: null,
          );

    final rawPagination = json['pagination'];
    final parsedPagination = rawPagination is Map<String, dynamic>
        ? MobileWorkPagination.fromJson(rawPagination)
        : const MobileWorkPagination(page: 1, pageSize: 31, total: 0, totalPages: 0);

    final rawFilters = json['filters'];
    final parsedFilters = rawFilters is Map<String, dynamic>
        ? rawFilters
        : const <String, dynamic>{};

    final fromDay = (parsedFilters['from'] ?? '').toString();
    final toDay = (parsedFilters['to'] ?? '').toString();

    return MobileWorkSummaryResult(
      items: parsedItems,
      scope: parsedScope,
      pagination: parsedPagination,
      fromDay: fromDay.isEmpty ? null : fromDay,
      toDay: toDay.isEmpty ? null : toDay,
    );
  }
}

abstract class MobileWorkSummaryApi {
  Future<MobileWorkSummaryResult> fetchWorkSummary({
    required String accessToken,
    required DateTime fromDay,
    required DateTime toDay,
    String? rangerId,
    int page,
    int pageSize,
  });
}

class MobileIncidentItem {
  final String incidentId;
  final String erEventId;
  final String? rangerId;
  final String mappingStatus;
  final String? occurredAt;
  final String? updatedAt;
  final String title;
  final String status;
  final String severity;
  final String? payloadRef;

  const MobileIncidentItem({
    required this.incidentId,
    required this.erEventId,
    required this.rangerId,
    required this.mappingStatus,
    required this.occurredAt,
    required this.updatedAt,
    required this.title,
    required this.status,
    required this.severity,
    required this.payloadRef,
  });

  factory MobileIncidentItem.fromJson(Map<String, dynamic> json) {
    final incidentId = (json['incident_id'] ?? '').toString().trim();
    final erEventId = (json['er_event_id'] ?? '').toString().trim();
    final rangerId = (json['ranger_id'] ?? '').toString().trim();
    final mappingStatus = (json['mapping_status'] ?? '').toString().trim();
    final occurredAt = (json['occurred_at'] ?? '').toString().trim();
    final updatedAt = (json['updated_at'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    final status = (json['status'] ?? '').toString().trim();
    final severity = (json['severity'] ?? '').toString().trim();
    final payloadRef = (json['payload_ref'] ?? '').toString().trim();

    return MobileIncidentItem(
      incidentId: incidentId,
      erEventId: erEventId,
      rangerId: rangerId.isEmpty ? null : rangerId,
      mappingStatus: mappingStatus,
      occurredAt: occurredAt.isEmpty ? null : occurredAt,
      updatedAt: updatedAt.isEmpty ? null : updatedAt,
      title: title,
      status: status,
      severity: severity,
      payloadRef: payloadRef.isEmpty ? null : payloadRef,
    );
  }
}

class MobileIncidentScope {
  final String role;
  final bool teamScope;
  final String? requestedRangerId;
  final String? effectiveRangerId;

  const MobileIncidentScope({
    required this.role,
    required this.teamScope,
    required this.requestedRangerId,
    required this.effectiveRangerId,
  });

  factory MobileIncidentScope.fromJson(Map<String, dynamic> json) {
    final requestedRangerId =
        (json['requested_ranger_id'] ?? '').toString().trim();
    final effectiveRangerId =
        (json['effective_ranger_id'] ?? '').toString().trim();

    return MobileIncidentScope(
      role: (json['role'] ?? '').toString(),
      teamScope: _parseBool(json['team_scope']),
      requestedRangerId: requestedRangerId.isEmpty ? null : requestedRangerId,
      effectiveRangerId: effectiveRangerId.isEmpty ? null : effectiveRangerId,
    );
  }
}

class MobileIncidentPagination {
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  const MobileIncidentPagination({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
  });

  factory MobileIncidentPagination.fromJson(Map<String, dynamic> json) {
    final parsedTotalPages = _parseInt(json['total_pages'], 0);
    final safeTotalPages = parsedTotalPages < 0 ? 0 : parsedTotalPages;

    final parsedPageSize = _parseInt(json['page_size'], 50);
    final safePageSize = parsedPageSize > 0 ? parsedPageSize : 50;

    final parsedTotal = _parseInt(json['total'], 0);
    final safeTotal = parsedTotal < 0 ? 0 : parsedTotal;

    final parsedPage = _parseInt(json['page'], 1);
    var safePage = parsedPage > 0 ? parsedPage : 1;
    if (safeTotalPages > 0 && safePage > safeTotalPages) {
      safePage = safeTotalPages;
    }

    return MobileIncidentPagination(
      page: safePage,
      pageSize: safePageSize,
      total: safeTotal,
      totalPages: safeTotalPages,
    );
  }
}

class MobileIncidentSync {
  final String? cursor;
  final bool hasMore;
  final String? lastSyncedAt;

  const MobileIncidentSync({
    required this.cursor,
    required this.hasMore,
    required this.lastSyncedAt,
  });

  factory MobileIncidentSync.fromJson(Map<String, dynamic> json) {
    final cursor = (json['cursor'] ?? '').toString().trim();
    final lastSyncedAt = (json['last_synced_at'] ?? '').toString().trim();
    return MobileIncidentSync(
      cursor: cursor.isEmpty ? null : cursor,
      hasMore: _parseBool(json['has_more']),
      lastSyncedAt: lastSyncedAt.isEmpty ? null : lastSyncedAt,
    );
  }
}

class MobileIncidentListResult {
  final List<MobileIncidentItem> items;
  final MobileIncidentScope scope;
  final MobileIncidentPagination pagination;
  final MobileIncidentSync sync;
  final String? fromDay;
  final String? toDay;
  final String? updatedSince;

  const MobileIncidentListResult({
    required this.items,
    required this.scope,
    required this.pagination,
    required this.sync,
    required this.fromDay,
    required this.toDay,
    required this.updatedSince,
  });

  factory MobileIncidentListResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final parsedItems = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(MobileIncidentItem.fromJson)
              .toList(growable: false)
        : <MobileIncidentItem>[];

    final rawScope = json['scope'];
    final parsedScope = rawScope is Map<String, dynamic>
        ? MobileIncidentScope.fromJson(rawScope)
        : const MobileIncidentScope(
            role: '',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: null,
          );

    final rawPagination = json['pagination'];
    final parsedPagination = rawPagination is Map<String, dynamic>
        ? MobileIncidentPagination.fromJson(rawPagination)
        : const MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 0,
            totalPages: 0,
          );

    final rawSync = json['sync'];
    final parsedSync = rawSync is Map<String, dynamic>
        ? MobileIncidentSync.fromJson(rawSync)
        : const MobileIncidentSync(cursor: null, hasMore: false, lastSyncedAt: null);

    final rawFilters = json['filters'];
    final parsedFilters = rawFilters is Map<String, dynamic>
        ? rawFilters
        : const <String, dynamic>{};

    final fromDay = (parsedFilters['from'] ?? '').toString().trim();
    final toDay = (parsedFilters['to'] ?? '').toString().trim();
    final updatedSince = (parsedFilters['updated_since'] ?? '').toString().trim();

    return MobileIncidentListResult(
      items: parsedItems,
      scope: parsedScope,
      pagination: parsedPagination,
      sync: parsedSync,
      fromDay: fromDay.isEmpty ? null : fromDay,
      toDay: toDay.isEmpty ? null : toDay,
      updatedSince: updatedSince.isEmpty ? null : updatedSince,
    );
  }
}

abstract class MobileIncidentApi {
  Future<MobileIncidentListResult> fetchIncidents({
    required String accessToken,
    DateTime? fromDay,
    DateTime? toDay,
    DateTime? updatedSince,
    String? rangerId,
    String? cursor,
    int page,
    int pageSize,
  });
}

class MobileScheduleItem {
  final String scheduleId;
  final String rangerId;
  final String workDate;
  final String note;
  final String? updatedBy;
  final String? createdAt;
  final String? updatedAt;

  const MobileScheduleItem({
    required this.scheduleId,
    required this.rangerId,
    required this.workDate,
    required this.note,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MobileScheduleItem.fromJson(Map<String, dynamic> json) {
    final updatedBy = (json['updated_by'] ?? '').toString().trim();
    final createdAt = (json['created_at'] ?? '').toString().trim();
    final updatedAt = (json['updated_at'] ?? '').toString().trim();

    return MobileScheduleItem(
      scheduleId: (json['schedule_id'] ?? '').toString(),
      rangerId: (json['ranger_id'] ?? '').toString(),
      workDate: (json['work_date'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      updatedBy: updatedBy.isEmpty ? null : updatedBy,
      createdAt: createdAt.isEmpty ? null : createdAt,
      updatedAt: updatedAt.isEmpty ? null : updatedAt,
    );
  }
}

class MobileScheduleDirectoryUser {
  final String username;
  final String displayName;
  final String role;

  const MobileScheduleDirectoryUser({
    required this.username,
    required this.displayName,
    required this.role,
  });

  factory MobileScheduleDirectoryUser.fromJson(Map<String, dynamic> json) {
    final username = (json['username'] ?? '').toString().trim();
    final displayName = (json['display_name'] ?? '').toString().trim();
    final role = (json['role'] ?? '').toString().trim().toLowerCase();

    return MobileScheduleDirectoryUser(
      username: username,
      displayName: displayName.isEmpty ? username : displayName,
      role: role,
    );
  }
}

class MobileScheduleScope {
  final String role;
  final String? accountRole;
  final bool teamScope;
  final String? requestedRangerId;
  final String? effectiveRangerId;

  const MobileScheduleScope({
    required this.role,
    this.accountRole,
    required this.teamScope,
    required this.requestedRangerId,
    required this.effectiveRangerId,
  });

  factory MobileScheduleScope.fromJson(Map<String, dynamic> json) {
    final requestedRangerId =
        (json['requested_ranger_id'] ?? '').toString().trim();
    final effectiveRangerId =
        (json['effective_ranger_id'] ?? '').toString().trim();
    final accountRole = (json['account_role'] ?? '').toString().trim();
    return MobileScheduleScope(
      role: (json['role'] ?? '').toString(),
      accountRole: accountRole.isEmpty ? null : accountRole,
      teamScope: _parseBool(json['team_scope']),
      requestedRangerId: requestedRangerId.isEmpty ? null : requestedRangerId,
      effectiveRangerId: effectiveRangerId.isEmpty ? null : effectiveRangerId,
    );
  }
}

class MobileScheduleListResult {
  final List<MobileScheduleItem> items;
  final MobileScheduleScope scope;
  final String? fromDay;
  final String? toDay;
  final List<MobileScheduleDirectoryUser> directory;

  const MobileScheduleListResult({
    required this.items,
    required this.scope,
    required this.fromDay,
    required this.toDay,
    this.directory = const <MobileScheduleDirectoryUser>[],
  });

  factory MobileScheduleListResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final parsedItems = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(MobileScheduleItem.fromJson)
              .toList(growable: false)
        : <MobileScheduleItem>[];

    final rawScope = json['scope'];
    final parsedScope = rawScope is Map<String, dynamic>
        ? MobileScheduleScope.fromJson(rawScope)
        : const MobileScheduleScope(
            role: '',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: null,
          );

    final rawDirectory = json['directory'];
    final parsedDirectory = rawDirectory is List
      ? rawDirectory
          .whereType<Map<String, dynamic>>()
          .map(MobileScheduleDirectoryUser.fromJson)
          .where((entry) => entry.username.trim().isNotEmpty)
          .toList(growable: false)
      : const <MobileScheduleDirectoryUser>[];

    final rawFilters = json['filters'];
    final parsedFilters = rawFilters is Map<String, dynamic>
        ? rawFilters
        : const <String, dynamic>{};

    final fromDay = (parsedFilters['from'] ?? '').toString().trim();
    final toDay = (parsedFilters['to'] ?? '').toString().trim();

    return MobileScheduleListResult(
      items: parsedItems,
      scope: parsedScope,
      fromDay: fromDay.isEmpty ? null : fromDay,
      toDay: toDay.isEmpty ? null : toDay,
      directory: parsedDirectory,
    );
  }
}

abstract class MobileScheduleApi {
  Future<MobileScheduleListResult> fetchSchedules({
    required String accessToken,
    DateTime? fromDay,
    DateTime? toDay,
    String? rangerId,
  });

  Future<MobileScheduleItem> createSchedule({
    required String accessToken,
    required String rangerId,
    required DateTime workDate,
    String note,
  });

  Future<MobileScheduleItem> updateSchedule({
    required String accessToken,
    required String scheduleId,
    required String rangerId,
    required DateTime workDate,
    String note,
  });

  Future<void> deleteSchedule({
    required String accessToken,
    required String scheduleId,
  });
}

class MobileApiService
    implements
    MobileAuthApi,
        MobileRegisterApi,
        MobileCheckinApi,
        MobileWorkSummaryApi,
        MobileIncidentApi,
        MobileScheduleApi,
        MobileAccountApi,
        MobileEmployeeApi,
        MobileWorkStatsApi,
        MobileForestCompartmentApi,
        MobileAlertApi,
        MobileReportApi {
  final String baseUrl;
  final List<String> _baseUrlCandidates;
  final http.Client _client;
  final Duration checkinRequestTimeout;
  String _activeBaseUrl;

  MobileApiService({
    required this.baseUrl,
    List<String> fallbackBaseUrls = const <String>[],
    http.Client? client,
    this.checkinRequestTimeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client(),
       _activeBaseUrl = _normalizeBaseUrl(baseUrl),
       _baseUrlCandidates = _buildBaseUrlCandidates(baseUrl, fallbackBaseUrls);

  static List<String> _buildBaseUrlCandidates(
    String primaryBaseUrl,
    List<String> fallbackBaseUrls,
  ) {
    final candidates = <String>[];

    void add(String value) {
      final normalized = _normalizeBaseUrl(value);
      if (normalized.isEmpty) return;
      if (!candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    add(primaryBaseUrl);
    for (final fallback in fallbackBaseUrls) {
      add(fallback);
    }

    if (candidates.isEmpty) {
      add('http://localhost:8000');
    }

    return candidates;
  }

  Uri _buildUri(String path) {
    return Uri.parse('$_activeBaseUrl$path');
  }

  Uri _buildUriForBaseUrl(String baseUrl, String path) {
    final normalized = _normalizeBaseUrl(baseUrl);
    return Uri.parse('$normalized$path');
  }

  Future<http.Response> _postWithBaseUrlFailover({
    required String path,
    required Map<String, String> headers,
    Object? body,
  }) async {
    Object? lastError;

    for (final candidate in _baseUrlCandidates) {
      try {
        final response = await _client.post(
          _buildUriForBaseUrl(candidate, path),
          headers: headers,
          body: body,
        );
        _activeBaseUrl = _normalizeBaseUrl(candidate);
        return response;
      } catch (error) {
        if (!_isRetryableBackendError(error)) {
          rethrow;
        }
        lastError = error;
      }
    }

    if (lastError != null) {
      throw lastError;
    }

    throw const SocketException('Unable to reach any backend base URL');
  }

  String _formatIsoDay(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    return normalized.toIso8601String().split('T').first;
  }

  @override
  Future<MobileAuthSession> loginMobile({
    required String username,
    required String password,
  }) async {
    final response = await _postWithBaseUrlFailover(
      path: '/api/mobile/auth/login',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw MobileApiException(response.statusCode, response.body);
    }

    return MobileAuthSession.fromJson(
      payload,
      fallbackUsername: username,
    );
  }

  @override
  Future<MobileRegisterResult> registerMobile({
    required String username,
    required String password,
    String displayName = '',
    String region = '',
    String phone = '',
  }) async {
    final response = await _postWithBaseUrlFailover(
      path: '/api/mobile/auth/register',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'username': username,
        'password': password,
        'display_name': displayName,
        'region': region,
        'phone': phone,
      }),
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw MobileApiException(response.statusCode, response.body);
    }

    return MobileRegisterResult.fromJson(payload);
  }

  @override
  Future<MobileAuthSession> refreshMobileSession({
    required String refreshToken,
  }) async {
    final response = await _postWithBaseUrlFailover(
      path: '/api/mobile/auth/refresh',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'refresh_token': refreshToken,
      }),
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw MobileApiException(response.statusCode, response.body);
    }

    return MobileAuthSession.fromJson(payload);
  }

  @override
  Future<void> logoutMobileSession({
    required String refreshToken,
  }) async {
    final response = await _postWithBaseUrlFailover(
      path: '/api/mobile/auth/logout',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'refresh_token': refreshToken,
      }),
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }
  }

  @override
  Future<MobileAuthIdentity> fetchCurrentMobileUser({
    required String accessToken,
  }) async {
    final response = await _client.get(
      _buildUri('/api/mobile/me'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw MobileApiException(response.statusCode, response.body);
    }

    return MobileAuthIdentity.fromJson(payload);
  }

  @override
  Future<MobileCheckinResult> submitAppOpenCheckin({
    required String accessToken,
    String idempotencyKey = '',
    String clientTime = '',
    String timezone = '',
    String appVersion = '',
    double? latitude,
    double? longitude,
  }) async {
    final http.Response response;
    try {
      final body = <String, dynamic>{
        'idempotency_key': idempotencyKey,
        'client_time': clientTime,
        'timezone': timezone,
        'app_version': appVersion,
      };
      if (latitude != null) body['latitude'] = latitude;
      if (longitude != null) body['longitude'] = longitude;

      response = await _client
          .post(
            _buildUri('/api/mobile/checkins'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(checkinRequestTimeout);
    } on TimeoutException {
      throw MobileApiException(
        408,
        'Request timeout while submitting mobile check-in.',
      );
    }

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return MobileCheckinResult.fromJson(payload);
  }

  @override
  Future<MobileWorkSummaryResult> fetchWorkSummary({
    required String accessToken,
    required DateTime fromDay,
    required DateTime toDay,
    String? rangerId,
    int page = 1,
    int pageSize = 62,
  }) async {
    final queryParams = <String, String>{
      'from': _formatIsoDay(fromDay),
      'to': _formatIsoDay(toDay),
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    final trimmedRangerId = rangerId?.trim();
    if (trimmedRangerId != null && trimmedRangerId.isNotEmpty) {
      queryParams['ranger_id'] = trimmedRangerId;
    }

    final uri = _buildUri('/api/mobile/work-management').replace(
      queryParameters: queryParams,
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return MobileWorkSummaryResult.fromJson(payload);
  }

  @override
  Future<MobileIncidentListResult> fetchIncidents({
    required String accessToken,
    DateTime? fromDay,
    DateTime? toDay,
    DateTime? updatedSince,
    String? rangerId,
    String? cursor,
    int page = 1,
    int pageSize = 50,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    if (fromDay != null) {
      queryParams['from'] = _formatIsoDay(fromDay);
    }
    if (toDay != null) {
      queryParams['to'] = _formatIsoDay(toDay);
    }
    if (updatedSince != null) {
      queryParams['updated_since'] = updatedSince.toUtc().toIso8601String();
    }

    final trimmedRangerId = rangerId?.trim();
    if (trimmedRangerId != null && trimmedRangerId.isNotEmpty) {
      queryParams['ranger_id'] = trimmedRangerId;
    }

    final trimmedCursor = cursor?.trim();
    if (trimmedCursor != null && trimmedCursor.isNotEmpty) {
      queryParams['cursor'] = trimmedCursor;
    }

    final uri = _buildUri('/api/mobile/incidents').replace(
      queryParameters: queryParams,
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return MobileIncidentListResult.fromJson(payload);
  }

  @override
  Future<MobileScheduleListResult> fetchSchedules({
    required String accessToken,
    DateTime? fromDay,
    DateTime? toDay,
    String? rangerId,
  }) async {
    final queryParams = <String, String>{};

    if (fromDay != null) {
      queryParams['from'] = _formatIsoDay(fromDay);
    }
    if (toDay != null) {
      queryParams['to'] = _formatIsoDay(toDay);
    }

    final trimmedRangerId = rangerId?.trim();
    if (trimmedRangerId != null && trimmedRangerId.isNotEmpty) {
      queryParams['ranger_id'] = trimmedRangerId;
    }

    final uri = _buildUri('/api/mobile/schedules').replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return MobileScheduleListResult.fromJson(payload);
  }

  @override
  Future<MobileScheduleItem> createSchedule({
    required String accessToken,
    required String rangerId,
    required DateTime workDate,
    String note = '',
  }) async {
    final response = await _client.post(
      _buildUri('/api/mobile/schedules'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'ranger_id': rangerId,
        'work_date': _formatIsoDay(workDate),
        'note': note,
      }),
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawSchedule = payload['schedule'];
    if (rawSchedule is! Map<String, dynamic>) {
      throw MobileApiException(response.statusCode, response.body);
    }
    return MobileScheduleItem.fromJson(rawSchedule);
  }

  @override
  Future<MobileScheduleItem> updateSchedule({
    required String accessToken,
    required String scheduleId,
    required String rangerId,
    required DateTime workDate,
    String note = '',
  }) async {
    final response = await _client.put(
      _buildUri('/api/mobile/schedules/$scheduleId'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'ranger_id': rangerId,
        'work_date': _formatIsoDay(workDate),
        'note': note,
      }),
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawSchedule = payload['schedule'];
    if (rawSchedule is! Map<String, dynamic>) {
      throw MobileApiException(response.statusCode, response.body);
    }
    return MobileScheduleItem.fromJson(rawSchedule);
  }

  @override
  Future<void> deleteSchedule({
    required String accessToken,
    required String scheduleId,
  }) async {
    final response = await _client.delete(
      _buildUri('/api/mobile/schedules/$scheduleId'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }
  }

  @override
  Future<MobileUserProfile> fetchProfile({required String accessToken}) async {
    final response = await _client.get(
      _buildUri('/api/mobile/me'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return MobileUserProfile.fromJson(payload);
  }

  @override
  Future<MobileProfileUpdateResult> updateProfile({
    required String accessToken,
    required String displayName,
    required String region,
    required String phone,
  }) async {
    final response = await _client.put(
      _buildUri('/api/mobile/account/profile'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'display_name': displayName,
        'region': region,
        'phone': phone,
      }),
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return MobileProfileUpdateResult.fromJson(payload);
  }

  @override
  Future<String> uploadAvatar({
    required String accessToken,
    required List<int> imageBytes,
    required String filename,
  }) async {
    final uri = _buildUri('/api/mobile/account/avatar');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.headers['Accept'] = 'application/json';
    request.files.add(http.MultipartFile.fromBytes(
      'avatar',
      imageBytes,
      filename: filename,
    ));

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['avatar_url'] ?? '').toString();
  }

  @override
  Future<List<MobileEmployeeItem>> fetchEmployees({
    required String accessToken,
  }) async {
    final response = await _client.get(
      _buildUri('/api/mobile/employees'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawEmployees = payload['employees'];
    if (rawEmployees is! List) return [];
    return rawEmployees
        .whereType<Map<String, dynamic>>()
        .map(MobileEmployeeItem.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<MobileRangerStats>> fetchWorkStats({
    required String accessToken,
    required DateTime fromDay,
    required DateTime toDay,
    String? rangerId,
  }) async {
    final queryParams = <String, String>{
      'from': _formatIsoDay(fromDay),
      'to': _formatIsoDay(toDay),
    };
    final trimmedRangerId = rangerId?.trim();
    if (trimmedRangerId != null && trimmedRangerId.isNotEmpty) {
      queryParams['ranger_id'] = trimmedRangerId;
    }

    final uri = _buildUri('/api/mobile/work-management/stats').replace(
      queryParameters: queryParams,
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final rawStats = payload['stats'];
    if (rawStats is! List) return [];
    return rawStats
        .whereType<Map<String, dynamic>>()
        .map(MobileRangerStats.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<MobileForestCompartment>> fetchForestCompartments({
    required String accessToken,
    DateTime? fromDay,
    DateTime? toDay,
  }) async {
    final queryParams = <String, String>{};
    if (fromDay != null) queryParams['from'] = _formatIsoDay(fromDay);
    if (toDay != null) queryParams['to'] = _formatIsoDay(toDay);

    final uri = _buildUri('/api/mobile/forest-compartments').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = payload['compartments'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MobileForestCompartment.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<MobileAlert>> fetchAlerts({
    required String accessToken,
    int limit = 20,
  }) async {
    final uri = _buildUri('/api/mobile/alerts').replace(
      queryParameters: {'limit': '$limit'},
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = payload['alerts'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MobileAlert.fromJson)
        .toList(growable: false);
  }

  @override
  Future<MobileReportData> fetchReport({
    required String accessToken,
    required String reportType,
    required DateTime fromDay,
    required DateTime toDay,
  }) async {
    final uri = _buildUri('/api/mobile/reports/$reportType').replace(
      queryParameters: {
        'from': _formatIsoDay(fromDay),
        'to': _formatIsoDay(toDay),
      },
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw MobileApiException(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return MobileReportData.fromJson(payload);
  }
}
