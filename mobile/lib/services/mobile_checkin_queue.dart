import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

class MobileCheckinQueueStatus {
  static const String pending = 'pending';
  static const String synced = 'synced';
  static const String failed = 'failed';

  static String normalize(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    if (normalized == synced) {
      return synced;
    }
    if (normalized == failed) {
      return failed;
    }
    return pending;
  }
}

class MobileCheckinQueueItem {
  static final RegExp _isoDayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  final String queueId;
  final String userId;
  final String actionType;
  final String dayKey;
  final String clientUuid;
  final String idempotencyKey;
  final String clientTime;
  final String timezone;
  final String appVersion;
  final String status;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextRetryAt;
  final String? lastError;

  const MobileCheckinQueueItem({
    required this.queueId,
    required this.userId,
    required this.actionType,
    required this.dayKey,
    required this.clientUuid,
    required this.idempotencyKey,
    required this.clientTime,
    required this.timezone,
    required this.appVersion,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    required this.nextRetryAt,
    required this.lastError,
  });

  bool get isPending => status == MobileCheckinQueueStatus.pending;
  bool get isSynced => status == MobileCheckinQueueStatus.synced;
  bool get isFailed => status == MobileCheckinQueueStatus.failed;

  MobileCheckinQueueItem copyWith({
    String? status,
    int? attemptCount,
    DateTime? updatedAt,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    String? lastError,
    bool clearLastError = false,
  }) {
    return MobileCheckinQueueItem(
      queueId: queueId,
      userId: userId,
      actionType: actionType,
      dayKey: dayKey,
      clientUuid: clientUuid,
      idempotencyKey: idempotencyKey,
      clientTime: clientTime,
      timezone: timezone,
      appVersion: appVersion,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      nextRetryAt: clearNextRetryAt
          ? null
          : (nextRetryAt ?? this.nextRetryAt),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'queue_id': queueId,
      'user_id': userId,
      'action_type': actionType,
      'day_key': dayKey,
      'client_uuid': clientUuid,
      'idempotency_key': idempotencyKey,
      'client_time': clientTime,
      'timezone': timezone,
      'app_version': appVersion,
      'status': status,
      'attempt_count': attemptCount,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
      'last_error': lastError,
    };
  }

  factory MobileCheckinQueueItem.fromJson(Map<String, dynamic> json) {
    final queueId = (json['queue_id'] ?? '').toString().trim();
    final userId = (json['user_id'] ?? '').toString().trim();
    final actionType = (json['action_type'] ?? '').toString().trim();
    final dayKey = (json['day_key'] ?? '').toString().trim();
    final clientUuid = (json['client_uuid'] ?? '').toString().trim();
    final idempotencyKey = (json['idempotency_key'] ?? '').toString().trim();

    if (queueId.isEmpty ||
        userId.isEmpty ||
        actionType.isEmpty ||
        dayKey.isEmpty ||
        clientUuid.isEmpty ||
        idempotencyKey.isEmpty) {
      throw const FormatException('Invalid queue record payload');
    }

    if (!_isoDayPattern.hasMatch(dayKey)) {
      throw const FormatException('Invalid queue day_key format');
    }

    return MobileCheckinQueueItem(
      queueId: queueId,
      userId: userId,
      actionType: actionType,
      dayKey: dayKey,
      clientUuid: clientUuid,
      idempotencyKey: idempotencyKey,
      clientTime: (json['client_time'] ?? '').toString(),
      timezone: (json['timezone'] ?? '').toString(),
      appVersion: (json['app_version'] ?? '').toString(),
      status: MobileCheckinQueueStatus.normalize(
        (json['status'] ?? '').toString(),
      ),
      attemptCount: _parseAttemptCount(json['attempt_count']),
      createdAt: _parseIsoDateTime(json['created_at']) ?? DateTime.now().toUtc(),
      updatedAt: _parseIsoDateTime(json['updated_at']) ?? DateTime.now().toUtc(),
      nextRetryAt: _parseIsoDateTime(json['next_retry_at']),
      lastError: _normalizeNullableString(json['last_error']),
    );
  }

