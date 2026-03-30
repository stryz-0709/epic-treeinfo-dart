import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';

import '../services/mobile_api_service.dart';
import '../services/mobile_checkin_queue.dart';
import '../services/mobile_read_model_cache.dart';
import 'auth_provider.dart';

class WorkCheckinSyncStatusItem {
  final String queueId;
  final String dayKey;
  final String status;
  final int attemptCount;
  final DateTime updatedAt;
  final DateTime? nextRetryAt;
  final String? lastError;

  const WorkCheckinSyncStatusItem({
    required this.queueId,
    required this.dayKey,
    required this.status,
    required this.attemptCount,
    required this.updatedAt,
    required this.nextRetryAt,
    required this.lastError,
  });

  bool get isPending => status == MobileCheckinQueueStatus.pending;
  bool get isSynced => status == MobileCheckinQueueStatus.synced;
  bool get isFailed => status == MobileCheckinQueueStatus.failed;

  factory WorkCheckinSyncStatusItem.fromQueueItem(MobileCheckinQueueItem item) {
    return WorkCheckinSyncStatusItem(
      queueId: item.queueId,
      dayKey: item.dayKey,
      status: item.status,
      attemptCount: item.attemptCount,
      updatedAt: item.updatedAt,
      nextRetryAt: item.nextRetryAt,
      lastError: item.lastError,
    );
  }
}

class WorkManagementProvider extends ChangeNotifier {
  final MobileCheckinApi _mobileCheckinApi;
  final MobileWorkSummaryApi? _mobileWorkSummaryApi;
  final MobileReadModelCache? _cache;
  final MobileCheckinReplayQueue? _checkinQueue;
  final Duration staleAfter;

  WorkManagementProvider({
    required MobileCheckinApi mobileCheckinApi,
    MobileWorkSummaryApi? mobileWorkSummaryApi,
    MobileReadModelCache? cache,
    MobileCheckinReplayQueue? checkinQueue,
    this.staleAfter = const Duration(minutes: 30),
  })  : _mobileCheckinApi = mobileCheckinApi,
        _mobileWorkSummaryApi = mobileWorkSummaryApi,
        _cache = cache,
        _checkinQueue = checkinQueue;

  String? _lastCheckinDayKey;
  String? _lastCheckinStatus;
  String? _lastCheckinServerTime;
  String? _checkinError;
  bool _isSyncingCheckin = false;
  bool _isReplayingCheckins = false;
  int _pendingCheckinCount = 0;
  int _failedCheckinCount = 0;
  DateTime? _nextCheckinRetryAt;
  List<WorkCheckinSyncStatusItem> _checkinSyncItems =
      const <WorkCheckinSyncStatusItem>[];
  int _checkinClientSequence = 0;

  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  bool _isLoadingSummary = false;
  String? _summaryError;
  String? _summaryRefreshError;
  DateTime? _summaryLastSyncedAt;
  bool _isSummaryStale = false;
  bool _isSummaryOfflineFallback = false;
  bool _isUsingCachedSummary = false;
  String _summaryRole = 'ranger';
  bool _teamScope = false;
  String? _selectedRangerId;
  String? _effectiveRangerId;
  int _summaryPage = 1;
  int _summaryPageSize = 62;
  int _summaryTotal = 0;
  int _summaryTotalPages = 0;
  final Map<String, List<MobileWorkSummaryItem>> _itemsByDay = {};
  List<String> _availableRangerIds = const [];
  String? _activeSummaryCacheKey;
  String? _activeSummarySessionKey;
  int _summaryRequestId = 0;

  String? get lastCheckinDayKey => _lastCheckinDayKey;
  String? get lastCheckinStatus => _lastCheckinStatus;
  String? get lastCheckinServerTime => _lastCheckinServerTime;
  String? get checkinError => _checkinError;
  bool get isSyncingCheckin => _isSyncingCheckin;
  bool get isReplayingCheckins => _isReplayingCheckins;
  int get pendingCheckinCount => _pendingCheckinCount;
  int get failedCheckinCount => _failedCheckinCount;
  DateTime? get nextCheckinRetryAt => _nextCheckinRetryAt;
  bool get hasPendingCheckinQueue => _pendingCheckinCount > 0;
    List<WorkCheckinSyncStatusItem> get checkinSyncItems =>
      List.unmodifiable(_checkinSyncItems);
    int get syncedCheckinCount =>
      _checkinSyncItems.where((item) => item.isSynced).length;
  DateTime get focusedMonth => _focusedMonth;
  DateTime get selectedDay => _selectedDay;
  bool get isLoadingSummary => _isLoadingSummary;
  String? get summaryError => _summaryError;
  String? get summaryRefreshError => _summaryRefreshError;
  DateTime? get summaryLastSyncedAt => _summaryLastSyncedAt;
  bool get isSummaryStaleData => _isSummaryStale;
  bool get isSummaryOfflineFallback => _isSummaryOfflineFallback;
  bool get isUsingCachedSummary => _isUsingCachedSummary;
  String get summaryRole => _summaryRole;
  bool get isLeaderScope => _summaryRole == 'leader';
  bool get teamScope => _teamScope;
  String? get selectedRangerId => _selectedRangerId;
  String? get effectiveRangerId => _effectiveRangerId;
  int get summaryPage => _summaryPage;
  int get summaryPageSize => _summaryPageSize;
  int get summaryTotal => _summaryTotal;
  int get summaryTotalPages => _summaryTotalPages;
  List<String> get availableRangerIds =>
      List.unmodifiable(_availableRangerIds);
  bool get hasCalendarData => _itemsByDay.isNotEmpty;

