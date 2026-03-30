import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../services/mobile_api_service.dart';
import '../services/mobile_read_model_cache.dart';
import 'auth_provider.dart';

class IncidentProvider extends ChangeNotifier {
  final MobileIncidentApi _incidentApi;
  final MobileReadModelCache? _cache;
  final Duration staleAfter;

  IncidentProvider({
    required MobileIncidentApi incidentApi,
    MobileReadModelCache? cache,
    this.staleAfter = const Duration(minutes: 30),
  })  : _incidentApi = incidentApi,
        _cache = cache;

  List<MobileIncidentItem> _incidents = const [];
  bool _isLoading = false;
  String? _loadError;
  String? _refreshError;
  bool _isStaleData = false;
  bool _isOfflineFallback = false;
  bool _isUsingCachedData = false;
  bool _hasCrossRangerLeakage = false;

  String _scopeRole = 'ranger';
  bool _teamScope = false;
  String? _requestedRangerId;
  String? _effectiveRangerId;

  DateTime _fromDay = DateTime.now().toUtc().subtract(const Duration(days: 30));
  DateTime _toDay = DateTime.now().toUtc();
  DateTime? _lastSyncedAt;

  int _page = 1;
  int _pageSize = 50;
  int _total = 0;
  int _totalPages = 0;
  bool _hasMore = false;
  String? _activeCacheKey;
  String? _activeSessionKey;
  int _loadRequestId = 0;

  List<MobileIncidentItem> get incidents => List.unmodifiable(_incidents);
  List<MobileIncidentItem> get visibleIncidents => incidents;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  String? get refreshError => _refreshError;
  bool get isStaleData => _isStaleData;
  bool get isOfflineFallback => _isOfflineFallback;
  bool get isUsingCachedData => _isUsingCachedData;
  String get scopeRole => _scopeRole;
  bool get teamScope => _teamScope;
  String? get requestedRangerId => _requestedRangerId;
  String? get effectiveRangerId => _effectiveRangerId;
  DateTime get fromDay => _fromDay;
  DateTime get toDay => _toDay;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  int get page => _page;
  int get pageSize => _pageSize;
  int get total => _total;
  int get totalPages => _totalPages;
  bool get hasMore => _hasMore;

  bool get hasIncidents => visibleIncidents.isNotEmpty;

  bool _isCurrentLoadRequest(int requestId) {
    return requestId == _loadRequestId;
  }

  bool get isEmptyState =>
      !_isLoading && _loadError == null && !hasIncidents && !_isStaleData;

  bool get hasCrossRangerLeakage {
    return _hasCrossRangerLeakage;
  }

  String _deriveRoleFromAuth(AuthProvider authProvider) {
    if (authProvider.mobileRole == 'leader') {
      return 'leader';
    }
    return 'ranger';
  }