  static int _parseAttemptCount(dynamic value) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }
    if (value is num) {
      final parsed = value.toInt();
      return parsed < 0 ? 0 : parsed;
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim()) ?? 0;
      return parsed < 0 ? 0 : parsed;
    }
    return 0;
  }

  static DateTime? _parseIsoDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(raw.replaceAll('Z', '+00:00'));
    return parsed?.toUtc();
  }

  static String? _normalizeNullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }
}

class MobileCheckinQueueSummary {
  final int pendingCount;
  final int failedCount;
  final DateTime? nextRetryAt;

  const MobileCheckinQueueSummary({
    required this.pendingCount,
    required this.failedCount,
    required this.nextRetryAt,
  });
}

abstract class MobileCheckinQueueStore {
  Future<List<Map<String, dynamic>>> loadQueueItems();

  Future<void> saveQueueItems(List<Map<String, dynamic>> records);
}

class SharedPreferencesMobileCheckinQueueStore
    implements MobileCheckinQueueStore {
  static const String _storageKey = 'mobile.checkin.queue.v1';

  final Future<SharedPreferences> Function() _prefsProvider;

  SharedPreferencesMobileCheckinQueueStore({
    Future<SharedPreferences> Function()? prefsProvider,
  }) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  @override
  Future<List<Map<String, dynamic>>> loadQueueItems() async {
    final prefs = await _prefsProvider();
    final rawValue = prefs.getString(_storageKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! List) {
        return const <Map<String, dynamic>>[];
      }

      final normalized = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        final entry = <String, dynamic>{};
        for (final mapEntry in item.entries) {
          entry[mapEntry.key.toString()] = mapEntry.value;
        }
        normalized.add(entry);
      }

      return normalized;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  @override
  Future<void> saveQueueItems(List<Map<String, dynamic>> records) async {
    final prefs = await _prefsProvider();
    await prefs.setString(_storageKey, jsonEncode(records));
  }
}

class MobileCheckinReplayQueue {
  static const String checkinActionType = 'checkin';

  final MobileCheckinQueueStore _store;
  final Duration initialRetryDelay;
  final Duration maxRetryDelay;
  final int maxAttempts;
  final int maxSyncedHistory;
  final double jitterRatio;
  final DateTime Function() _nowUtc;
  final double Function() _jitterSource;
  final String Function() _uuidGenerator;
  Future<void> _mutationChain = Future<void>.value();

  MobileCheckinReplayQueue({
    required MobileCheckinQueueStore store,
    this.initialRetryDelay = const Duration(seconds: 5),
    this.maxRetryDelay = const Duration(minutes: 15),
    this.maxAttempts = 8,
    this.maxSyncedHistory = 100,
    this.jitterRatio = 0.25,
    DateTime Function()? nowUtc,
    double Function()? jitterSource,
    String Function()? uuidGenerator,
  })  : _store = store,
        _nowUtc = nowUtc ?? _defaultNowUtc,
        _jitterSource = jitterSource ?? _defaultJitterSource,
        _uuidGenerator = uuidGenerator ?? _defaultUuidGenerator;

  static DateTime _defaultNowUtc() => DateTime.now().toUtc();

  static final math.Random _random = math.Random();

  static double _defaultJitterSource() => _random.nextDouble();

  static String _defaultUuidGenerator() {
    final nowMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(0x7fffffff).toRadixString(16);
    return '$nowMicros-$randomPart';
  }