  void _resetCheckinState() {
    _lastCheckinDayKey = null;
    _lastCheckinStatus = null;
    _lastCheckinServerTime = null;
    _checkinError = null;
  }

  String _isoDay(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    return normalized.toIso8601String().split('T').first;
  }

  String _deriveRoleFromAuth(AuthProvider authProvider) {
    if (authProvider.mobileRole == 'leader') {
      return 'leader';
    }
    return 'ranger';
  }

  String _monthKey(DateTime month) {
    final yyyy = month.year.toString().padLeft(4, '0');
    final mm = month.month.toString().padLeft(2, '0');
    return '$yyyy-$mm';
  }

  String _cacheKeyForSummary({
    required DateTime month,
    required String role,
    required String sessionPartition,
    String? rangerId,
  }) {
    final normalizedRangerId = rangerId?.trim();
    final rangerScope =
        normalizedRangerId == null || normalizedRangerId.isEmpty
            ? 'all'
            : normalizedRangerId;

    return 'month=${_monthKey(month)}|role=$role|ranger=$rangerScope|session=$sessionPartition';
  }

  String _sessionPartitionFromAuth(AuthProvider authProvider) {
    final refreshToken = authProvider.mobileRefreshToken?.trim() ?? '';
    final accessToken = authProvider.mobileAccessToken?.trim() ?? '';
    final seed = refreshToken.isNotEmpty ? refreshToken : accessToken;

    if (seed.isEmpty) {
      return 'anon';
    }

    final digest = sha256.convert(utf8.encode(seed)).toString();
    return 'u$digest';
  }

  bool _computeSummaryStale(DateTime? syncedAt) {
    if (!hasCalendarData) {
      return false;
    }
    if (syncedAt == null) {
      return true;
    }
    return DateTime.now().toUtc().difference(syncedAt) > staleAfter;
  }

  bool _isCurrentSummaryRequest(int requestId) {
    return requestId == _summaryRequestId;
  }

