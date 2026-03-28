import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treeinfo_dart/providers/auth_provider.dart';
import 'package:treeinfo_dart/providers/incident_provider.dart';
import 'package:treeinfo_dart/services/mobile_api_service.dart';
import 'package:treeinfo_dart/services/mobile_read_model_cache.dart';

String _sessionPartition(String seed) {
  final digest = sha256.convert(utf8.encode(seed)).toString();
  return 'u$digest';
}

class _FakeMobileIncidentApi implements MobileIncidentApi {
  int callCount = 0;
  final List<MobileIncidentListResult> _responses;
  Object? errorToThrow;
  final List<int> requestedPages = <int>[];
  final List<String?> requestedCursors = <String?>[];
  final List<String> requestedAccessTokens = <String>[];

  _FakeMobileIncidentApi(this._responses, {this.errorToThrow});

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
    callCount += 1;
    requestedPages.add(page);
    requestedCursors.add(cursor);
    requestedAccessTokens.add(accessToken);

    if (errorToThrow != null) {
      throw errorToThrow!;
    }

    if (_responses.isEmpty) {
      return const MobileIncidentListResult(
        items: <MobileIncidentItem>[],
        scope: MobileIncidentScope(
          role: 'ranger',
          teamScope: false,
          requestedRangerId: null,
          effectiveRangerId: 'rangeruser',
        ),
        pagination: MobileIncidentPagination(
          page: 1,
          pageSize: 50,
          total: 0,
          totalPages: 0,
        ),
        sync: MobileIncidentSync(cursor: null, hasMore: false, lastSyncedAt: null),
        fromDay: null,
        toDay: null,
        updatedSince: null,
      );
    }

    return _responses.removeAt(0);
  }
}

class _TokenRefreshIncidentApi implements MobileIncidentApi {
  final void Function() onFirstCall;
  int callCount = 0;
  final List<String> requestedAccessTokens = <String>[];

  _TokenRefreshIncidentApi({required this.onFirstCall});

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
    callCount += 1;
    requestedAccessTokens.add(accessToken);

    if (callCount == 1) {
      onFirstCall();
      throw MobileApiException(401, 'expired access token');
    }

    return const MobileIncidentListResult(
      items: <MobileIncidentItem>[
        MobileIncidentItem(
          incidentId: 'inc-retry',
          erEventId: 'er-retry',
          rangerId: 'rangeruser',
          mappingStatus: 'mapped',
          occurredAt: '2026-03-24T01:00:00Z',
          updatedAt: '2026-03-24T01:10:00Z',
          title: 'Retry recovered incident',
          status: 'open',
          severity: 'medium',
          payloadRef: 'payload/inc-retry.json',
        ),
      ],
      scope: MobileIncidentScope(
        role: 'ranger',
        teamScope: false,
        requestedRangerId: null,
        effectiveRangerId: 'rangeruser',
      ),
      pagination: MobileIncidentPagination(
        page: 1,
        pageSize: 50,
        total: 1,
        totalPages: 1,
      ),
      sync: MobileIncidentSync(
        cursor: null,
        hasMore: false,
        lastSyncedAt: '2026-03-24T01:10:00Z',
      ),
      fromDay: '2026-03-01',
      toDay: '2026-03-31',
      updatedSince: null,
    );
  }
}

class _QueuedMobileIncidentApi implements MobileIncidentApi {
  final List<Completer<MobileIncidentListResult>> _queue;
  int callCount = 0;

  _QueuedMobileIncidentApi(this._queue);

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
  }) {
    callCount += 1;
    if (_queue.isEmpty) {
      throw StateError('No queued incident response completer');
    }
    return _queue.removeAt(0).future;
  }
}

class _InMemoryReadModelCache implements MobileReadModelCache {
  final Map<String, CachedReadModel<MobileWorkSummaryResult>> _work =
      <String, CachedReadModel<MobileWorkSummaryResult>>{};
  final Map<String, CachedReadModel<MobileIncidentListResult>> _incidents =
      <String, CachedReadModel<MobileIncidentListResult>>{};
  final Map<String, CachedReadModel<MobileScheduleListResult>> _schedules =
      <String, CachedReadModel<MobileScheduleListResult>>{};