  static String projectDayKeyFromUtc(DateTime nowUtc) {
    final projectTime = nowUtc.toUtc().add(const Duration(hours: 7));
    final year = projectTime.year.toString().padLeft(4, '0');
    final month = projectTime.month.toString().padLeft(2, '0');
    final day = projectTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String composeIdempotencyKey({
    required String userId,
    required String actionType,
    required String dayKey,
    required String clientUuid,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedActionType = actionType.trim();
    final normalizedDayKey = dayKey.trim();
    final normalizedClientUuid = clientUuid.trim();

    return '$normalizedUserId:$normalizedActionType:$normalizedDayKey:$normalizedClientUuid';
  }

  Future<T> _withMutationLock<T>(Future<T> Function() operation) {
    final completer = Completer<void>();
    final previous = _mutationChain;
    _mutationChain = completer.future;

    return previous.then((_) => operation()).whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
  }

  static final RegExp _isoDayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  Future<List<MobileCheckinQueueItem>> listItems({
    String? userId,
  }) async {
    final normalizedFilterUserId = userId?.trim();
    final rawRecords = await _store.loadQueueItems();
    final parsed = <MobileCheckinQueueItem>[];
    for (final record in rawRecords) {
      try {
        final item = MobileCheckinQueueItem.fromJson(record);
        if (normalizedFilterUserId != null &&
            normalizedFilterUserId.isNotEmpty &&
            item.userId != normalizedFilterUserId) {
          continue;
        }
        parsed.add(item);
      } catch (_) {
        // Drop malformed persisted records.
      }
    }

    parsed.sort(_sortByCreatedAt);
    return parsed;
  }

  Future<MobileCheckinQueueSummary> summarize() async {
    final items = await listItems();
    var pendingCount = 0;
    var failedCount = 0;
    DateTime? nextRetryAt;

    for (final item in items) {
      if (item.isPending) {
        pendingCount += 1;
        final candidate = item.nextRetryAt;
        if (candidate != null &&
            (nextRetryAt == null || candidate.isBefore(nextRetryAt))) {
          nextRetryAt = candidate;
        }
      } else if (item.isFailed) {
        failedCount += 1;
      }
    }

    return MobileCheckinQueueSummary(
      pendingCount: pendingCount,
      failedCount: failedCount,
      nextRetryAt: nextRetryAt,
    );
  }

  Future<MobileCheckinQueueSummary> summarizeForUser(String userId) async {
    final items = await listItems(userId: userId);
    var pendingCount = 0;
    var failedCount = 0;
    DateTime? nextRetryAt;

    for (final item in items) {
      if (item.isPending) {
        pendingCount += 1;
        final candidate = item.nextRetryAt;
        if (candidate != null &&
            (nextRetryAt == null || candidate.isBefore(nextRetryAt))) {
          nextRetryAt = candidate;
        }
      } else if (item.isFailed) {
        failedCount += 1;
      }
    }

    return MobileCheckinQueueSummary(
      pendingCount: pendingCount,
      failedCount: failedCount,
      nextRetryAt: nextRetryAt,
    );
  }

  Future<MobileCheckinQueueItem> enqueueCheckin({
    required String userId,
    required String dayKey,
    required String timezoneName,
    required String appVersion,
    DateTime? clientTimeUtc,
    String actionType = checkinActionType,
    String? clientUuid,
    String? idempotencyKey,
  }) async {
    return _withMutationLock(() async {
      final normalizedUserId = userId.trim();
      final normalizedDayKey = dayKey.trim();
      final normalizedActionType = actionType.trim().isEmpty
          ? checkinActionType
          : actionType.trim();
      final normalizedTimezone = timezoneName.trim();
      final normalizedAppVersion = appVersion.trim();

      if (normalizedUserId.isEmpty || normalizedDayKey.isEmpty) {
        throw ArgumentError('userId and dayKey are required for queue enqueue');
      }
      if (!_isoDayPattern.hasMatch(normalizedDayKey)) {
        throw ArgumentError('dayKey must follow YYYY-MM-DD format');
      }
      if (normalizedTimezone.isEmpty) {
        throw ArgumentError('timezoneName is required for queue enqueue');
      }
      if (normalizedAppVersion.isEmpty) {
        throw ArgumentError('appVersion is required for queue enqueue');
      }

      final now = _nowUtc().toUtc();
      final normalizedClientTime =
          (clientTimeUtc ?? now).toUtc().toIso8601String();

      final items = await listItems();
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item.userId != normalizedUserId ||
            item.actionType != normalizedActionType ||
            item.dayKey != normalizedDayKey) {
          continue;
        }

        if (item.isSynced) {
          continue;
        }

        if (item.isFailed) {
          final rearmed = item.copyWith(
            status: MobileCheckinQueueStatus.pending,
            attemptCount: 0,
            updatedAt: now,
            clearNextRetryAt: true,
            clearLastError: true,
          );
          items[index] = rearmed;
          await _persist(items);
          return rearmed;
        }

        return item;
      }

      final providedClientUuid = clientUuid?.trim() ?? '';
      final generatedClientUuid = _uuidGenerator().trim();
      final normalizedClientUuid = providedClientUuid.isNotEmpty
          ? providedClientUuid
          : (generatedClientUuid.isEmpty
                ? _defaultUuidGenerator()
                : generatedClientUuid);

      final expectedIdempotencyKey = composeIdempotencyKey(
        userId: normalizedUserId,
        actionType: normalizedActionType,
        dayKey: normalizedDayKey,
        clientUuid: normalizedClientUuid,
      );

      final providedIdempotencyKey = idempotencyKey?.trim() ?? '';
      if (providedIdempotencyKey.isNotEmpty &&
          providedIdempotencyKey != expectedIdempotencyKey) {
        throw ArgumentError('Provided idempotencyKey does not match key components');
      }

      final normalizedIdempotencyKey = providedIdempotencyKey.isNotEmpty
          ? providedIdempotencyKey
          : expectedIdempotencyKey;

      final record = MobileCheckinQueueItem(
        queueId: normalizedClientUuid,
        userId: normalizedUserId,
        actionType: normalizedActionType,
        dayKey: normalizedDayKey,
        clientUuid: normalizedClientUuid,
        idempotencyKey: normalizedIdempotencyKey,
        clientTime: normalizedClientTime,
        timezone: normalizedTimezone,
        appVersion: normalizedAppVersion,
        status: MobileCheckinQueueStatus.pending,
        attemptCount: 0,
        createdAt: now,
        updatedAt: now,
        nextRetryAt: null,
        lastError: null,
      );

      items.add(record);
      await _persist(items);
      return record;
    });
  }

