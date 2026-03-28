import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api_service.dart';

class CachedReadModel<T> {
  final T value;
  final DateTime? syncedAt;

  const CachedReadModel({required this.value, required this.syncedAt});
}

abstract class MobileReadModelCache {
  Future<CachedReadModel<MobileWorkSummaryResult>?> loadWorkSummary(String cacheKey);

  Future<void> saveWorkSummary({
    required String cacheKey,
    required MobileWorkSummaryResult value,
    required DateTime syncedAt,
  });

  Future<CachedReadModel<MobileIncidentListResult>?> loadIncidents(String cacheKey);

  Future<void> saveIncidents({
    required String cacheKey,
    required MobileIncidentListResult value,
    required DateTime syncedAt,
  });

  Future<CachedReadModel<MobileScheduleListResult>?> loadSchedules(String cacheKey);

  Future<void> saveSchedules({
    required String cacheKey,
    required MobileScheduleListResult value,
    required DateTime syncedAt,
  });
}

class SharedPreferencesMobileReadModelCache implements MobileReadModelCache {
  static const String _workBucketKey = 'mobile.read_model.work.v1';
  static const String _incidentBucketKey = 'mobile.read_model.incident.v1';
  static const String _scheduleBucketKey = 'mobile.read_model.schedule.v1';
  static const int _maxEntriesPerBucket = 64;

  final Future<SharedPreferences> Function() _prefsProvider;