  @override
  Future<CachedReadModel<MobileWorkSummaryResult>?> loadWorkSummary(
    String cacheKey,
  ) async {
    return _work[cacheKey];
  }

  @override
  Future<void> saveWorkSummary({
    required String cacheKey,
    required MobileWorkSummaryResult value,
    required DateTime syncedAt,
  }) async {
    _work[cacheKey] = CachedReadModel<MobileWorkSummaryResult>(
      value: value,
      syncedAt: syncedAt,
    );
  }

  @override
  Future<CachedReadModel<MobileIncidentListResult>?> loadIncidents(
    String cacheKey,
  ) async {
    return _incidents[cacheKey];
  }

  @override
  Future<void> saveIncidents({
    required String cacheKey,
    required MobileIncidentListResult value,
    required DateTime syncedAt,
  }) async {
    _incidents[cacheKey] = CachedReadModel<MobileIncidentListResult>(
      value: value,
      syncedAt: syncedAt,
    );
  }

  @override
  Future<CachedReadModel<MobileScheduleListResult>?> loadSchedules(
    String cacheKey,
  ) async {
    return _schedules[cacheKey];
  }

  @override
  Future<void> saveSchedules({
    required String cacheKey,
    required MobileScheduleListResult value,
    required DateTime syncedAt,
  }) async {
    _schedules[cacheKey] = CachedReadModel<MobileScheduleListResult>(
      value: value,
      syncedAt: syncedAt,
    );
  }
}