  String _summaryLoadErrorMessage(Object error) {
    if (error is MobileApiException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Session expired. Please sign in again.';
      }
    }
    return 'Unable to load Work Management data.';
  }

  String _summaryRefreshErrorMessage(Object error) {
    if (error is MobileApiException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Session expired. Please sign in again.';
      }
    }
    return 'Unable to refresh Work Management data.';
  }

  String _checkinErrorMessage(Object error) {
    if (error is MobileApiException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Session expired. Please sign in again.';
      }
    }
    return 'Unable to sync check-in right now.';
  }

  bool _isAuthCheckinFailure(Object error) {
    if (error is MobileApiException) {
      return error.statusCode == 401 || error.statusCode == 403;
    }
    return false;
  }

  Future<MobileWorkSummaryResult> _fetchWorkSummaryWithTokenRetry({
    required AuthProvider authProvider,
    required DateTime fromDay,
    required DateTime toDay,
    required int page,
    required int pageSize,
    String? rangerId,
  }) async {
    final api = _mobileWorkSummaryApi;
    if (api == null) {
      throw StateError('Work summary API unavailable');
    }

    final initialToken = authProvider.mobileAccessToken?.trim() ?? '';
    if (initialToken.isEmpty) {
      throw StateError('Missing mobile access token');
    }

    try {
      return await api.fetchWorkSummary(
        accessToken: initialToken,
        fromDay: fromDay,
        toDay: toDay,
        rangerId: rangerId,
        page: page,
        pageSize: pageSize,
      );
    } on MobileApiException catch (error) {
      final latestToken = authProvider.mobileAccessToken?.trim() ?? '';
      final shouldRetry =
          (error.statusCode == 401 || error.statusCode == 403) &&
          latestToken.isNotEmpty &&
          latestToken != initialToken;

      if (!shouldRetry) {
        rethrow;
      }

      return api.fetchWorkSummary(
        accessToken: latestToken,
        fromDay: fromDay,
        toDay: toDay,
        rangerId: rangerId,
        page: page,
        pageSize: pageSize,
      );
    }
  }

  Future<Position?> _tryGetCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<MobileCheckinResult> _submitCheckinWithTokenRetry({
    required AuthProvider authProvider,
    required String idempotencyKey,
    required String clientTime,
    required String timezone,
    required String appVersion,
    double? latitude,
    double? longitude,
  }) async {
    final initialToken = authProvider.mobileAccessToken?.trim() ?? '';
    if (initialToken.isEmpty) {
      throw StateError('Missing mobile access token');
    }

    try {
      return await _mobileCheckinApi.submitAppOpenCheckin(
        accessToken: initialToken,
        idempotencyKey: idempotencyKey,
        clientTime: clientTime,
        timezone: timezone,
        appVersion: appVersion,
        latitude: latitude,
        longitude: longitude,
      );
    } on MobileApiException catch (error) {
      final latestToken = authProvider.mobileAccessToken?.trim() ?? '';
      final shouldRetry =
          (error.statusCode == 401 || error.statusCode == 403) &&
          latestToken.isNotEmpty &&
          latestToken != initialToken;

      if (!shouldRetry) {
        rethrow;
      }

      return _mobileCheckinApi.submitAppOpenCheckin(
        accessToken: latestToken,
        idempotencyKey: idempotencyKey,
        clientTime: clientTime,
        timezone: timezone,
        appVersion: appVersion,
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  bool _isQueueableCheckinFailure(Object error) {
    if (error is StateError || error is FormatException || error is ArgumentError) {
      return false;
    }

    if (error is MobileApiException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return false;
      }
      if (error.statusCode == 400) {
        return false;
      }
      if (error.statusCode == 408 || error.statusCode == 429) {
        return true;
      }
      return error.statusCode >= 500;
    }

    // Treat transport/runtime exceptions as transient offline failures.
    return true;
  }

  String? _resolveCheckinUserId(AuthProvider authProvider) {
    final username = authProvider.mobileUsername?.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }

    return null;
  }

  String _generateCheckinClientUuid() {
    _checkinClientSequence += 1;
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return '$micros-${_checkinClientSequence.toRadixString(16)}';
  }

  Future<void> _refreshCheckinQueueSummary() async {
    if (_checkinQueue == null) {
      _pendingCheckinCount = 0;
      _failedCheckinCount = 0;
      _nextCheckinRetryAt = null;
      _checkinSyncItems = const <WorkCheckinSyncStatusItem>[];
      return;
    }

    _pendingCheckinCount = 0;
    _failedCheckinCount = 0;
    _nextCheckinRetryAt = null;
    _checkinSyncItems = const <WorkCheckinSyncStatusItem>[];
  }

  Future<void> _refreshCheckinQueueSummaryForUser(String? queueUserId) async {
    final normalizedQueueUserId = queueUserId?.trim();
    if (_checkinQueue == null ||
        normalizedQueueUserId == null ||
        normalizedQueueUserId.isEmpty) {
      _pendingCheckinCount = 0;
      _failedCheckinCount = 0;
      _nextCheckinRetryAt = null;
      _checkinSyncItems = const <WorkCheckinSyncStatusItem>[];
      return;
    }

    final summary = await _checkinQueue.summarizeForUser(normalizedQueueUserId);
    final items = await _checkinQueue.listItems(userId: normalizedQueueUserId);
    final statusItems = items
        .map(WorkCheckinSyncStatusItem.fromQueueItem)
        .toList(growable: false)
      ..sort((a, b) {
        final updatedCompare = b.updatedAt.compareTo(a.updatedAt);
        if (updatedCompare != 0) {
          return updatedCompare;
        }
        return b.queueId.compareTo(a.queueId);
      });

    _pendingCheckinCount = summary.pendingCount;
    _failedCheckinCount = summary.failedCount;
    _nextCheckinRetryAt = summary.nextRetryAt;
    _checkinSyncItems = statusItems;
  }

  Future<bool> replayQueuedCheckins({
    required AuthProvider authProvider,
    Set<String>? queueIds,
  }) async {
    if (_checkinQueue == null) {
      return true;
    }

    if (_isReplayingCheckins) {
      return false;
    }

    if (!authProvider.isRangerSession) {
      await _refreshCheckinQueueSummary();
      notifyListeners();
      return true;
    }

    final accessToken = authProvider.mobileAccessToken?.trim();
    final queueUserId = _resolveCheckinUserId(authProvider);
    final normalizedQueueIds = queueIds
        ?.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    if (accessToken == null || accessToken.isEmpty) {
      await _refreshCheckinQueueSummaryForUser(queueUserId);
      notifyListeners();
      return true;
    }

    if (queueUserId == null || queueUserId.isEmpty) {
      await _refreshCheckinQueueSummary();
      notifyListeners();
      return true;
    }

    _isReplayingCheckins = true;
    notifyListeners();

    var blockedByAuthFailure = false;
    var blockedByReplayValidationFailure = false;

    try {
      final readyItems = await _checkinQueue.readyForReplay(userId: queueUserId);
      for (final queueItem in readyItems) {
        if (normalizedQueueIds != null &&
            !normalizedQueueIds.contains(queueItem.queueId)) {
          continue;
        }

        try {
          final replayResult = await _submitCheckinWithTokenRetry(
            authProvider: authProvider,
            idempotencyKey: queueItem.idempotencyKey,
            clientTime: queueItem.clientTime,
            timezone: queueItem.timezone,
            appVersion: queueItem.appVersion,
          );

          if (replayResult.status == 'created' ||
              replayResult.status == 'already_exists') {
            final responseDayKey = replayResult.dayKey.trim();
            if (responseDayKey.isNotEmpty && responseDayKey != queueItem.dayKey) {
              await _checkinQueue.markReplayFailure(
                queueId: queueItem.queueId,
                errorMessage:
                    'Replay day-key mismatch: expected ${queueItem.dayKey}, got ${replayResult.dayKey}',
                userId: queueUserId,
              );
              _checkinError = 'Unable to verify replayed check-in day key.';
              blockedByReplayValidationFailure = true;
              await _refreshCheckinQueueSummaryForUser(queueUserId);
              notifyListeners();
              continue;
            }

            final responseIdempotencyKey = replayResult.idempotencyKey.trim();
            if (responseIdempotencyKey.isNotEmpty &&
                responseIdempotencyKey != queueItem.idempotencyKey) {
              await _checkinQueue.markReplayFailure(
                queueId: queueItem.queueId,
                errorMessage:
                    'Replay idempotency mismatch: expected ${queueItem.idempotencyKey}, got ${replayResult.idempotencyKey}',
                userId: queueUserId,
              );
              _checkinError = 'Unable to verify replayed check-in identity.';
              blockedByReplayValidationFailure = true;
              await _refreshCheckinQueueSummaryForUser(queueUserId);
              notifyListeners();
              continue;
            }

            await _checkinQueue.markSynced(
              queueItem.queueId,
              userId: queueUserId,
            );
            _lastCheckinDayKey = responseDayKey.isEmpty
                ? queueItem.dayKey
                : responseDayKey;
            _lastCheckinStatus = replayResult.status;
            _lastCheckinServerTime = replayResult.serverTime;
            _checkinError = null;
            await _refreshCheckinQueueSummaryForUser(queueUserId);
            notifyListeners();
          } else {
            await _checkinQueue.markReplayFailure(
              queueId: queueItem.queueId,
              errorMessage: 'Unexpected check-in replay status: ${replayResult.status}',
              userId: queueUserId,
            );
            _checkinError = 'Unable to verify replayed check-in status.';
            blockedByReplayValidationFailure = true;
            await _refreshCheckinQueueSummaryForUser(queueUserId);
            notifyListeners();
          }
        } catch (error) {
          if (_isAuthCheckinFailure(error)) {
            _checkinError = _checkinErrorMessage(error);
            blockedByAuthFailure = true;
            break;
          }

          await _checkinQueue.markReplayFailure(
            queueId: queueItem.queueId,
            errorMessage: _checkinErrorMessage(error),
            userId: queueUserId,
          );
          await _refreshCheckinQueueSummaryForUser(queueUserId);
          notifyListeners();
        }
      }

      await _refreshCheckinQueueSummaryForUser(queueUserId);
      return !blockedByAuthFailure && !blockedByReplayValidationFailure;
    } finally {
      _isReplayingCheckins = false;
      notifyListeners();
    }
  }

  List<MobileWorkSummaryItem> _scopeSummaryItems({
    required List<MobileWorkSummaryItem> items,
    required String role,
    required String? effectiveRangerId,
  }) {
    if (role != 'ranger') {
      return List<MobileWorkSummaryItem>.from(items, growable: false);
    }

    final effective = effectiveRangerId?.trim();
    if (effective == null || effective.isEmpty) {
      return const <MobileWorkSummaryItem>[];
    }

    return items
        .where((item) => item.rangerId.trim() == effective)
        .toList(growable: false);
  }

  List<MobileWorkSummaryItem> _mergeSummaryItems({
    required List<MobileWorkSummaryItem> base,
    required List<MobileWorkSummaryItem> incoming,
  }) {
    final mergedByKey = <String, MobileWorkSummaryItem>{};

    for (final item in base) {
      final dayKey = item.dayKey.trim();
      final rangerId = item.rangerId.trim();
      if (dayKey.isEmpty || rangerId.isEmpty) {
        continue;
      }
      mergedByKey['$dayKey::$rangerId'] = item;
    }

    for (final item in incoming) {
      final dayKey = item.dayKey.trim();
      final rangerId = item.rangerId.trim();
      if (dayKey.isEmpty || rangerId.isEmpty) {
        continue;
      }
      mergedByKey['$dayKey::$rangerId'] = item;
    }

    final merged = mergedByKey.values.toList(growable: false)
      ..sort((a, b) {
        final dayCompare = a.dayKey.compareTo(b.dayKey);
        if (dayCompare != 0) {
          return dayCompare;
        }
        return a.rangerId.compareTo(b.rangerId);
      });

    return merged;
  }

  void _applySummaryResult(
    MobileWorkSummaryResult result, {
    required String authRole,
  }) {
    final resolvedRole = authRole == 'leader' ? 'leader' : 'ranger';
    final requestedRangerId = result.scope.requestedRangerId?.trim();
    final effectiveRangerId = result.scope.effectiveRangerId?.trim();
    final resolvedRequestedRangerId =
        requestedRangerId == null || requestedRangerId.isEmpty
            ? null
            : requestedRangerId;
    final resolvedEffectiveRangerId =
        effectiveRangerId == null || effectiveRangerId.isEmpty
            ? null
            : effectiveRangerId;

    final scopedItems = _scopeSummaryItems(
      items: result.items,
      role: resolvedRole,
      effectiveRangerId: resolvedEffectiveRangerId,
    );

    _summaryRole = resolvedRole;
    _teamScope = resolvedRole == 'leader' ? result.scope.teamScope : false;
    _effectiveRangerId = resolvedEffectiveRangerId;
    _selectedRangerId =
      _summaryRole == 'leader' ? resolvedRequestedRangerId : null;

    _summaryPage = result.pagination.page;
    _summaryPageSize = result.pagination.pageSize;
    _summaryTotal = result.pagination.total;
    _summaryTotalPages = result.pagination.totalPages;

    _itemsByDay
      ..clear()
      ..addEntries(
        scopedItems.fold<Map<String, List<MobileWorkSummaryItem>>>(
          <String, List<MobileWorkSummaryItem>>{},
          (acc, item) {
            final dayKey = item.dayKey.trim();
            if (dayKey.isEmpty) {
              return acc;
            }
            acc.putIfAbsent(dayKey, () => <MobileWorkSummaryItem>[]).add(item);
            return acc;
          },
        ).entries,
      );

    final rangerIds = <String>{};
    if (resolvedRole == 'leader') {
      for (final item in result.items) {
        final rangerId = item.rangerId.trim();
        if (rangerId.isNotEmpty) {
          rangerIds.add(rangerId);
        }
      }
      if (resolvedRequestedRangerId != null &&
          resolvedRequestedRangerId.isNotEmpty) {
        rangerIds.addAll(_availableRangerIds);
        rangerIds.add(resolvedRequestedRangerId);
      }
    } else {
      for (final item in scopedItems) {
        final rangerId = item.rangerId.trim();
        if (rangerId.isNotEmpty) {
          rangerIds.add(rangerId);
        }
      }
    }

    _availableRangerIds = rangerIds.toList()..sort();
  }

  DateTime _normalizeMonth(DateTime value) => DateTime(value.year, value.month);

  List<MobileWorkSummaryItem> itemsForDay(DateTime day) {
    final key = _isoDay(day);
    return List.unmodifiable(_itemsByDay[key] ?? const <MobileWorkSummaryItem>[]);
  }

  int checkinCountForDay(DateTime day) {
    final items = itemsForDay(day);
    return items.where((item) => item.hasCheckin).length;
  }

  int totalCountForDay(DateTime day) => itemsForDay(day).length;

  bool hasSummaryForDay(DateTime day) => totalCountForDay(day) > 0;

  bool hasAnyCheckinForDay(DateTime day) => checkinCountForDay(day) > 0;

  void selectDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    if (normalized == _selectedDay) {
      return;
    }
    _selectedDay = normalized;
    notifyListeners();
  }

  Future<void> loadWorkSummaryForMonth({
    required AuthProvider authProvider,
    DateTime? month,
    String? rangerId,
  }) async {
    final requestId = ++_summaryRequestId;
    final targetMonth = _normalizeMonth(month ?? _focusedMonth);
    _focusedMonth = targetMonth;
    if (_selectedDay.year != targetMonth.year ||
        _selectedDay.month != targetMonth.month) {
      _selectedDay = DateTime(targetMonth.year, targetMonth.month, 1);
    }

    final authRole = _deriveRoleFromAuth(authProvider);
    _summaryRole = authRole;
    final sessionPartition = _sessionPartitionFromAuth(authProvider);
    final summarySessionKey = 'role=$authRole|session=$sessionPartition';
    final hadSessionScopedData =
      _itemsByDay.isNotEmpty ||
      _availableRangerIds.isNotEmpty ||
      _selectedRangerId != null ||
      _effectiveRangerId != null;

    if (_activeSummarySessionKey != summarySessionKey) {
      _activeSummarySessionKey = summarySessionKey;
      _activeSummaryCacheKey = null;

      _itemsByDay.clear();
      _summaryPage = 1;
      _summaryPageSize = 62;
      _summaryTotal = 0;
      _summaryTotalPages = 0;

      _teamScope = false;
      _selectedRangerId = null;
      _effectiveRangerId = null;
      _availableRangerIds = const [];

      _summaryLastSyncedAt = null;
      _isSummaryStale = false;
      _isSummaryOfflineFallback = false;
      _isUsingCachedSummary = false;
      _summaryError = null;
      _summaryRefreshError = null;

      if (hadSessionScopedData) {
        notifyListeners();
      }
    }

    final requestedRangerId = (rangerId ?? _selectedRangerId)?.trim();
    final leaderRequestedRangerId = authRole == 'leader'
        ? (requestedRangerId == null || requestedRangerId.isEmpty
            ? null
            : requestedRangerId)
        : null;

    final cacheKey = _cacheKeyForSummary(
      month: targetMonth,
      role: authRole,
      sessionPartition: sessionPartition,
      rangerId: leaderRequestedRangerId,
    );
    final cache = _cache;
    final hasActiveInMemoryData =
        _activeSummaryCacheKey == cacheKey && _itemsByDay.isNotEmpty;

    CachedReadModel<MobileWorkSummaryResult>? cachedSummary;
    if (cache != null) {
      try {
        cachedSummary = await cache.loadWorkSummary(cacheKey);
      } catch (_) {
        cachedSummary = null;
      }
      if (!_isCurrentSummaryRequest(requestId)) {
        return;
      }
      if (cachedSummary != null) {
        _applySummaryResult(cachedSummary.value, authRole: authRole);
        _activeSummaryCacheKey = cacheKey;
        _summaryLastSyncedAt = cachedSummary.syncedAt;
        _isSummaryStale = _computeSummaryStale(_summaryLastSyncedAt);
        _isSummaryOfflineFallback = false;
        _isUsingCachedSummary = true;
        _summaryError = null;
        _summaryRefreshError = null;
        notifyListeners();
      }
    }

    if (_mobileWorkSummaryApi == null) {
      if (!_isCurrentSummaryRequest(requestId)) {
        return;
      }
      _isLoadingSummary = false;
      if (cachedSummary != null || hasActiveInMemoryData) {
        _summaryError = null;
        _summaryRefreshError = 'Work summary API unavailable';
        _isSummaryStale = true;
        _isSummaryOfflineFallback = true;
        _isUsingCachedSummary = true;
      } else {
        _summaryError = 'Work summary API unavailable';
        _summaryRefreshError = null;
        _itemsByDay.clear();
        _availableRangerIds = const [];
        _summaryPage = 1;
        _summaryPageSize = 62;
        _summaryTotal = 0;
        _summaryTotalPages = 0;
        _teamScope = false;
        _selectedRangerId = null;
        _effectiveRangerId = null;
        _summaryLastSyncedAt = null;
        _isSummaryStale = false;
        _isSummaryOfflineFallback = false;
        _isUsingCachedSummary = false;
        _activeSummaryCacheKey = null;
      }
      notifyListeners();
      return;
    }

    final accessToken = authProvider.mobileAccessToken?.trim();
    if (accessToken == null || accessToken.isEmpty) {
      if (!_isCurrentSummaryRequest(requestId)) {
        return;
      }
      _isLoadingSummary = false;
      if (cachedSummary != null || hasActiveInMemoryData) {
        _summaryError = null;
        _summaryRefreshError = 'Missing mobile access token';
        _isSummaryStale = true;
        _isSummaryOfflineFallback = true;
        _isUsingCachedSummary = true;
      } else {
        _summaryError = 'Missing mobile access token';
        _summaryRefreshError = null;
        _itemsByDay.clear();
        _availableRangerIds = const [];
        _summaryPage = 1;
        _summaryPageSize = 62;
        _summaryTotal = 0;
        _summaryTotalPages = 0;
        _teamScope = false;
        _selectedRangerId = null;
        _effectiveRangerId = null;
        _summaryLastSyncedAt = null;
        _isSummaryStale = false;
        _isSummaryOfflineFallback = false;
        _isUsingCachedSummary = false;
        _activeSummaryCacheKey = null;
      }
      notifyListeners();
      return;
    }

    if (!_isCurrentSummaryRequest(requestId)) {
      return;
    }

    _isLoadingSummary = true;
    if (cachedSummary == null) {
      _summaryError = null;
    }
    _summaryRefreshError = null;
    notifyListeners();

    final fromDay = DateTime(targetMonth.year, targetMonth.month, 1);
    final toDay = DateTime(targetMonth.year, targetMonth.month + 1, 0);

    try {
      final firstPageResult = await _fetchWorkSummaryWithTokenRetry(
        authProvider: authProvider,
        fromDay: fromDay,
        toDay: toDay,
        rangerId: leaderRequestedRangerId,
        page: 1,
        pageSize: 366,
      );

      if (!_isCurrentSummaryRequest(requestId)) {
        return;
      }

      var allNetworkItems = List<MobileWorkSummaryItem>.from(
        firstPageResult.items,
        growable: false,
      );

      for (var page = 2; page <= firstPageResult.pagination.totalPages; page++) {
        final nextPageResult = await _fetchWorkSummaryWithTokenRetry(
          authProvider: authProvider,
          fromDay: fromDay,
          toDay: toDay,
          rangerId: leaderRequestedRangerId,
          page: page,
          pageSize: 366,
        );

        if (!_isCurrentSummaryRequest(requestId)) {
          return;
        }

        allNetworkItems = _mergeSummaryItems(
          base: allNetworkItems,
          incoming: nextPageResult.items,
        );
      }

      final authoritativeItems = _mergeSummaryItems(
        base: const <MobileWorkSummaryItem>[],
        incoming: allNetworkItems,
      );

      final mergedResult = MobileWorkSummaryResult(
        items: authoritativeItems,
        scope: firstPageResult.scope,
        pagination: firstPageResult.pagination,
        fromDay: firstPageResult.fromDay ?? cachedSummary?.value.fromDay,
        toDay: firstPageResult.toDay ?? cachedSummary?.value.toDay,
      );

      _applySummaryResult(mergedResult, authRole: authRole);
      _activeSummaryCacheKey = cacheKey;

      final syncedAt = DateTime.now().toUtc();
      _summaryLastSyncedAt = syncedAt;
      _isSummaryStale = false;
      _isSummaryOfflineFallback = false;
      _isUsingCachedSummary = false;
      _summaryError = null;
      _summaryRefreshError = null;

      if (cache != null) {
        try {
          await cache.saveWorkSummary(
            cacheKey: cacheKey,
            value: mergedResult,
            syncedAt: syncedAt,
          );
          if (!_isCurrentSummaryRequest(requestId)) {
            return;
          }
        } catch (_) {
          if (!_isCurrentSummaryRequest(requestId)) {
            return;
          }
          _summaryRefreshError =
              'Work Management data loaded, but local cache update failed.';
          _isSummaryStale = true;
        }
        if (!_isCurrentSummaryRequest(requestId)) {
          return;
        }
      }
    } catch (e) {
      if (!_isCurrentSummaryRequest(requestId)) {
        return;
      }
      if (cachedSummary != null || hasActiveInMemoryData) {
        _summaryError = null;
        _summaryRefreshError = _summaryRefreshErrorMessage(e);
        _isSummaryStale = true;
        _isSummaryOfflineFallback = true;
        _isUsingCachedSummary = true;
      } else {
        _summaryError = _summaryLoadErrorMessage(e);
        _summaryRefreshError = null;
        _itemsByDay.clear();
        _availableRangerIds = const [];
        _summaryPage = 1;
        _summaryPageSize = 62;
        _summaryTotal = 0;
        _summaryTotalPages = 0;
        _teamScope = false;
        _selectedRangerId = null;
        _effectiveRangerId = null;
        _summaryLastSyncedAt = null;
        _isSummaryStale = false;
        _isSummaryOfflineFallback = false;
        _isUsingCachedSummary = false;
        _activeSummaryCacheKey = null;
      }
    } finally {
      if (_isCurrentSummaryRequest(requestId)) {
        _isLoadingSummary = false;
        notifyListeners();
      }
    }
  }

  Future<void> goToPreviousMonth({required AuthProvider authProvider}) async {
    final previousMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    await loadWorkSummaryForMonth(
      authProvider: authProvider,
      month: previousMonth,
      rangerId: _selectedRangerId,
    );
  }

  Future<void> goToNextMonth({required AuthProvider authProvider}) async {
    final nextMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    await loadWorkSummaryForMonth(
      authProvider: authProvider,
      month: nextMonth,
      rangerId: _selectedRangerId,
    );
  }

  Future<void> selectRangerFilter({
    required AuthProvider authProvider,
    String? rangerId,
  }) async {
    if (!isLeaderScope) {
      return;
    }

    final normalized = rangerId?.trim();
    if (normalized != null &&
        normalized.isNotEmpty &&
        !_availableRangerIds.contains(normalized)) {
      _summaryRefreshError = 'Unknown ranger filter';
      notifyListeners();
      return;
    }

    final nextSelectedRangerId =
        (normalized == null || normalized.isEmpty) ? null : normalized;
    if (nextSelectedRangerId == _selectedRangerId) {
      _summaryRefreshError = null;
      notifyListeners();
      return;
    }

    _summaryRefreshError = null;
    _selectedRangerId = nextSelectedRangerId;
    await loadWorkSummaryForMonth(
      authProvider: authProvider,
      month: _focusedMonth,
      rangerId: _selectedRangerId,
    );
  }

  Future<void> retryLoadSummary({required AuthProvider authProvider}) async {
    await loadWorkSummaryForMonth(
      authProvider: authProvider,
      month: _focusedMonth,
      rangerId: _selectedRangerId,
    );
  }

  Future<void> refreshCheckinSyncStatus({
    required AuthProvider authProvider,
  }) async {
    if (!authProvider.isRangerSession) {
      await _refreshCheckinQueueSummary();
      notifyListeners();
      return;
    }

    final queueUserId = _resolveCheckinUserId(authProvider);
    await _refreshCheckinQueueSummaryForUser(queueUserId);
    notifyListeners();
  }

  Future<bool> retryFailedCheckins({
    required AuthProvider authProvider,
    String? queueId,
  }) async {
    if (_checkinQueue == null || _isReplayingCheckins || _isSyncingCheckin) {
      return false;
    }

    final accessToken = authProvider.mobileAccessToken?.trim();
    final queueUserId = _resolveCheckinUserId(authProvider);
    if (!authProvider.isRangerSession ||
        accessToken == null ||
        accessToken.isEmpty ||
        queueUserId == null ||
        queueUserId.isEmpty) {
      _checkinError = 'Session expired. Please sign in again.';
      await _refreshCheckinQueueSummary();
      notifyListeners();
      return false;
    }

    final normalizedQueueId = queueId?.trim();
    final allItems = await _checkinQueue.listItems(userId: queueUserId);
    final failedItems = allItems
        .where(
          (item) =>
              item.isFailed &&
              (normalizedQueueId == null ||
                  normalizedQueueId.isEmpty ||
                  item.queueId == normalizedQueueId),
        )
        .toList(growable: false);

    if (failedItems.isEmpty) {
      await _refreshCheckinQueueSummaryForUser(queueUserId);
      notifyListeners();
      return false;
    }

    for (final failedItem in failedItems) {
      await _checkinQueue.prepareFailedForManualRetry(
        failedItem.queueId,
        resetAttemptCount: true,
        userId: queueUserId,
      );
    }

    await _refreshCheckinQueueSummaryForUser(queueUserId);
    notifyListeners();

    return replayQueuedCheckins(
      authProvider: authProvider,
      queueIds: failedItems.map((item) => item.queueId).toSet(),
    );
  }

  Future<void> triggerAppOpenCheckin({
    required AuthProvider authProvider,
  }) async {
    if (_isSyncingCheckin || _isReplayingCheckins) {
      return;
    }

    if (!authProvider.isRangerSession) {
      _resetCheckinState();
      await _refreshCheckinQueueSummary();
      notifyListeners();
      return;
    }

    final accessToken = authProvider.mobileAccessToken?.trim();
    if (accessToken == null || accessToken.isEmpty) {
      _resetCheckinState();
      await _refreshCheckinQueueSummary();
      notifyListeners();
      return;
    }

    _isSyncingCheckin = true;
    _checkinError = null;
    notifyListeners();

    final nowUtc = DateTime.now().toUtc();
    final projectDayKey = MobileCheckinReplayQueue.projectDayKeyFromUtc(nowUtc);
    final userId = _resolveCheckinUserId(authProvider);
    String? requestClientUuid;
    String? requestIdempotencyKey;

    try {
      final replaySucceeded = await replayQueuedCheckins(
        authProvider: authProvider,
      );
      if (!replaySucceeded) {
        return;
      }

      if (userId == null || userId.isEmpty) {
        _lastCheckinDayKey = null;
        _lastCheckinStatus = null;
        _lastCheckinServerTime = null;
        _checkinError = 'Unable to resolve check-in identity.';
        await _refreshCheckinQueueSummaryForUser(userId);
        return;
      }

      if (_checkinQueue != null) {
        final existingItems = await _checkinQueue.listItems(userId: userId);
        final hasPendingForDay = existingItems.any(
          (item) => item.isPending && item.dayKey == projectDayKey,
        );

        if (hasPendingForDay) {
          _lastCheckinDayKey = projectDayKey;
          _lastCheckinStatus = MobileCheckinQueueStatus.pending;
          _lastCheckinServerTime = nowUtc.toIso8601String();
          _checkinError = null;
          await _refreshCheckinQueueSummaryForUser(userId);
          return;
        }
      }

      requestClientUuid = _generateCheckinClientUuid();
      requestIdempotencyKey = MobileCheckinReplayQueue.composeIdempotencyKey(
        userId: userId,
        actionType: MobileCheckinReplayQueue.checkinActionType,
        dayKey: projectDayKey,
        clientUuid: requestClientUuid,
      );

      final gpsPosition = await _tryGetCurrentPosition();

      final result = await _submitCheckinWithTokenRetry(
        authProvider: authProvider,
        idempotencyKey: requestIdempotencyKey,
        clientTime: nowUtc.toIso8601String(),
        timezone: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
        latitude: gpsPosition?.latitude,
        longitude: gpsPosition?.longitude,
      );

      final responseIdempotencyKey = result.idempotencyKey.trim();
      if (responseIdempotencyKey.isNotEmpty &&
          responseIdempotencyKey != requestIdempotencyKey) {
        throw StateError(
          'Unexpected check-in idempotency key: ${result.idempotencyKey}',
        );
      }

      if (result.status != 'created' && result.status != 'already_exists') {
        throw StateError('Unexpected check-in status: ${result.status}');
      }

      final responseDayKey = result.dayKey.trim();
      if (responseDayKey.isNotEmpty && responseDayKey != projectDayKey) {
        throw StateError(
          'Unexpected check-in day key: expected $projectDayKey, got ${result.dayKey}',
        );
      }

      _lastCheckinDayKey = responseDayKey.isEmpty
          ? projectDayKey
          : responseDayKey;
      _lastCheckinStatus = result.status;
      _lastCheckinServerTime = result.serverTime;
      _checkinError = null;

      if (_checkinQueue != null) {
        final remainingPendingItems = await _checkinQueue.listItems(userId: userId);
        for (final pendingItem in remainingPendingItems) {
          if (!pendingItem.isPending || pendingItem.dayKey != projectDayKey) {
            continue;
          }

          if (pendingItem.idempotencyKey == requestIdempotencyKey) {
            continue;
          }

          await _checkinQueue.markSynced(pendingItem.queueId, userId: userId);
        }
      }

      await _refreshCheckinQueueSummaryForUser(userId);
    } catch (e) {
      final canQueue = _checkinQueue != null &&
          userId != null &&
          userId.isNotEmpty &&
          requestClientUuid != null &&
          requestClientUuid.isNotEmpty &&
          requestIdempotencyKey != null &&
          requestIdempotencyKey.isNotEmpty &&
          _isQueueableCheckinFailure(e);

      if (canQueue) {
        final queuedItem = await _checkinQueue.enqueueCheckin(
          userId: userId,
          dayKey: projectDayKey,
          timezoneName: 'Asia/Ho_Chi_Minh',
          appVersion: '1.0.0',
          clientTimeUtc: nowUtc,
          clientUuid: requestClientUuid,
          idempotencyKey: requestIdempotencyKey,
        );

        _lastCheckinDayKey = queuedItem.dayKey;
        _lastCheckinStatus = MobileCheckinQueueStatus.pending;
        _lastCheckinServerTime = nowUtc.toIso8601String();
        _checkinError = null;
        await _refreshCheckinQueueSummaryForUser(userId);
      } else {
        _lastCheckinDayKey = null;
        _lastCheckinStatus = null;
        _lastCheckinServerTime = null;
        _checkinError = _checkinErrorMessage(e);
        await _refreshCheckinQueueSummaryForUser(userId);
      }
    } finally {
      _isSyncingCheckin = false;
      notifyListeners();
    }
  }
}