  Future<MobileIncidentListResult> _fetchIncidentsWithTokenRetry({
    required AuthProvider authProvider,
    required DateTime fromDay,
    required DateTime toDay,
    required int page,
    required int pageSize,
    String? cursor,
  }) async {
    final initialToken = authProvider.mobileAccessToken?.trim() ?? '';
    if (initialToken.isEmpty) {
      throw StateError('Missing mobile access token');
    }

    try {
      return await _incidentApi.fetchIncidents(
        accessToken: initialToken,
        fromDay: fromDay,
        toDay: toDay,
        page: page,
        pageSize: pageSize,
        cursor: cursor,
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

      return _incidentApi.fetchIncidents(
        accessToken: latestToken,
        fromDay: fromDay,
        toDay: toDay,
        page: page,
        pageSize: pageSize,
        cursor: cursor,
      );
    }
  }

  String _describeLoadError(Object error) {
    if (error is StateError) {
      final message = error.message.toString();
      if (message.contains('incident_pagination_guard_exceeded')) {
        return 'incident_error_pagination_guard';
      }
    }

    if (error is MobileApiException) {
      return error.toString();
    }
    if (error is TimeoutException) {
      return 'incident_error_timeout';
    }
    if (error is SocketException) {
      return 'incident_error_network';
    }
    return 'incident_error_unexpected';
  }

  DateTime? _parseIsoDateTime(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    final normalized = value.replaceAll('Z', '+00:00');
    try {
      return DateTime.parse(normalized).toUtc();
    } catch (_) {
      return null;
    }
  }

  bool _computeStale(DateTime? syncedAt) {
    if (!hasIncidents) {
      return false;
    }
    if (syncedAt == null) {
      return true;
    }
    return DateTime.now().toUtc().difference(syncedAt) > staleAfter;
  }

  String _formatIsoDay(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    return normalized.toIso8601String().split('T').first;
  }

  String _cacheKeyForIncidents({
    required DateTime fromDay,
    required DateTime toDay,
    required String role,
    required String sessionPartition,
  }) {
    return 'from=${_formatIsoDay(fromDay)}|to=${_formatIsoDay(toDay)}|role=$role|session=$sessionPartition';
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

  String _incidentIdentity(MobileIncidentItem item) {
    final incidentId = item.incidentId.trim();
    if (incidentId.isNotEmpty) {
      return 'incident:${incidentId.toLowerCase()}';
    }

    final eventId = item.erEventId.trim();
    if (eventId.isNotEmpty) {
      return 'event:${eventId.toLowerCase()}';
    }

    final payloadRef = _normalizeIdentityToken(item.payloadRef);
    if (payloadRef.isNotEmpty) {
      return 'payload:$payloadRef';
    }

    final rangerId = _normalizeIdentityToken(item.rangerId);
    final occurredAt = _normalizeIdentityToken(item.occurredAt);
    final updatedAt = _normalizeIdentityToken(item.updatedAt);
    final title = _normalizeIdentityToken(item.title);
    final status = _normalizeIdentityToken(item.status);
    final severity = _normalizeIdentityToken(item.severity);
    final mappingStatus = _normalizeIdentityToken(item.mappingStatus);
    return 'fallback:$rangerId::$occurredAt::$updatedAt::$mappingStatus::$status::$severity::$title';
  }

  DateTime _incidentSortTime(MobileIncidentItem item) {
    return _parseIsoDateTime(item.updatedAt) ??
        _parseIsoDateTime(item.occurredAt) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  List<MobileIncidentItem> _mergeIncidentItems({
    required List<MobileIncidentItem> base,
    required List<MobileIncidentItem> incoming,
  }) {
    final mergedByKey = <String, MobileIncidentItem>{};

    for (final item in base) {
      mergedByKey[_incidentIdentity(item)] = item;
    }
    for (final item in incoming) {
      mergedByKey[_incidentIdentity(item)] = item;
    }

    final merged = mergedByKey.values.toList(growable: false)
      ..sort((a, b) {
        final timeCompare = _incidentSortTime(b).compareTo(_incidentSortTime(a));
        if (timeCompare != 0) {
          return timeCompare;
        }
        return _incidentIdentity(a).compareTo(_incidentIdentity(b));
      });

    return merged;
  }

  List<MobileIncidentItem> _scopeIncidentItems({
    required List<MobileIncidentItem> items,
    required String role,
    required String? effectiveRangerId,
  }) {
    if (role != 'ranger') {
      return List<MobileIncidentItem>.from(items, growable: false);
    }

    final effective = effectiveRangerId?.trim();
    if (effective == null || effective.isEmpty) {
      return const <MobileIncidentItem>[];
    }

    return items
      .where((item) => (item.rangerId ?? '').trim() == effective)
        .toList(growable: false);
  }

  bool _detectCrossRangerLeakage({
    required List<MobileIncidentItem> items,
    required String role,
    required String? effectiveRangerId,
  }) {
    if (role != 'ranger') {
      return false;
    }

    final effective = effectiveRangerId?.trim();
    if (effective == null || effective.isEmpty) {
      return items.isNotEmpty;
    }

    return items.any((item) {
      final rangerId = (item.rangerId ?? '').trim();
      return rangerId.isEmpty || rangerId != effective;
    });
  }

  void _applyIncidentResult(
    MobileIncidentListResult result, {
    required String fallbackRole,
  }) {
    final resolvedRole = fallbackRole == 'leader' ? 'leader' : 'ranger';
    final resolvedEffectiveRangerId = result.scope.effectiveRangerId;
    _incidents = _scopeIncidentItems(
      items: result.items,
      role: resolvedRole,
      effectiveRangerId: resolvedEffectiveRangerId,
    );
    _scopeRole = resolvedRole;
    _teamScope = resolvedRole == 'leader' ? result.scope.teamScope : false;
    _requestedRangerId =
        resolvedRole == 'leader' ? result.scope.requestedRangerId : null;
    _effectiveRangerId = resolvedEffectiveRangerId;
    _hasCrossRangerLeakage = _detectCrossRangerLeakage(
      items: result.items,
      role: resolvedRole,
      effectiveRangerId: resolvedEffectiveRangerId,
    );

    _page = result.pagination.page;
    _pageSize = result.pagination.pageSize;
    _total = result.pagination.total;
    _totalPages = result.pagination.totalPages;
    _hasMore = result.sync.hasMore;

    _lastSyncedAt = _parseIsoDateTime(result.sync.lastSyncedAt);
    _isStaleData = _computeStale(_lastSyncedAt);

    if (_scopeRole == 'ranger' && hasCrossRangerLeakage) {
      debugPrint(
        'IncidentProvider: filtered cross-ranger incidents from ranger-scoped payload.',
      );
    }
  }

  Future<void> loadIncidents({
    required AuthProvider authProvider,
    DateTime? fromDay,
    DateTime? toDay,
    bool isRefresh = false,
  }) async {
    final requestId = ++_loadRequestId;
    final targetFromDay = (fromDay ?? _fromDay).toUtc();
    final targetToDay = (toDay ?? _toDay).toUtc();

    _fromDay = targetFromDay;
    _toDay = targetToDay;

    final authRole = _deriveRoleFromAuth(authProvider);
    final sessionPartition = _sessionPartitionFromAuth(authProvider);
    final incidentSessionKey = 'role=$authRole|session=$sessionPartition';
    final hadSessionScopedData =
        _incidents.isNotEmpty ||
        _requestedRangerId != null ||
        _effectiveRangerId != null;

    if (_activeSessionKey != incidentSessionKey) {
      _activeSessionKey = incidentSessionKey;
      _activeCacheKey = null;

      _incidents = const <MobileIncidentItem>[];
      _scopeRole = authRole;
      _teamScope = false;
      _requestedRangerId = null;
      _effectiveRangerId = null;
      _hasCrossRangerLeakage = false;
      _page = 1;
      _pageSize = 50;
      _total = 0;
      _totalPages = 0;
      _hasMore = false;

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

    final cache = _cache;
    final cacheKey = _cacheKeyForIncidents(
      fromDay: targetFromDay,
      toDay: targetToDay,
      role: authRole,
      sessionPartition: sessionPartition,
    );
    final hasActiveInMemoryData = _activeCacheKey == cacheKey && _incidents.isNotEmpty;

    CachedReadModel<MobileIncidentListResult>? cachedIncidents;
    if (cache != null) {
      cachedIncidents = await cache.loadIncidents(cacheKey);
      if (!_isCurrentLoadRequest(requestId)) {
        return;
      }

      if (cachedIncidents != null) {
        _applyIncidentResult(cachedIncidents.value, fallbackRole: authRole);
        _activeCacheKey = cacheKey;
        _lastSyncedAt = cachedIncidents.syncedAt ?? _lastSyncedAt;
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

      final tokenError = 'Missing mobile access token';
      if (cachedIncidents != null || hasActiveInMemoryData) {
        _loadError = null;
        _refreshError = tokenError;
        _isStaleData = true;
        _isOfflineFallback = true;
        _isUsingCachedData = true;
      } else {
        _loadError = tokenError;
        _refreshError = null;
        _incidents = const [];
        _scopeRole = authRole;
        _teamScope = false;
        _requestedRangerId = null;
        _effectiveRangerId = null;
        _hasCrossRangerLeakage = false;
        _page = 1;
        _pageSize = 50;
        _total = 0;
        _totalPages = 0;
        _hasMore = false;
        _lastSyncedAt = null;
        _isStaleData = false;
        _isOfflineFallback = false;
        _isUsingCachedData = false;
        _activeCacheKey = null;
      }
      _isLoading = false;
      notifyListeners();
      return;
    }

    if (!_isCurrentLoadRequest(requestId)) {
      return;
    }

    _isLoading = true;
    if (!isRefresh) {
      if (cachedIncidents == null) {
        _loadError = null;
      }
    }
    _refreshError = null;
    notifyListeners();

    try {
      const pageSize = 100;
      final networkItems = <MobileIncidentItem>[];
      final seenCursors = <String>{};

      MobileIncidentListResult? firstResult;
      MobileIncidentListResult? latestResult;
      String? activeCursor;
      var page = 1;
      var loopCount = 0;
      var paginationGuardExceeded = false;

      while (true) {
        loopCount += 1;
        if (loopCount > 50) {
          paginationGuardExceeded = true;
          break;
        }

        final result = await _fetchIncidentsWithTokenRetry(
          authProvider: authProvider,
          fromDay: targetFromDay,
          toDay: targetToDay,
          page: page,
          pageSize: pageSize,
          cursor: activeCursor,
        );

        if (!_isCurrentLoadRequest(requestId)) {
          return;
        }

        firstResult ??= result;
        latestResult = result;
        networkItems.addAll(result.items);

        final nextCursor = result.sync.cursor?.trim();
        final hasCursor = nextCursor != null && nextCursor.isNotEmpty;
        final hasPaginationMore =
            result.pagination.totalPages > 0 && page < result.pagination.totalPages;

        if (!result.sync.hasMore && !hasPaginationMore) {
          break;
        }

        if (hasCursor) {
          final normalizedCursor = nextCursor!;
          if (!seenCursors.add(normalizedCursor)) {
            break;
          }
          activeCursor = normalizedCursor;
          page += 1;
          continue;
        }

        if (hasPaginationMore) {
          page += 1;
          activeCursor = null;
          continue;
        }

        break;
      }

      if (paginationGuardExceeded) {
        throw StateError('incident_pagination_guard_exceeded');
      }

      if (latestResult == null || firstResult == null) {
        throw StateError('Unable to load incidents');
      }

      final result = latestResult;
      final authoritativeNetworkItems = _mergeIncidentItems(
        base: const <MobileIncidentItem>[],
        incoming: networkItems,
      );

      final mergedItems = _mergeIncidentItems(
        base: const <MobileIncidentItem>[],
        incoming: authoritativeNetworkItems,
      );

      final mergedResult = MobileIncidentListResult(
        items: mergedItems,
        scope: result.scope,
        pagination: result.pagination,
        sync: result.sync,
        fromDay: result.fromDay ?? cachedIncidents?.value.fromDay,
        toDay: result.toDay ?? cachedIncidents?.value.toDay,
        updatedSince: result.updatedSince ?? cachedIncidents?.value.updatedSince,
      );

      _applyIncidentResult(mergedResult, fallbackRole: authRole);
      _activeCacheKey = cacheKey;

      final serverSyncedAt = _parseIsoDateTime(result.sync.lastSyncedAt);
      _lastSyncedAt = serverSyncedAt;
      _isStaleData = _computeStale(_lastSyncedAt);
      _isOfflineFallback = false;
      _isUsingCachedData = false;

      _loadError = null;
      _refreshError = null;

      if (cache != null) {
        final persistedSyncedAt =
            serverSyncedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final cacheSafeResult = MobileIncidentListResult(
          items: _incidents,
          scope: mergedResult.scope,
          pagination: mergedResult.pagination,
          sync: mergedResult.sync,
          fromDay: mergedResult.fromDay,
          toDay: mergedResult.toDay,
          updatedSince: mergedResult.updatedSince,
        );
        await cache.saveIncidents(
          cacheKey: cacheKey,
          value: cacheSafeResult,
          syncedAt: persistedSyncedAt,
        );

        if (!_isCurrentLoadRequest(requestId)) {
          return;
        }
      }
    } catch (e) {
      if (!_isCurrentLoadRequest(requestId)) {
        return;
      }

      final errorMessage = _describeLoadError(e);
      if (cachedIncidents != null || hasActiveInMemoryData) {
        _loadError = null;
        _refreshError = errorMessage;
        _isStaleData = true;
        _isOfflineFallback = true;
        _isUsingCachedData = true;
      } else {
        _loadError = errorMessage;
        _refreshError = null;
        _incidents = const [];
        _scopeRole = authRole;
        _teamScope = false;
        _requestedRangerId = null;
        _effectiveRangerId = null;
        _hasCrossRangerLeakage = false;
        _page = 1;
        _pageSize = 50;
        _total = 0;
        _totalPages = 0;
        _hasMore = false;
        _lastSyncedAt = null;
        _isStaleData = false;
        _isOfflineFallback = false;
        _isUsingCachedData = false;
        _activeCacheKey = null;
      }
    } finally {
      if (_isCurrentLoadRequest(requestId)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshIncidents({required AuthProvider authProvider}) async {
    await loadIncidents(authProvider: authProvider, isRefresh: true);
  }
}
