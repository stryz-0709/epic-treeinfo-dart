import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../services/mobile_api_service.dart';
import '../services/mobile_read_model_cache.dart';
import 'auth_provider.dart';

class ScheduleProvider extends ChangeNotifier {
  final MobileScheduleApi _scheduleApi;
  final MobileReadModelCache? _cache;
  final Duration staleAfter;

  ScheduleProvider({
    required MobileScheduleApi scheduleApi,
    MobileReadModelCache? cache,
    this.staleAfter = const Duration(minutes: 30),
  })  : _scheduleApi = scheduleApi,
        _cache = cache;

  List<MobileScheduleItem> _schedules = const [];
  bool _isLoading = false;
  String? _loadError;
  String? _refreshError;
  DateTime? _lastSyncedAt;
  bool _isStaleData = false;
  bool _isOfflineFallback = false;
  bool _isUsingCachedData = false;

  bool _isSubmitting = false;
  String? _submitError;

  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  String _scopeRole = 'ranger';
  String _accountRole = 'ranger';
  bool _teamScope = false;
  String? _requestedRangerId;
  String? _effectiveRangerId;
  String? _selectedRangerId;
  List<String> _availableRangerIds = const [];
  List<MobileScheduleDirectoryUser> _scheduleDirectory = const [];
  Map<String, String> _displayNameByRangerId = const {};
  String? _activeCacheKey;
  String? _activeSessionKey;
  int _loadRequestId = 0;

  List<MobileScheduleItem> get schedules => List.unmodifiable(_schedules);
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  String? get refreshError => _refreshError;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isStaleData => _isStaleData;
  bool get isOfflineFallback => _isOfflineFallback;
  bool get isUsingCachedData => _isUsingCachedData;
  bool get isSubmitting => _isSubmitting;
  String? get submitError => _submitError;
  DateTime get focusedMonth => _focusedMonth;
  String get scopeRole => _scopeRole;
  String get accountRole => _accountRole;
  bool get isLeaderScope => _scopeRole == 'leader';
  bool get isAdminScope => _accountRole == 'admin';
  bool get isReadOnly => !isLeaderScope;
  bool get canDeleteSchedules => isLeaderScope && isAdminScope;
  bool get teamScope => _teamScope;
  String? get requestedRangerId => _requestedRangerId;
  String? get effectiveRangerId => _effectiveRangerId;
  String? get selectedRangerId => _selectedRangerId;
  List<String> get availableRangerIds => List.unmodifiable(_availableRangerIds);
  List<MobileScheduleDirectoryUser> get scheduleDirectory =>
      List.unmodifiable(_scheduleDirectory);
  bool get canViewLeaderAssignments =>
      _scheduleDirectory.any((entry) => entry.role == 'leader');

  bool get hasSchedules => _schedules.isNotEmpty;
  bool get isEmptyState => !_isLoading && _loadError == null && !hasSchedules;

  String rangerDisplayName(String rangerId) {
    final normalized = rangerId.trim();
    if (normalized.isEmpty) {
      return normalized;
    }

    final displayName = (_displayNameByRangerId[normalized] ?? '').trim();
    if (displayName.isEmpty) {
      return normalized;
    }

    return displayName;
  }

  bool _isCurrentLoadRequest(int requestId) {
    return requestId == _loadRequestId;
  }

  String _userSafeMessageForApiError(
    Object error, {
    required String fallback,
  }) {
    if (error is MobileApiException) {
      if (error.statusCode == 400) {
        return 'Invalid schedule request';
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Not authorized for this schedule operation';
      }
      if (error.statusCode == 404) {
        return 'Schedule not found';
      }
      if (error.statusCode >= 500) {
        return 'Schedule service is temporarily unavailable';
      }
    }

    return fallback;
  }