  Future<List<MobileCheckinQueueItem>> readyForReplay({
    DateTime? referenceTime,
    String? userId,
  }) async {
    final now = (referenceTime ?? _nowUtc()).toUtc();
    final items = await listItems(userId: userId);
    return items
        .where(
          (item) =>
              item.isPending &&
              (item.nextRetryAt == null || !item.nextRetryAt!.isAfter(now)),
        )
        .toList(growable: false)
      ..sort(_sortByCreatedAt);
  }

  Future<MobileCheckinQueueItem?> markSynced(
    String queueId, {
    String? userId,
  }) async {
    return _withMutationLock(() async {
      final normalizedQueueId = queueId.trim();
      final normalizedUserId = userId?.trim();
      if (normalizedQueueId.isEmpty) {
        return null;
      }

      final items = await listItems();
      final index = items.indexWhere(
        (item) =>
            item.queueId == normalizedQueueId &&
            (normalizedUserId == null ||
                normalizedUserId.isEmpty ||
                item.userId == normalizedUserId),
      );
      if (index < 0) {
        return null;
      }

      final now = _nowUtc().toUtc();
      final updated = items[index].copyWith(
        status: MobileCheckinQueueStatus.synced,
        updatedAt: now,
        clearNextRetryAt: true,
        clearLastError: true,
      );

      items[index] = updated;
      await _persist(items);
      return updated;
    });
  }