  SharedPreferencesMobileReadModelCache({
    Future<SharedPreferences> Function()? prefsProvider,
  }) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  @override
  Future<CachedReadModel<MobileWorkSummaryResult>?> loadWorkSummary(
    String cacheKey,
  ) async {
    final entry = await _loadEntry(_workBucketKey, cacheKey);
    if (entry == null) {
      return null;
    }

    final rawValue = entry['value'];
    if (rawValue is! Map) {
      return null;
    }

    final payload = _normalizeMap(rawValue);
    if (payload == null) {
      return null;
    }

    try {
      final parsed = MobileWorkSummaryResult.fromJson(payload);
      return CachedReadModel<MobileWorkSummaryResult>(
        value: parsed,
        syncedAt: _parseIsoDateTime(entry['synced_at']),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveWorkSummary({
    required String cacheKey,
    required MobileWorkSummaryResult value,
    required DateTime syncedAt,
  }) {
    return _saveEntry(
      bucketKey: _workBucketKey,
      cacheKey: cacheKey,
      entry: <String, dynamic>{
        'synced_at': syncedAt.toUtc().toIso8601String(),
        'value': _workSummaryToJson(value),
      },
    );
  }

  @override
  Future<CachedReadModel<MobileIncidentListResult>?> loadIncidents(
    String cacheKey,
  ) async {
    final entry = await _loadEntry(_incidentBucketKey, cacheKey);
    if (entry == null) {
      return null;
    }

    final rawValue = entry['value'];
    if (rawValue is! Map) {
      return null;
    }

    final payload = _normalizeMap(rawValue);
    if (payload == null) {
      return null;
    }

    try {
      final parsed = MobileIncidentListResult.fromJson(payload);
      return CachedReadModel<MobileIncidentListResult>(
        value: parsed,
        syncedAt: _parseIsoDateTime(entry['synced_at']),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveIncidents({
    required String cacheKey,
    required MobileIncidentListResult value,
    required DateTime syncedAt,
  }) {
    return _saveEntry(
      bucketKey: _incidentBucketKey,
      cacheKey: cacheKey,
      entry: <String, dynamic>{
        'synced_at': syncedAt.toUtc().toIso8601String(),
        'value': _incidentListToJson(value),
      },
    );
  }

  @override
  Future<CachedReadModel<MobileScheduleListResult>?> loadSchedules(
    String cacheKey,
  ) async {
    final entry = await _loadEntry(_scheduleBucketKey, cacheKey);
    if (entry == null) {
      return null;
    }

    final rawValue = entry['value'];
    if (rawValue is! Map) {
      return null;
    }

    final payload = _normalizeMap(rawValue);
    if (payload == null) {
      return null;
    }

    try {
      final parsed = MobileScheduleListResult.fromJson(payload);
      return CachedReadModel<MobileScheduleListResult>(
        value: parsed,
        syncedAt: _parseIsoDateTime(entry['synced_at']),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSchedules({
    required String cacheKey,
    required MobileScheduleListResult value,
    required DateTime syncedAt,
  }) {
    return _saveEntry(
      bucketKey: _scheduleBucketKey,
      cacheKey: cacheKey,
      entry: <String, dynamic>{
        'synced_at': syncedAt.toUtc().toIso8601String(),
        'value': _scheduleListToJson(value),
      },
    );
  }

  Future<Map<String, dynamic>?> _loadEntry(String bucketKey, String cacheKey) async {
    final prefs = await _prefsProvider();
    final bucket = _decodeBucket(prefs.getString(bucketKey));
    final rawEntry = bucket[cacheKey];

    if (rawEntry is! Map) {
      return null;
    }

    return _normalizeMap(rawEntry);
  }

  Future<void> _saveEntry({
    required String bucketKey,
    required String cacheKey,
    required Map<String, dynamic> entry,
  }) async {
    final prefs = await _prefsProvider();
    final bucket = _decodeBucket(prefs.getString(bucketKey));
    bucket[cacheKey] = entry;
    _pruneBucket(bucket);
    await prefs.setString(bucketKey, jsonEncode(bucket));
  }

  void _pruneBucket(Map<String, dynamic> bucket) {
    while (bucket.length > _maxEntriesPerBucket) {
      final firstKey = bucket.keys.first;
      bucket.remove(firstKey);
    }
  }

  Map<String, dynamic> _decodeBucket(String? rawBucket) {
    if (rawBucket == null || rawBucket.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(rawBucket);
      if (decoded is! Map) {
        return <String, dynamic>{};
      }
      final normalized = _normalizeMap(decoded);
      return normalized ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic>? _normalizeMap(dynamic value) {
    if (value is! Map) {
      return null;
    }

    final normalized = <String, dynamic>{};
    for (final entry in value.entries) {
      normalized[entry.key.toString()] = entry.value;
    }
    return normalized;
  }

  DateTime? _parseIsoDateTime(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = rawValue.toString().trim();
    if (normalized.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(normalized.replaceAll('Z', '+00:00'));
    return parsed?.toUtc();
  }

  Map<String, dynamic> _workSummaryToJson(MobileWorkSummaryResult value) {
    return <String, dynamic>{
      'items': value.items
          .map(
            (item) => <String, dynamic>{
              'ranger_id': item.rangerId,
              'day_key': item.dayKey,
              'has_checkin': item.hasCheckin,
              'checkin_indicator': item.checkinIndicator,
              'summary': item.summary,
            },
          )
          .toList(growable: false),
      'scope': <String, dynamic>{
        'role': value.scope.role,
        'team_scope': value.scope.teamScope,
        'requested_ranger_id': value.scope.requestedRangerId,
        'effective_ranger_id': value.scope.effectiveRangerId,
      },
      'pagination': <String, dynamic>{
        'page': value.pagination.page,
        'page_size': value.pagination.pageSize,
        'total': value.pagination.total,
        'total_pages': value.pagination.totalPages,
      },
      'filters': <String, dynamic>{
        'from': value.fromDay,
        'to': value.toDay,
      },
    };
  }

  Map<String, dynamic> _incidentListToJson(MobileIncidentListResult value) {
    return <String, dynamic>{
      'items': value.items
          .map(
            (item) => <String, dynamic>{
              'incident_id': item.incidentId,
              'er_event_id': item.erEventId,
              'ranger_id': item.rangerId,
              'mapping_status': item.mappingStatus,
              'occurred_at': item.occurredAt,
              'updated_at': item.updatedAt,
              'title': item.title,
              'status': item.status,
              'severity': item.severity,
              'payload_ref': item.payloadRef,
            },
          )
          .toList(growable: false),
      'scope': <String, dynamic>{
        'role': value.scope.role,
        'team_scope': value.scope.teamScope,
        'requested_ranger_id': value.scope.requestedRangerId,
        'effective_ranger_id': value.scope.effectiveRangerId,
      },
      'pagination': <String, dynamic>{
        'page': value.pagination.page,
        'page_size': value.pagination.pageSize,
        'total': value.pagination.total,
        'total_pages': value.pagination.totalPages,
      },
      'sync': <String, dynamic>{
        'cursor': value.sync.cursor,
        'has_more': value.sync.hasMore,
        'last_synced_at': value.sync.lastSyncedAt,
      },
      'filters': <String, dynamic>{
        'from': value.fromDay,
        'to': value.toDay,
        'updated_since': value.updatedSince,
      },
    };
  }

  Map<String, dynamic> _scheduleListToJson(MobileScheduleListResult value) {
    return <String, dynamic>{
      'items': value.items
          .map(
            (item) => <String, dynamic>{
              'schedule_id': item.scheduleId,
              'ranger_id': item.rangerId,
              'work_date': item.workDate,
              'note': item.note,
              'updated_by': item.updatedBy,
              'created_at': item.createdAt,
              'updated_at': item.updatedAt,
            },
          )
          .toList(growable: false),
      'scope': <String, dynamic>{
        'role': value.scope.role,
        'account_role': value.scope.accountRole,
        'team_scope': value.scope.teamScope,
        'requested_ranger_id': value.scope.requestedRangerId,
        'effective_ranger_id': value.scope.effectiveRangerId,
      },
      'filters': <String, dynamic>{
        'from': value.fromDay,
        'to': value.toDay,
      },
      'directory': value.directory
          .map(
            (entry) => <String, dynamic>{
              'username': entry.username,
              'display_name': entry.displayName,
              'role': entry.role,
            },
          )
          .toList(growable: false),
    };
  }
}