  Future<MobileScheduleListResult> _fetchSchedulesWithTokenRetry({
    required AuthProvider authProvider,
    required DateTime fromDay,
    required DateTime toDay,
    String? rangerId,
  }) async {
    final initialToken = authProvider.mobileAccessToken?.trim() ?? '';
    if (initialToken.isEmpty) {
      throw StateError('Missing mobile access token');
    }

    try {
      return await _scheduleApi.fetchSchedules(
        accessToken: initialToken,
        fromDay: fromDay,
        toDay: toDay,
        rangerId: rangerId,
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

      return _scheduleApi.fetchSchedules(
        accessToken: latestToken,
        fromDay: fromDay,
        toDay: toDay,
        rangerId: rangerId,
      );
    }
  }

  Future<void> _submitScheduleWriteWithTokenRetry({
    required AuthProvider authProvider,
    required Future<void> Function(String accessToken) submit,
  }) async {
    final initialToken = authProvider.mobileAccessToken?.trim() ?? '';
    if (initialToken.isEmpty) {
      throw StateError('Missing mobile access token');
    }

    try {
      await submit(initialToken);
      return;
    } on MobileApiException catch (error) {
      final latestToken = authProvider.mobileAccessToken?.trim() ?? '';
      final shouldRetry =
          (error.statusCode == 401 || error.statusCode == 403) &&
          latestToken.isNotEmpty &&
          latestToken != initialToken;

      if (!shouldRetry) {
        rethrow;
      }

      await submit(latestToken);
    }
  }

  Future<void> _submitScheduleDeleteWithTokenRetry({
    required AuthProvider authProvider,
    required String scheduleId,
  }) async {
    final initialToken = authProvider.mobileAccessToken?.trim() ?? '';
    if (initialToken.isEmpty) {
      throw StateError('Missing mobile access token');
    }

    try {
      await _scheduleApi.deleteSchedule(
        accessToken: initialToken,
        scheduleId: scheduleId,
      );
      return;
    } on MobileApiException catch (error) {
      final latestToken = authProvider.mobileAccessToken?.trim() ?? '';
      final shouldRetry =
          (error.statusCode == 401 || error.statusCode == 403) &&
          latestToken.isNotEmpty &&
          latestToken != initialToken;

      if (!shouldRetry) {
        rethrow;
      }

      await _scheduleApi.deleteSchedule(
        accessToken: latestToken,
        scheduleId: scheduleId,
      );
    }
  }

  String _deriveRoleFromAuth(AuthProvider authProvider) {
    if (authProvider.mobileRole == 'leader') {
      return 'leader';
    }
    return 'ranger';
  }

  String _deriveAccountRoleFromScope({
    required String fallbackRole,
    String? accountRole,
  }) {
    final normalized = (accountRole ?? '').trim().toLowerCase();
    if (normalized == 'admin' || normalized == 'leader' || normalized == 'ranger') {
      return normalized;
    }
    return fallbackRole == 'leader' ? 'leader' : 'ranger';
  }

  DateTime _normalizeMonth(DateTime value) => DateTime(value.year, value.month);

  DateTime? _parseIsoDay(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _monthKey(DateTime month) {
    final yyyy = month.year.toString().padLeft(4, '0');
    final mm = month.month.toString().padLeft(2, '0');
    return '$yyyy-$mm';
  }

  String _cacheKeyForSchedules({
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

  String _normalizeIdentityToken(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return '';
    }

    return normalized.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  bool _computeStale(DateTime? syncedAt) {
    if (!hasSchedules) {
      return false;
    }
    if (syncedAt == null) {
      return true;
    }
    return DateTime.now().toUtc().difference(syncedAt) > staleAfter;
  }

  List<MobileScheduleItem> _scopeSchedules({
    required List<MobileScheduleItem> items,
    required String role,
    required String? effectiveRangerId,
  }) {
    if (role != 'ranger') {
      return List<MobileScheduleItem>.from(items, growable: false);
    }

    final effective = effectiveRangerId?.trim();
    if (effective == null || effective.isEmpty) {
      return const <MobileScheduleItem>[];
    }

    return items
        .where((item) => item.rangerId.trim() == effective)
        .toList(growable: false);
  }

  String _scheduleIdentity(MobileScheduleItem item) {
    final scheduleId = item.scheduleId.trim();
    if (scheduleId.isNotEmpty) {
      return 'schedule:${scheduleId.toLowerCase()}';
    }

    final rangerId = _normalizeIdentityToken(item.rangerId);
    final workDate = _normalizeIdentityToken(item.workDate);

    final createdAt = _normalizeIdentityToken(item.createdAt);
    if (createdAt.isNotEmpty) {
      return 'fallback:$rangerId::$workDate::$createdAt';
    }

    final updatedAt = _normalizeIdentityToken(item.updatedAt);
    if (updatedAt.isNotEmpty) {
      return 'fallback:$rangerId::$workDate::$updatedAt';
    }

    final note = _normalizeIdentityToken(item.note);
    return 'fallback:$rangerId::$workDate::$note';
  }

  List<MobileScheduleItem> _mergeSchedules({
    required List<MobileScheduleItem> base,
    required List<MobileScheduleItem> incoming,
  }) {
    final mergedByKey = <String, MobileScheduleItem>{};
    for (final item in base) {
      mergedByKey[_scheduleIdentity(item)] = item;
    }
    for (final item in incoming) {
      mergedByKey[_scheduleIdentity(item)] = item;
    }

    final merged = mergedByKey.values.toList(growable: false)
      ..sort((a, b) {
        final dayCompare = a.workDate.compareTo(b.workDate);
        if (dayCompare != 0) {
          return dayCompare;
        }
        final rangerCompare = a.rangerId.compareTo(b.rangerId);
        if (rangerCompare != 0) {
          return rangerCompare;
        }

        final scheduleIdCompare = a.scheduleId.compareTo(b.scheduleId);
        if (scheduleIdCompare != 0) {
          return scheduleIdCompare;
        }

        return _scheduleIdentity(a).compareTo(_scheduleIdentity(b));
      });

    return merged;
  }

  void _applyScheduleResult(
    MobileScheduleListResult result, {
    required String fallbackRole,
  }) {
    final resolvedRole = fallbackRole == 'leader' ? 'leader' : 'ranger';
    final resolvedAccountRole = _deriveAccountRoleFromScope(
      fallbackRole: resolvedRole,
      accountRole: result.scope.accountRole,
    );
    final resolvedRequestedRangerId =
        resolvedRole == 'leader' ? result.scope.requestedRangerId : null;
    final resolvedEffectiveRangerId = result.scope.effectiveRangerId;
    final scopedSchedules = _scopeSchedules(
      items: result.items,
      role: resolvedRole,
      effectiveRangerId: resolvedEffectiveRangerId,
    );

    _scopeRole = resolvedRole;
  _accountRole = resolvedAccountRole;
    _teamScope = resolvedRole == 'leader' ? result.scope.teamScope : false;
    _requestedRangerId = resolvedRequestedRangerId;
    _effectiveRangerId = resolvedEffectiveRangerId;
    _selectedRangerId = resolvedRequestedRangerId;

    _schedules = scopedSchedules.toList(growable: false)
      ..sort((a, b) {
        final dayCompare = a.workDate.compareTo(b.workDate);
        if (dayCompare != 0) {
          return dayCompare;
        }
        final rangerCompare = a.rangerId.compareTo(b.rangerId);
        if (rangerCompare != 0) {
          return rangerCompare;
        }
        return a.scheduleId.compareTo(b.scheduleId);
      });

    final directoryByRangerId = <String, MobileScheduleDirectoryUser>{
      for (final entry in result.directory)
        if (entry.username.trim().isNotEmpty)
          entry.username.trim(): MobileScheduleDirectoryUser(
            username: entry.username.trim(),
            displayName: entry.displayName.trim().isEmpty
                ? entry.username.trim()
                : entry.displayName.trim(),
            role: entry.role.trim().toLowerCase(),
          ),
    };

    final rangerIds = <String>{
      if (_scopeRole == 'leader') ..._availableRangerIds,
      ...directoryByRangerId.keys,
      for (final item in (_scopeRole == 'leader' ? result.items : _schedules))
        if (item.rangerId.trim().isNotEmpty) item.rangerId.trim(),
    };
    final requestedRangerId = _requestedRangerId?.trim();
    if (requestedRangerId != null && requestedRangerId.isNotEmpty) {
      rangerIds.add(requestedRangerId);
    }

    for (final rangerId in rangerIds) {
      if (!directoryByRangerId.containsKey(rangerId)) {
        directoryByRangerId[rangerId] = MobileScheduleDirectoryUser(
          username: rangerId,
          displayName: rangerId,
          role: 'ranger',
        );
      }
    }

    final sortedIds = rangerIds.toList()
      ..sort((a, b) {
        final displayA =
            (directoryByRangerId[a]?.displayName ?? a).trim().toLowerCase();
        final displayB =
            (directoryByRangerId[b]?.displayName ?? b).trim().toLowerCase();
        final displayCompare = displayA.compareTo(displayB);
        if (displayCompare != 0) {
          return displayCompare;
        }
        return a.compareTo(b);
      });

    _availableRangerIds = sortedIds;
    _scheduleDirectory = sortedIds
        .map((rangerId) => directoryByRangerId[rangerId]!)
        .toList(growable: false);
    _displayNameByRangerId = {
      for (final entry in _scheduleDirectory)
        entry.username: entry.displayName,
    };
  }

  Future<void> loadSchedules({
    required AuthProvider authProvider,
    DateTime? month,
    String? rangerId,
  }) async {
    final requestId = ++_loadRequestId;
    final targetMonth = _normalizeMonth(month ?? _focusedMonth);
    _focusedMonth = targetMonth;

    final roleFromAuth = _deriveRoleFromAuth(authProvider);
    final sessionPartition = _sessionPartitionFromAuth(authProvider);
    final scheduleSessionKey = 'role=$roleFromAuth|session=$sessionPartition';
    final hadSessionScopedData =
        _schedules.isNotEmpty ||
        _availableRangerIds.isNotEmpty ||
        _selectedRangerId != null ||
        _effectiveRangerId != null;

    if (_activeSessionKey != scheduleSessionKey) {
      _activeSessionKey = scheduleSessionKey;
      _activeCacheKey = null;

      _schedules = const <MobileScheduleItem>[];
      _scopeRole = roleFromAuth;
      _accountRole = roleFromAuth == 'leader' ? 'leader' : 'ranger';
      _teamScope = false;
      _requestedRangerId = null;
      _effectiveRangerId = null;
      _selectedRangerId = null;
      _availableRangerIds = const [];
      _scheduleDirectory = const [];
      _displayNameByRangerId = const {};

      _lastSyncedAt = null;
      _isStaleData = false;
      _isOfflineFallback = false;
      _isUsingCachedData = false;
      _loadError = null;
      _refreshError = null;

      if (hadSessionScopedData) {
        notifyListeners();
      }
    }

    final requestedRanger = (rangerId ?? _selectedRangerId)?.trim();
    final leaderRequestedRangerId = roleFromAuth == 'leader'
        ? (requestedRanger == null || requestedRanger.isEmpty ? null : requestedRanger)
        : null;

    final cacheKey = _cacheKeyForSchedules(
      month: targetMonth,
      role: roleFromAuth,
      sessionPartition: sessionPartition,
      rangerId: leaderRequestedRangerId,
    );
    final cache = _cache;
    final hasActiveInMemoryData = _activeCacheKey == cacheKey && _schedules.isNotEmpty;

    CachedReadModel<MobileScheduleListResult>? cachedSchedules;
    if (cache != null) {
      cachedSchedules = await cache.loadSchedules(cacheKey);
      if (!_isCurrentLoadRequest(requestId)) {
        return;
      }

      if (cachedSchedules != null) {
        _applyScheduleResult(cachedSchedules.value, fallbackRole: roleFromAuth);
        _activeCacheKey = cacheKey;
        _lastSyncedAt = cachedSchedules.syncedAt;
        _isStaleData = _computeStale(_lastSyncedAt);
        _isOfflineFallback = false;
        _isUsingCachedData = true;
        _loadError = null;
        _refreshError = null;
        notifyListeners();
      }
    }

    if (!authProvider.hasMobileAccessToken) {
      if (!_isCurrentLoadRequest(requestId)) {
        return;
      }

      if (cachedSchedules != null || hasActiveInMemoryData) {
        _loadError = null;
        _refreshError = 'Missing mobile access token';
        _isStaleData = true;
        _isOfflineFallback = true;
        _isUsingCachedData = true;
      } else {
        _loadError = 'Missing mobile access token';
        _refreshError = null;
        _schedules = const [];
        _availableRangerIds = const [];
        _scopeRole = roleFromAuth;
        _accountRole = roleFromAuth == 'leader' ? 'leader' : 'ranger';
        _teamScope = false;
        _requestedRangerId = null;
        _effectiveRangerId = null;
        _selectedRangerId = null;
        _lastSyncedAt = null;
        _isStaleData = false;
        _isOfflineFallback = false;
        _isUsingCachedData = false;
        _activeCacheKey = null;
        _scheduleDirectory = const [];
        _displayNameByRangerId = const {};
      }
      _isLoading = false;
      notifyListeners();
      return;
    }

    if (!_isCurrentLoadRequest(requestId)) {
      return;
    }

    _isLoading = true;
    if (cachedSchedules == null) {
      _loadError = null;
    }
    _refreshError = null;
    notifyListeners();

    final fromDay = DateTime(targetMonth.year, targetMonth.month, 1);
    final toDay = DateTime(targetMonth.year, targetMonth.month + 1, 0);

    try {
      final result = await _fetchSchedulesWithTokenRetry(
        authProvider: authProvider,
        fromDay: fromDay,
        toDay: toDay,
        rangerId: leaderRequestedRangerId,
      );

      if (!_isCurrentLoadRequest(requestId)) {
        return;
      }

      final mergedItems = _mergeSchedules(
        base: const <MobileScheduleItem>[],
        incoming: result.items,
      );

      final mergedResult = MobileScheduleListResult(
        items: mergedItems,
        scope: result.scope,
        fromDay: result.fromDay ?? cachedSchedules?.value.fromDay,
        toDay: result.toDay ?? cachedSchedules?.value.toDay,
        directory: result.directory.isNotEmpty
            ? result.directory
            : (cachedSchedules?.value.directory ??
                const <MobileScheduleDirectoryUser>[]),
      );

      _applyScheduleResult(mergedResult, fallbackRole: roleFromAuth);
      _activeCacheKey = cacheKey;

      final syncedAt = DateTime.now().toUtc();
      _lastSyncedAt = syncedAt;
      _isStaleData = false;
      _isOfflineFallback = false;
      _isUsingCachedData = false;

      _loadError = null;
      _refreshError = null;

      if (cache != null) {
        await cache.saveSchedules(
          cacheKey: cacheKey,
          value: mergedResult,
          syncedAt: syncedAt,
        );

        if (!_isCurrentLoadRequest(requestId)) {
          return;
        }
      }
    } catch (e) {
      if (!_isCurrentLoadRequest(requestId)) {
        return;
      }

      if (cachedSchedules != null || hasActiveInMemoryData) {
        _loadError = null;
        _refreshError = _userSafeMessageForApiError(
          e,
          fallback: 'Unable to refresh schedules',
        );
        _isStaleData = true;
        _isOfflineFallback = true;
        _isUsingCachedData = true;
      } else {
        _loadError = _userSafeMessageForApiError(
          e,
          fallback: 'Unable to load schedules',
        );
        _refreshError = null;
        _schedules = const [];
        _availableRangerIds = const [];
        _scopeRole = roleFromAuth;
        _accountRole = roleFromAuth == 'leader' ? 'leader' : 'ranger';
        _teamScope = false;
        _requestedRangerId = null;
        _effectiveRangerId = null;
        _selectedRangerId = null;
        _lastSyncedAt = null;
        _isStaleData = false;
        _isOfflineFallback = false;
        _isUsingCachedData = false;
        _activeCacheKey = null;
        _scheduleDirectory = const [];
        _displayNameByRangerId = const {};
      }
    } finally {
      if (_isCurrentLoadRequest(requestId)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> goToPreviousMonth({required AuthProvider authProvider}) async {
    if (_isLoading) {
      return;
    }

    final previousMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    await loadSchedules(
      authProvider: authProvider,
      month: previousMonth,
      rangerId: _selectedRangerId,
    );
  }

  Future<void> goToNextMonth({required AuthProvider authProvider}) async {
    if (_isLoading) {
      return;
    }

    final nextMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    await loadSchedules(
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
        _availableRangerIds.isNotEmpty &&
        !_availableRangerIds.contains(normalized)) {
      _refreshError = 'Unknown ranger filter';
      notifyListeners();
      return;
    }

    _refreshError = null;
    _selectedRangerId = (normalized == null || normalized.isEmpty) ? null : normalized;

    await loadSchedules(
      authProvider: authProvider,
      month: _focusedMonth,
      rangerId: _selectedRangerId,
    );
  }

  Future<void> retryLoad({required AuthProvider authProvider}) async {
    if (_isLoading) {
      return;
    }

    await loadSchedules(
      authProvider: authProvider,
      month: _focusedMonth,
      rangerId: _selectedRangerId,
    );
  }

  Future<bool> createSchedule({
    required AuthProvider authProvider,
    required String rangerId,
    required DateTime? workDate,
    String note = '',
  }) async {
    return _submitScheduleWrite(
      authProvider: authProvider,
      rangerId: rangerId,
      workDate: workDate,
      note: note,
    );
  }

  Future<bool> updateSchedule({
    required AuthProvider authProvider,
    required String scheduleId,
    required String rangerId,
    required DateTime? workDate,
    String note = '',
  }) async {
    return _submitScheduleWrite(
      authProvider: authProvider,
      rangerId: rangerId,
      workDate: workDate,
      note: note,
      scheduleId: scheduleId,
    );
  }

  Future<bool> deleteSchedule({
    required AuthProvider authProvider,
    required String scheduleId,
  }) async {
    final role = _deriveRoleFromAuth(authProvider);
    if (role != 'leader') {
      _submitError = 'Leader role required';
      notifyListeners();
      return false;
    }

    if (_accountRole != 'admin') {
      _submitError = 'Admin role required';
      notifyListeners();
      return false;
    }

    if (!authProvider.hasMobileAccessToken) {
      _submitError = 'Missing mobile access token';
      notifyListeners();
      return false;
    }

    final normalizedScheduleId = scheduleId.trim();
    if (normalizedScheduleId.isEmpty) {
      _submitError = 'Schedule not found';
      notifyListeners();
      return false;
    }

    if (_isSubmitting) {
      _submitError = 'Schedule submission in progress';
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    _submitError = null;
    notifyListeners();

    try {
      await _submitScheduleDeleteWithTokenRetry(
        authProvider: authProvider,
        scheduleId: normalizedScheduleId,
      );

      _submitError = null;
      await loadSchedules(
        authProvider: authProvider,
        month: _focusedMonth,
        rangerId: _selectedRangerId,
      );
      return true;
    } catch (e) {
      _submitError = _userSafeMessageForApiError(
        e,
        fallback: 'Unable to delete schedule',
      );
      notifyListeners();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> _submitScheduleWrite({
    required AuthProvider authProvider,
    required String rangerId,
    required DateTime? workDate,
    required String note,
    String? scheduleId,
  }) async {
    final role = _deriveRoleFromAuth(authProvider);
    if (role != 'leader') {
      _submitError = 'Leader role required';
      notifyListeners();
      return false;
    }

    if (!authProvider.hasMobileAccessToken) {
      _submitError = 'Missing mobile access token';
      notifyListeners();
      return false;
    }

    final normalizedRangerId = rangerId.trim();
    if (normalizedRangerId.isEmpty || workDate == null) {
      _submitError = 'ranger_id and work_date required';
      notifyListeners();
      return false;
    }

    if (_isSubmitting) {
      _submitError = 'Schedule submission in progress';
      notifyListeners();
      return false;
    }

    final normalizedScheduleId = scheduleId?.trim();

    _isSubmitting = true;
    _submitError = null;
    notifyListeners();

    try {
      await _submitScheduleWriteWithTokenRetry(
        authProvider: authProvider,
        submit: (accessToken) async {
          if (normalizedScheduleId == null || normalizedScheduleId.isEmpty) {
            await _scheduleApi.createSchedule(
              accessToken: accessToken,
              rangerId: normalizedRangerId,
              workDate: workDate,
              note: note.trim(),
            );
          } else {
            await _scheduleApi.updateSchedule(
              accessToken: accessToken,
              scheduleId: normalizedScheduleId,
              rangerId: normalizedRangerId,
              workDate: workDate,
              note: note.trim(),
            );
          }
        },
      );

      _submitError = null;

      await loadSchedules(
        authProvider: authProvider,
        month: _focusedMonth,
        rangerId: _selectedRangerId,
      );
      return true;
    } catch (e) {
      _submitError = _userSafeMessageForApiError(
        e,
        fallback: 'Unable to save schedule',
      );
      notifyListeners();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  DateTime? parseWorkDate(String raw) => _parseIsoDay(raw);
}