void main() {
  group('IncidentProvider operational states', () {
    test('leader scope displays all incidents across ranger IDs', () async {
      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-leader-1',
              erEventId: 'er-leader-1',
              rangerId: 'ranger-a',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Boundary issue A',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-leader-1.json',
            ),
            MobileIncidentItem(
              incidentId: 'inc-leader-2',
              erEventId: 'er-leader-2',
              rangerId: 'ranger-b',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-21T01:00:00Z',
              updatedAt: '2026-03-21T02:00:00Z',
              title: 'Boundary issue B',
              status: 'resolved',
              severity: 'high',
              payloadRef: 'payload/inc-leader-2.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 2,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-21T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final provider = IncidentProvider(incidentApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadIncidents(authProvider: auth);

      expect(provider.scopeRole, 'leader');
      expect(provider.visibleIncidents.length, 2);
      expect(provider.hasCrossRangerLeakage, isFalse);
    });

    test('renders ranger-scoped incidents without cross-ranger leakage', () async {
      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-1',
              erEventId: 'er-1',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Fence broken',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-1.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-20T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final provider = IncidentProvider(incidentApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadIncidents(authProvider: auth);

      expect(provider.scopeRole, 'ranger');
      expect(provider.hasCrossRangerLeakage, isFalse);
      expect(provider.visibleIncidents.length, 1);
      expect(provider.visibleIncidents.first.rangerId, 'rangeruser');
      expect(provider.loadError, isNull);
    });

    test('defensively hides leaked records for ranger-scoped payloads', () async {
      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-1',
              erEventId: 'er-1',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Fence broken',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-1.json',
            ),
            MobileIncidentItem(
              incidentId: 'inc-2',
              erEventId: 'er-2',
              rangerId: 'otherranger',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T03:00:00Z',
              updatedAt: '2026-03-20T04:00:00Z',
              title: 'Other ranger event',
              status: 'open',
              severity: 'high',
              payloadRef: 'payload/inc-2.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 2,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-20T04:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final provider = IncidentProvider(incidentApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadIncidents(authProvider: auth);

      expect(provider.hasCrossRangerLeakage, isTrue);
      expect(provider.incidents.length, 1);
      expect(provider.visibleIncidents.length, 1);
      expect(provider.visibleIncidents.first.rangerId, 'rangeruser');
    });

    test('hides ranger incidents when effective ranger scope is missing',
        () async {
      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-1',
              erEventId: 'er-1',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Fence broken',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-1.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-20T04:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final provider = IncidentProvider(incidentApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadIncidents(authProvider: auth);

      expect(provider.visibleIncidents, isEmpty);
      expect(provider.hasCrossRangerLeakage, isTrue);
    });

    test('supports empty and stale states from sync metadata', () async {
      final oldSync = DateTime.now().toUtc().subtract(const Duration(hours: 2));
      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[],
          scope: MobileIncidentScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 0,
            totalPages: 0,
          ),
          sync: MobileIncidentSync(cursor: null, hasMore: false, lastSyncedAt: null),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
        MobileIncidentListResult(
          items: const <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-3',
              erEventId: 'er-3',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Patrol note',
              status: 'closed',
              severity: 'low',
              payloadRef: 'payload/inc-3.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final provider = IncidentProvider(incidentApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadIncidents(authProvider: auth);
      expect(provider.isEmptyState, isTrue);
      expect(provider.isStaleData, isFalse);

      fakeApi.errorToThrow = null;
      fakeApi._responses.add(
        MobileIncidentListResult(
          items: const <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-4',
              erEventId: 'er-4',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Old sync item',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-4.json',
            ),
          ],
          scope: const MobileIncidentScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: const MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: oldSync.toIso8601String(),
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      );

      await provider.loadIncidents(authProvider: auth);
      expect(provider.hasIncidents, isTrue);
      expect(provider.isStaleData, isTrue);
    });

    test('keeps existing data and marks refresh-error as stale when refresh fails',
        () async {
      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-1',
              erEventId: 'er-1',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Fence broken',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-1.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-20T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final provider = IncidentProvider(incidentApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadIncidents(authProvider: auth);
      expect(provider.hasIncidents, isTrue);

      fakeApi.errorToThrow = MobileApiException(500, 'refresh failed');
      await provider.refreshIncidents(authProvider: auth);

      expect(provider.hasIncidents, isTrue);
      expect(provider.refreshError, contains('MobileApiException(500)'));
      expect(provider.isStaleData, isTrue);
    });

    test('uses cached incidents when refresh fails and marks offline fallback',
        () async {
      final cache = _InMemoryReadModelCache();
      await cache.saveIncidents(
        cacheKey:
            'from=2026-03-01|to=2026-03-31|role=ranger|session=${_sessionPartition('refresh-ranger')}',
        value: const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-cached',
              erEventId: 'er-cached',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Cached incident',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-cached.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-20T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
        syncedAt: DateTime.utc(2026, 3, 20, 2),
      );

      final fakeApi = _FakeMobileIncidentApi(
        const <MobileIncidentListResult>[],
        errorToThrow: MobileApiException(503, 'offline'),
      );

      final provider = IncidentProvider(incidentApi: fakeApi, cache: cache);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadIncidents(
        authProvider: auth,
        fromDay: DateTime.utc(2026, 3, 1),
        toDay: DateTime.utc(2026, 3, 31),
      );

      expect(provider.hasIncidents, isTrue);
      expect(provider.loadError, isNull);
      expect(provider.refreshError, contains('MobileApiException(503)'));
      expect(provider.isOfflineFallback, isTrue);
      expect(provider.isStaleData, isTrue);
    });

    test('merges reconnect payload by incident identity without duplicates',
        () async {
      final cache = _InMemoryReadModelCache();
      await cache.saveIncidents(
        cacheKey:
            'from=2026-03-01|to=2026-03-31|role=ranger|session=${_sessionPartition('refresh-ranger')}',
        value: const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-1',
              erEventId: 'er-1',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Old title',
              status: 'open',
              severity: 'low',
              payloadRef: 'payload/inc-1.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-20T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
        syncedAt: DateTime.utc(2026, 3, 20, 2),
      );

      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-1',
              erEventId: 'er-1',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T03:00:00Z',
              title: 'Updated title',
              status: 'resolved',
              severity: 'high',
              payloadRef: 'payload/inc-1.json',
            ),
            MobileIncidentItem(
              incidentId: 'inc-2',
              erEventId: 'er-2',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-21T01:00:00Z',
              updatedAt: '2026-03-21T03:00:00Z',
              title: 'New incident',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-2.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 2,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-21T03:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final provider = IncidentProvider(incidentApi: fakeApi, cache: cache);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadIncidents(
        authProvider: auth,
        fromDay: DateTime.utc(2026, 3, 1),
        toDay: DateTime.utc(2026, 3, 31),
      );

      final incidents = provider.incidents;
      expect(incidents.where((item) => item.incidentId == 'inc-1').length, 1);
      expect(incidents.where((item) => item.incidentId == 'inc-2').length, 1);
      expect(
        incidents.firstWhere((item) => item.incidentId == 'inc-1').severity,
        'high',
      );
      expect(provider.refreshError, isNull);
      expect(provider.isOfflineFallback, isFalse);
    });

    test('normalizes fallback incident identity to avoid cosmetic duplicates',
        () async {
      final cache = _InMemoryReadModelCache();
      await cache.saveIncidents(
        cacheKey:
            'from=2026-03-01|to=2026-03-31|role=ranger|session=${_sessionPartition('refresh-ranger')}',
        value: const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: '',
              erEventId: '',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: 'Fence Broken',
              status: 'OPEN',
              severity: 'HIGH',
              payloadRef: null,
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-20T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
        syncedAt: DateTime.utc(2026, 3, 20, 2),
      );

      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: '',
              erEventId: '',
              rangerId: 'rangeruser',
              mappingStatus: '  MAPPED  ',
              occurredAt: '2026-03-20T01:00:00Z',
              updatedAt: '2026-03-20T02:00:00Z',
              title: '  fence    broken ',
              status: ' open ',
              severity: ' high ',
              payloadRef: null,
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-20T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final provider = IncidentProvider(incidentApi: fakeApi, cache: cache);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadIncidents(
        authProvider: auth,
        fromDay: DateTime.utc(2026, 3, 1),
        toDay: DateTime.utc(2026, 3, 31),
      );

      expect(provider.incidents.length, 1);
      expect(provider.incidents.first.status.trim().toLowerCase(), 'open');
      expect(provider.refreshError, isNull);
    });

    test('follows cursor pagination chain until hasMore=false', () async {
      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-page-1',
              erEventId: 'er-page-1',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-22T01:00:00Z',
              updatedAt: '2026-03-22T02:00:00Z',
              title: 'Page one incident',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-page-1.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 2,
            totalPages: 2,
          ),
          sync: MobileIncidentSync(
            cursor: 'cursor-page-2',
            hasMore: true,
            lastSyncedAt: '2026-03-22T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-page-2',
              erEventId: 'er-page-2',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-23T01:00:00Z',
              updatedAt: '2026-03-23T02:00:00Z',
              title: 'Page two incident',
              status: 'resolved',
              severity: 'high',
              payloadRef: 'payload/inc-page-2.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 2,
            pageSize: 50,
            total: 2,
            totalPages: 2,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-23T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final provider = IncidentProvider(incidentApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.loadIncidents(
        authProvider: auth,
        fromDay: DateTime.utc(2026, 3, 1),
        toDay: DateTime.utc(2026, 3, 31),
      );

      expect(fakeApi.callCount, 2);
      expect(fakeApi.requestedPages, <int>[1, 2]);
      expect(fakeApi.requestedCursors, <String?>[null, 'cursor-page-2']);
      expect(
        provider.incidents.map((item) => item.incidentId).toSet(),
        <String>{'inc-page-1', 'inc-page-2'},
      );
      expect(provider.loadError, isNull);
    });

    test('retries once when access token changes after unauthorized response',
        () async {
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-old',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      final retryApi = _TokenRefreshIncidentApi(
        onFirstCall: () {
          auth.setMobileSession(
            accessToken: 'token-new',
            refreshToken: 'refresh-ranger',
            role: 'ranger',
            username: 'rangeruser',
          );
        },
      );

      final provider = IncidentProvider(incidentApi: retryApi);

      await provider.loadIncidents(authProvider: auth);

      expect(retryApi.callCount, 2);
      expect(
        retryApi.requestedAccessTokens,
        <String>['token-old', 'token-new'],
      );
      expect(provider.hasIncidents, isTrue);
      expect(provider.loadError, isNull);
    });

    test('does not widen ranger scope from stale admin login state',
        () async {
      final fakeApi = _FakeMobileIncidentApi([
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-ranger',
              erEventId: 'er-ranger',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-21T01:00:00Z',
              updatedAt: '2026-03-21T02:00:00Z',
              title: 'Own incident',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-ranger.json',
            ),
            MobileIncidentItem(
              incidentId: 'inc-other',
              erEventId: 'er-other',
              rangerId: 'other-ranger',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-21T03:00:00Z',
              updatedAt: '2026-03-21T04:00:00Z',
              title: 'Other incident',
              status: 'open',
              severity: 'high',
              payloadRef: 'payload/inc-other.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 2,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-21T04:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      ]);

      final auth = AuthProvider();
      auth.debugSetAdminForTesting(true);
      expect(auth.isAdmin, isTrue);

      auth.setMobileSession(
        accessToken: 'token-ranger',
        refreshToken: 'refresh-ranger',
        role: 'ranger',
        username: 'rangeruser',
      );

      expect(auth.isAdmin, isFalse);

      final provider = IncidentProvider(incidentApi: fakeApi);
      await provider.loadIncidents(authProvider: auth);

      expect(provider.scopeRole, 'ranger');
      expect(provider.visibleIncidents, isEmpty);
      expect(provider.hasCrossRangerLeakage, isTrue);
    });

    test('ignores stale out-of-order incident responses', () async {
      final firstRequest = Completer<MobileIncidentListResult>();
      final secondRequest = Completer<MobileIncidentListResult>();
      final queuedApi = _QueuedMobileIncidentApi(
        <Completer<MobileIncidentListResult>>[firstRequest, secondRequest],
      );

      final provider = IncidentProvider(incidentApi: queuedApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      final marchLoad = provider.loadIncidents(
        authProvider: auth,
        fromDay: DateTime.utc(2026, 3, 1),
        toDay: DateTime.utc(2026, 3, 31),
      );

      final aprilLoad = provider.loadIncidents(
        authProvider: auth,
        fromDay: DateTime.utc(2026, 4, 1),
        toDay: DateTime.utc(2026, 4, 30),
      );

      secondRequest.complete(
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-april',
              erEventId: 'er-april',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-04-03T01:00:00Z',
              updatedAt: '2026-04-03T02:00:00Z',
              title: 'April incident',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-april.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-04-03T02:00:00Z',
          ),
          fromDay: '2026-04-01',
          toDay: '2026-04-30',
          updatedSince: null,
        ),
      );
      await aprilLoad;

      firstRequest.complete(
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-march',
              erEventId: 'er-march',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-03T01:00:00Z',
              updatedAt: '2026-03-03T02:00:00Z',
              title: 'March incident',
              status: 'open',
              severity: 'low',
              payloadRef: 'payload/inc-march.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-03T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      );
      await marchLoad;

      expect(queuedApi.callCount, 2);
      expect(provider.fromDay, DateTime.utc(2026, 4, 1));
      expect(provider.toDay, DateTime.utc(2026, 4, 30));
      expect(provider.incidents.length, 1);
      expect(provider.incidents.first.incidentId, 'inc-april');
    });

    test('clears in-memory incidents immediately on session switch', () async {
      final firstRequest = Completer<MobileIncidentListResult>();
      final secondRequest = Completer<MobileIncidentListResult>();
      final queuedApi = _QueuedMobileIncidentApi(
        <Completer<MobileIncidentListResult>>[firstRequest, secondRequest],
      );

      final provider = IncidentProvider(incidentApi: queuedApi);
      final authA = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger-a',
          refreshToken: 'refresh-ranger-a',
          role: 'ranger',
          username: 'rangeruser',
        );
      final authB = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger-b',
          refreshToken: 'refresh-ranger-b',
          role: 'ranger',
          username: 'rangeruser',
        );

      final marchLoad = provider.loadIncidents(
        authProvider: authA,
        fromDay: DateTime.utc(2026, 3, 1),
        toDay: DateTime.utc(2026, 3, 31),
      );

      firstRequest.complete(
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-session-a',
              erEventId: 'er-session-a',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-10T01:00:00Z',
              updatedAt: '2026-03-10T02:00:00Z',
              title: 'Session A incident',
              status: 'open',
              severity: 'medium',
              payloadRef: 'payload/inc-session-a.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-10T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      );
      await marchLoad;

      expect(provider.incidents.length, 1);
      expect(provider.incidents.first.incidentId, 'inc-session-a');

      final aprilLoad = provider.loadIncidents(
        authProvider: authB,
        fromDay: DateTime.utc(2026, 4, 1),
        toDay: DateTime.utc(2026, 4, 30),
      );

      expect(provider.incidents, isEmpty);

      secondRequest.complete(
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-session-b',
              erEventId: 'er-session-b',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-04-10T01:00:00Z',
              updatedAt: '2026-04-10T02:00:00Z',
              title: 'Session B incident',
              status: 'open',
              severity: 'high',
              payloadRef: 'payload/inc-session-b.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-04-10T02:00:00Z',
          ),
          fromDay: '2026-04-01',
          toDay: '2026-04-30',
          updatedSince: null,
        ),
      );
      await aprilLoad;

      expect(provider.incidents.length, 1);
      expect(provider.incidents.first.incidentId, 'inc-session-b');
    });

    test('superseded missing-token request resets incident loading state',
        () async {
      final inFlightResponse = Completer<MobileIncidentListResult>();
      final queuedApi = _QueuedMobileIncidentApi(
        <Completer<MobileIncidentListResult>>[inFlightResponse],
      );

      final provider = IncidentProvider(incidentApi: queuedApi);
      final authWithToken = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      final inFlightLoad = provider.loadIncidents(
        authProvider: authWithToken,
        fromDay: DateTime.utc(2026, 3, 1),
        toDay: DateTime.utc(2026, 3, 31),
      );

      final noTokenAuth = AuthProvider();
      await provider.loadIncidents(
        authProvider: noTokenAuth,
        fromDay: DateTime.utc(2026, 4, 1),
        toDay: DateTime.utc(2026, 4, 30),
      );

      expect(provider.isLoading, isFalse);
      expect(provider.loadError, 'Missing mobile access token');

      inFlightResponse.complete(
        const MobileIncidentListResult(
          items: <MobileIncidentItem>[
            MobileIncidentItem(
              incidentId: 'inc-stale',
              erEventId: 'er-stale',
              rangerId: 'rangeruser',
              mappingStatus: 'mapped',
              occurredAt: '2026-03-05T01:00:00Z',
              updatedAt: '2026-03-05T02:00:00Z',
              title: 'Stale response',
              status: 'open',
              severity: 'low',
              payloadRef: 'payload/inc-stale.json',
            ),
          ],
          scope: MobileIncidentScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          pagination: MobileIncidentPagination(
            page: 1,
            pageSize: 50,
            total: 1,
            totalPages: 1,
          ),
          sync: MobileIncidentSync(
            cursor: null,
            hasMore: false,
            lastSyncedAt: '2026-03-05T02:00:00Z',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          updatedSince: null,
        ),
      );
      await inFlightLoad;

      expect(provider.isLoading, isFalse);
      expect(provider.loadError, 'Missing mobile access token');
      expect(provider.incidents, isEmpty);
    });

    test('scope model parsing trims requested/effective ranger IDs', () {
      final incidentScope = MobileIncidentScope.fromJson(
        <String, dynamic>{
          'role': 'ranger',
          'team_scope': false,
          'requested_ranger_id': ' ranger-01 ',
          'effective_ranger_id': ' ranger-01 ',
        },
      );

      final workScope = MobileWorkScope.fromJson(
        <String, dynamic>{
          'role': 'leader',
          'team_scope': true,
          'requested_ranger_id': ' ranger-02 ',
          'effective_ranger_id': ' ranger-02 ',
        },
      );

      final scheduleScope = MobileScheduleScope.fromJson(
        <String, dynamic>{
          'role': 'leader',
          'team_scope': true,
          'requested_ranger_id': ' ranger-03 ',
          'effective_ranger_id': ' ranger-03 ',
        },
      );

      expect(incidentScope.requestedRangerId, 'ranger-01');
      expect(incidentScope.effectiveRangerId, 'ranger-01');
      expect(workScope.requestedRangerId, 'ranger-02');
      expect(workScope.effectiveRangerId, 'ranger-02');
      expect(scheduleScope.requestedRangerId, 'ranger-03');
      expect(scheduleScope.effectiveRangerId, 'ranger-03');
    });

    test('incident pagination parsing clamps invalid values safely', () {
      final pagination = MobileIncidentPagination.fromJson(
        <String, dynamic>{
          'page': 999,
          'page_size': 0,
          'total': -12,
          'total_pages': 2,
        },
      );

      expect(pagination.page, 2);
      expect(pagination.pageSize, 50);
      expect(pagination.total, 0);
      expect(pagination.totalPages, 2);
    });
  });
}