  Future<MobileCheckinQueueItem?> markReplayFailure({
    required String queueId,
    required String errorMessage,
    String? userId,
  }) async {
    return _withMutationLock(() async {
      final normalizedQueueId = queueId.trim();
      final normalizedUserId = userId?.trim();
      if (normalizedQueueId.isEmpty) {
        return null;
      }

      final items = await listItems();
      final index = items.indexWhere(
        (item) =>
            item.queueId == normalizedQueueId &&
            (normalizedUserId == null ||
                normalizedUserId.isEmpty ||
                item.userId == normalizedUserId),
      );
      if (index < 0) {
        return null;
      }

      final now = _nowUtc().toUtc();
      final current = items[index];
      final nextAttempt = current.attemptCount + 1;

      if (nextAttempt >= maxAttempts) {
        final failed = current.copyWith(
          status: MobileCheckinQueueStatus.failed,
          attemptCount: nextAttempt,
          updatedAt: now,
          clearNextRetryAt: true,
          lastError: errorMessage,
        );
        items[index] = failed;
        await _persist(items);
        return failed;
      }

      final retryDelay = _computeRetryDelay(nextAttempt);
      final pending = current.copyWith(
        status: MobileCheckinQueueStatus.pending,
        attemptCount: nextAttempt,
        updatedAt: now,
        nextRetryAt: now.add(retryDelay),
        lastError: errorMessage,
      );

      items[index] = pending;
      await _persist(items);
      return pending;
    });
  }

  Future<MobileCheckinQueueItem?> prepareFailedForManualRetry(
    String queueId, {
    bool resetAttemptCount = true,
    String? userId,
  }) async {
    return _withMutationLock(() async {
      final normalizedQueueId = queueId.trim();
      final normalizedUserId = userId?.trim();
      if (normalizedQueueId.isEmpty) {
        return null;
      }

      final items = await listItems();
      final index = items.indexWhere(
        (item) =>
            item.queueId == normalizedQueueId &&
            (normalizedUserId == null ||
                normalizedUserId.isEmpty ||
                item.userId == normalizedUserId),
      );
      if (index < 0) {
        return null;
      }

      final current = items[index];
      if (!current.isFailed) {
        return current;
      }

      final now = _nowUtc().toUtc();
      final pending = current.copyWith(
        status: MobileCheckinQueueStatus.pending,
        attemptCount: resetAttemptCount ? 0 : current.attemptCount,
        updatedAt: now,
        clearNextRetryAt: true,
        clearLastError: true,
      );

      items[index] = pending;
      await _persist(items);
      return pending;
    });
  }

  Duration _computeRetryDelay(int attemptNumber) {
    final safeAttempt = attemptNumber < 1 ? 1 : attemptNumber;
    final baseSeconds = math.max(1, initialRetryDelay.inSeconds);
    final maxSeconds = math.max(baseSeconds, maxRetryDelay.inSeconds);

    final exponential = math.min(
      maxSeconds.toDouble(),
      baseSeconds * math.pow(2, safeAttempt - 1),
    );

    final normalizedJitterRatio = jitterRatio <= 0 ? 0.0 : jitterRatio;
    final jitterCap = exponential * normalizedJitterRatio;
    final jitterSeed = _jitterSource();
    final normalizedSeed = jitterSeed.isNaN ? 0.0 : jitterSeed.clamp(0.0, 1.0);
    final jitter = jitterCap * normalizedSeed;
    final totalSeconds = math.min(maxSeconds.toDouble(), exponential + jitter);

    return Duration(milliseconds: (totalSeconds * 1000).round());
  }

  Future<void> _persist(List<MobileCheckinQueueItem> items) async {
    if (maxSyncedHistory >= 0) {
      final unsynced = items.where((item) => !item.isSynced).toList(growable: false);
      final synced = items
          .where((item) => item.isSynced)
          .toList(growable: false)
        ..sort((a, b) {
          final updatedCompare = b.updatedAt.compareTo(a.updatedAt);
          if (updatedCompare != 0) {
            return updatedCompare;
          }
          return b.queueId.compareTo(a.queueId);
        });

      final retainedSynced = synced.take(maxSyncedHistory).toList(growable: false);
      items
        ..clear()
        ..addAll(unsynced)
        ..addAll(retainedSynced);
    }

    items.sort(_sortByCreatedAt);
    await _store.saveQueueItems(
      items.map((item) => item.toJson()).toList(growable: false),
    );
  }

  static int _sortByCreatedAt(
    MobileCheckinQueueItem a,
    MobileCheckinQueueItem b,
  ) {
    final compareCreated = a.createdAt.compareTo(b.createdAt);
    if (compareCreated != 0) {
      return compareCreated;
    }
    return a.queueId.compareTo(b.queueId);
  }
}