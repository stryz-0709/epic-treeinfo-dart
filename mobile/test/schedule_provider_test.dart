import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treeinfo_dart/providers/auth_provider.dart';
import 'package:treeinfo_dart/providers/schedule_provider.dart';
import 'package:treeinfo_dart/services/mobile_api_service.dart';
import 'package:treeinfo_dart/services/mobile_read_model_cache.dart';

String _sessionPartition(String seed) {
  final digest = sha256.convert(utf8.encode(seed)).toString();
  return 'u$digest';
}

class _FakeMobileScheduleApi implements MobileScheduleApi {
  int fetchCallCount = 0;
  int createCallCount = 0;
  int updateCallCount = 0;
  int deleteCallCount = 0;

  final List<String?> requestedRangerIds = <String?>[];
  final List<String> fetchAccessTokens = <String>[];
  final List<String> createAccessTokens = <String>[];
  final List<String> updateAccessTokens = <String>[];
  final List<String> deleteAccessTokens = <String>[];
  final List<MobileScheduleListResult> _fetchResponses;

  Object? fetchError;
  Object? createError;
  Object? updateError;
  Object? deleteError;
  int throwFetchErrorForCalls = 0;
  int throwCreateErrorForCalls = 0;
  int throwUpdateErrorForCalls = 0;
  int throwDeleteErrorForCalls = 0;
  void Function(int callCount)? onFetchCall;
  void Function(int callCount)? onCreateCall;
  void Function(int callCount)? onUpdateCall;
  void Function(int callCount)? onDeleteCall;

  String? lastCreateRangerId;
  DateTime? lastCreateWorkDate;
  String? lastCreateNote;
  Completer<void>? createCompleter;
  Completer<void>? fetchCompleter;

  String? lastUpdateScheduleId;
  String? lastUpdateRangerId;
  DateTime? lastUpdateWorkDate;
  String? lastUpdateNote;
  String? lastDeletedScheduleId;

  _FakeMobileScheduleApi(this._fetchResponses);

  @override
  Future<MobileScheduleListResult> fetchSchedules({
    required String accessToken,
    DateTime? fromDay,
    DateTime? toDay,
    String? rangerId,
  }) async {
    fetchCallCount += 1;
    requestedRangerIds.add(rangerId);
    fetchAccessTokens.add(accessToken);
    onFetchCall?.call(fetchCallCount);

    if (fetchError != null &&
        (throwFetchErrorForCalls <= 0 ||
            fetchCallCount <= throwFetchErrorForCalls)) {
      throw fetchError!;
    }

    if (fetchCompleter != null) {
      await fetchCompleter!.future;
    }

    if (_fetchResponses.isEmpty) {
      return const MobileScheduleListResult(
        items: <MobileScheduleItem>[],
        scope: MobileScheduleScope(
          role: 'ranger',
          teamScope: false,
          requestedRangerId: null,
          effectiveRangerId: 'rangeruser',
        ),
        fromDay: null,
        toDay: null,
      );
    }

    return _fetchResponses.removeAt(0);
  }

  @override
  Future<MobileScheduleItem> createSchedule({
    required String accessToken,
    required String rangerId,
    required DateTime workDate,
    String note = '',
  }) async {
    createCallCount += 1;
    createAccessTokens.add(accessToken);
    onCreateCall?.call(createCallCount);
    lastCreateRangerId = rangerId;
    lastCreateWorkDate = workDate;
    lastCreateNote = note;

    if (createError != null &&
        (throwCreateErrorForCalls <= 0 ||
            createCallCount <= throwCreateErrorForCalls)) {
      throw createError!;
    }

    if (createCompleter != null) {
      await createCompleter!.future;
    }

    return MobileScheduleItem(
      scheduleId: 'sched-new',
      rangerId: rangerId,
      workDate: workDate.toIso8601String().split('T').first,
      note: note,
      updatedBy: 'leaderuser',
      createdAt: '2026-03-20T00:00:00Z',
      updatedAt: '2026-03-20T00:00:00Z',
    );
  }

  @override
  Future<MobileScheduleItem> updateSchedule({
    required String accessToken,
    required String scheduleId,
    required String rangerId,
    required DateTime workDate,
    String note = '',
  }) async {
    updateCallCount += 1;
    updateAccessTokens.add(accessToken);
    onUpdateCall?.call(updateCallCount);
    lastUpdateScheduleId = scheduleId;
    lastUpdateRangerId = rangerId;
    lastUpdateWorkDate = workDate;
    lastUpdateNote = note;

    if (updateError != null &&
        (throwUpdateErrorForCalls <= 0 ||
            updateCallCount <= throwUpdateErrorForCalls)) {
      throw updateError!;
    }

    return MobileScheduleItem(
      scheduleId: scheduleId,
      rangerId: rangerId,
      workDate: workDate.toIso8601String().split('T').first,
      note: note,
      updatedBy: 'leaderuser',
      createdAt: '2026-03-20T00:00:00Z',
      updatedAt: '2026-03-21T00:00:00Z',
    );
  }

  @override
  Future<void> deleteSchedule({
    required String accessToken,
    required String scheduleId,
  }) async {
    deleteCallCount += 1;
    deleteAccessTokens.add(accessToken);
    onDeleteCall?.call(deleteCallCount);
    lastDeletedScheduleId = scheduleId;

    if (deleteError != null &&
        (throwDeleteErrorForCalls <= 0 ||
            deleteCallCount <= throwDeleteErrorForCalls)) {
      throw deleteError!;
    }
  }
}

class _QueuedMobileScheduleApi implements MobileScheduleApi {
  final List<Completer<MobileScheduleListResult>> _queue;
  int fetchCallCount = 0;

  _QueuedMobileScheduleApi(this._queue);

  @override
  Future<MobileScheduleListResult> fetchSchedules({
    required String accessToken,
    DateTime? fromDay,
    DateTime? toDay,
    String? rangerId,
  }) {
    fetchCallCount += 1;
    if (_queue.isEmpty) {
      throw StateError('No queued schedule response completer');
    }
    return _queue.removeAt(0).future;
  }

  @override
  Future<MobileScheduleItem> createSchedule({
    required String accessToken,
    required String rangerId,
    required DateTime workDate,
    String note = '',
  }) {
    throw UnimplementedError('Not required for queued load test');
  }

  @override
  Future<MobileScheduleItem> updateSchedule({
    required String accessToken,
    required String scheduleId,
    required String rangerId,
    required DateTime workDate,
    String note = '',
  }) {
    throw UnimplementedError('Not required for queued load test');
  }

  @override
  Future<void> deleteSchedule({
    required String accessToken,
    required String scheduleId,
  }) {
    throw UnimplementedError('Not required for queued load test');
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
  group('ScheduleProvider role-aware behavior', () {
    test('ranger gets read-only schedule view and cannot write', () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-1',
              rangerId: 'rangeruser',
              workDate: '2026-03-20',
              note: 'Morning patrol',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T01:00:00Z',
              updatedAt: '2026-03-19T01:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      expect(provider.isReadOnly, isTrue);
      expect(provider.hasSchedules, isTrue);
      expect(provider.schedules.length, 1);
      expect(provider.loadError, isNull);

      final writeSuccess = await provider.createSchedule(
        authProvider: auth,
        rangerId: 'rangeruser',
        workDate: DateTime(2026, 3, 21),
        note: 'attempt',
      );

      expect(writeSuccess, isFalse);
      expect(provider.submitError, 'Leader role required');
      expect(fakeApi.createCallCount, 0);
    });

    test('defensively filters leaked ranger schedule rows', () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-1',
              rangerId: 'rangeruser',
              workDate: '2026-03-20',
              note: 'Mine',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T01:00:00Z',
              updatedAt: '2026-03-19T01:00:00Z',
            ),
            MobileScheduleItem(
              scheduleId: 'sched-2',
              rangerId: 'other-ranger',
              workDate: '2026-03-20',
              note: 'Leak',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T01:00:00Z',
              updatedAt: '2026-03-19T01:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      expect(provider.hasSchedules, isTrue);
      expect(provider.schedules.length, 1);
      expect(provider.schedules.first.rangerId, 'rangeruser');
      expect(provider.availableRangerIds, <String>['rangeruser']);
    });

    test('hides ranger schedules when effective ranger scope is missing',
        () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-1',
              rangerId: 'rangeruser',
              workDate: '2026-03-20',
              note: 'Mine',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T01:00:00Z',
              updatedAt: '2026-03-19T01:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      expect(provider.hasSchedules, isFalse);
      expect(provider.schedules, isEmpty);
    });

    test('leader can switch ranger filter for team and scoped views', () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-1',
              rangerId: 'ranger-a',
              workDate: '2026-03-20',
              note: 'A',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T01:00:00Z',
              updatedAt: '2026-03-19T01:00:00Z',
            ),
            MobileScheduleItem(
              scheduleId: 'sched-2',
              rangerId: 'ranger-b',
              workDate: '2026-03-21',
              note: 'B',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T02:00:00Z',
              updatedAt: '2026-03-19T02:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-2',
              rangerId: 'ranger-b',
              workDate: '2026-03-21',
              note: 'B',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T02:00:00Z',
              updatedAt: '2026-03-19T02:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: false,
            requestedRangerId: 'ranger-b',
            effectiveRangerId: 'ranger-b',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));
      await provider.selectRangerFilter(authProvider: auth, rangerId: 'ranger-b');

      expect(provider.isLeaderScope, isTrue);
      expect(provider.teamScope, isFalse);
      expect(provider.selectedRangerId, 'ranger-b');
      expect(provider.schedules.length, 1);
      expect(provider.schedules.first.rangerId, 'ranger-b');
      expect(provider.availableRangerIds, <String>['ranger-a', 'ranger-b']);
      expect(fakeApi.requestedRangerIds, <String?>[null, 'ranger-b']);
    });

    test('consumes schedule directory names and admin leader visibility',
        () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-1',
              rangerId: 'ranger-a',
              workDate: '2026-03-20',
              note: 'A',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T01:00:00Z',
              updatedAt: '2026-03-19T01:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            accountRole: 'admin',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
          directory: <MobileScheduleDirectoryUser>[
            MobileScheduleDirectoryUser(
              username: 'leader-z',
              displayName: 'Leader Z',
              role: 'leader',
            ),
            MobileScheduleDirectoryUser(
              username: 'ranger-b',
              displayName: 'Ranger B',
              role: 'ranger',
            ),
            MobileScheduleDirectoryUser(
              username: 'ranger-a',
              displayName: 'Ranger A',
              role: 'ranger',
            ),
          ],
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      expect(provider.canViewLeaderAssignments, isTrue);
      expect(
        provider.availableRangerIds.toSet(),
        <String>{'leader-z', 'ranger-a', 'ranger-b'},
      );
      expect(provider.rangerDisplayName('ranger-a'), 'Ranger A');
      expect(provider.rangerDisplayName('leader-z'), 'Leader Z');
      expect(provider.rangerDisplayName('unknown-id'), 'unknown-id');
    });

    test('ignores month navigation taps while schedule load is in progress',
        () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);
      fakeApi.fetchCompleter = Completer<void>();

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      final initialLoad = provider.loadSchedules(
        authProvider: auth,
        month: DateTime(2026, 3),
      );

      await provider.goToNextMonth(authProvider: auth);
      await provider.goToPreviousMonth(authProvider: auth);

      expect(fakeApi.fetchCallCount, 1);

      fakeApi.fetchCompleter!.complete();
      await initialLoad;
    });

    test('ignores stale out-of-order schedule responses', () async {
      final firstRequest = Completer<MobileScheduleListResult>();
      final secondRequest = Completer<MobileScheduleListResult>();
      final queuedApi = _QueuedMobileScheduleApi(
        <Completer<MobileScheduleListResult>>[firstRequest, secondRequest],
      );

      final provider = ScheduleProvider(scheduleApi: queuedApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      final marchLoad = provider.loadSchedules(
        authProvider: auth,
        month: DateTime(2026, 3, 1),
      );
      final aprilLoad = provider.loadSchedules(
        authProvider: auth,
        month: DateTime(2026, 4, 1),
      );

      secondRequest.complete(
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-april',
              rangerId: 'ranger-a',
              workDate: '2026-04-05',
              note: 'April row',
              updatedBy: 'leaderuser',
              createdAt: '2026-04-04T00:00:00Z',
              updatedAt: '2026-04-04T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-04-01',
          toDay: '2026-04-30',
        ),
      );
      await aprilLoad;

      firstRequest.complete(
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-march',
              rangerId: 'ranger-a',
              workDate: '2026-03-05',
              note: 'March row',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-04T00:00:00Z',
              updatedAt: '2026-03-04T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      );
      await marchLoad;

      expect(queuedApi.fetchCallCount, 2);
      expect(provider.focusedMonth, DateTime(2026, 4));
      expect(provider.schedules.length, 1);
      expect(provider.schedules.first.scheduleId, 'sched-april');
    });

    test('clears in-memory schedules immediately on session switch', () async {
      final firstRequest = Completer<MobileScheduleListResult>();
      final secondRequest = Completer<MobileScheduleListResult>();
      final queuedApi = _QueuedMobileScheduleApi(
        <Completer<MobileScheduleListResult>>[firstRequest, secondRequest],
      );

      final provider = ScheduleProvider(scheduleApi: queuedApi);
      final authA = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader-a',
          refreshToken: 'refresh-leader-a',
          role: 'leader',
        );
      final authB = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader-b',
          refreshToken: 'refresh-leader-b',
          role: 'leader',
        );

      final firstLoad = provider.loadSchedules(
        authProvider: authA,
        month: DateTime(2026, 3, 1),
      );

      firstRequest.complete(
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-session-a',
              rangerId: 'ranger-a',
              workDate: '2026-03-12',
              note: 'Session A row',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-11T00:00:00Z',
              updatedAt: '2026-03-11T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      );
      await firstLoad;

      expect(provider.schedules.length, 1);
      expect(provider.schedules.first.scheduleId, 'sched-session-a');

      final secondLoad = provider.loadSchedules(
        authProvider: authB,
        month: DateTime(2026, 4, 1),
      );

      expect(provider.schedules, isEmpty);

      secondRequest.complete(
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-session-b',
              rangerId: 'ranger-b',
              workDate: '2026-04-12',
              note: 'Session B row',
              updatedBy: 'leaderuser',
              createdAt: '2026-04-11T00:00:00Z',
              updatedAt: '2026-04-11T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-04-01',
          toDay: '2026-04-30',
        ),
      );
      await secondLoad;

      expect(provider.schedules.length, 1);
      expect(provider.schedules.first.scheduleId, 'sched-session-b');
    });

    test('superseded missing-token request resets schedule loading state',
        () async {
      final inFlightResponse = Completer<MobileScheduleListResult>();
      final queuedApi = _QueuedMobileScheduleApi(
        <Completer<MobileScheduleListResult>>[inFlightResponse],
      );

      final provider = ScheduleProvider(scheduleApi: queuedApi);
      final authWithToken = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      final inFlightLoad = provider.loadSchedules(
        authProvider: authWithToken,
        month: DateTime(2026, 3, 1),
      );

      final noTokenAuth = AuthProvider();
      await provider.loadSchedules(
        authProvider: noTokenAuth,
        month: DateTime(2026, 4, 1),
      );

      expect(provider.isLoading, isFalse);
      expect(provider.loadError, 'Missing mobile access token');

      inFlightResponse.complete(
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-stale',
              rangerId: 'ranger-a',
              workDate: '2026-03-05',
              note: 'stale row',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-04T00:00:00Z',
              updatedAt: '2026-03-04T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      );
      await inFlightLoad;

      expect(provider.isLoading, isFalse);
      expect(provider.loadError, 'Missing mobile access token');
      expect(provider.schedules, isEmpty);
    });

    test('leader write validates fields and refreshes on create success', () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-new',
              rangerId: 'ranger-a',
              workDate: '2026-03-25',
              note: 'night patrol',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-20T00:00:00Z',
              updatedAt: '2026-03-20T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      final missingRanger = await provider.createSchedule(
        authProvider: auth,
        rangerId: '',
        workDate: DateTime(2026, 3, 25),
        note: 'x',
      );
      expect(missingRanger, isFalse);
      expect(provider.submitError, 'ranger_id and work_date required');
      expect(fakeApi.createCallCount, 0);

      final missingDate = await provider.createSchedule(
        authProvider: auth,
        rangerId: 'ranger-a',
        workDate: null,
        note: 'x',
      );
      expect(missingDate, isFalse);
      expect(provider.submitError, 'ranger_id and work_date required');
      expect(fakeApi.createCallCount, 0);

      final success = await provider.createSchedule(
        authProvider: auth,
        rangerId: 'ranger-a',
        workDate: DateTime(2026, 3, 25),
        note: ' night patrol ',
      );

      expect(success, isTrue);
      expect(provider.submitError, isNull);
      expect(fakeApi.createCallCount, 1);
      expect(fakeApi.lastCreateRangerId, 'ranger-a');
      expect(fakeApi.lastCreateNote, 'night patrol');
      expect(provider.schedules.length, 1);
      expect(provider.schedules.first.scheduleId, 'sched-new');
      expect(fakeApi.fetchCallCount, 2); // initial load + post-write refresh
    });

    test('leader update surfaces server errors', () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-7',
              rangerId: 'ranger-a',
              workDate: '2026-03-24',
              note: 'old',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T00:00:00Z',
              updatedAt: '2026-03-19T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);
      fakeApi.updateError = MobileApiException(500, 'boom');

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      final success = await provider.updateSchedule(
        authProvider: auth,
        scheduleId: 'sched-7',
        rangerId: 'ranger-b',
        workDate: DateTime(2026, 3, 26),
        note: 'new',
      );

      expect(success, isFalse);
      expect(fakeApi.updateCallCount, 1);
      expect(provider.submitError, 'Schedule service is temporarily unavailable');
    });

    test('admin can delete schedule and refreshes list', () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-7',
              rangerId: 'ranger-a',
              workDate: '2026-03-24',
              note: 'old',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T00:00:00Z',
              updatedAt: '2026-03-19T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            accountRole: 'admin',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[],
          scope: MobileScheduleScope(
            role: 'leader',
            accountRole: 'admin',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-admin',
          refreshToken: 'refresh-admin',
          role: 'leader',
          username: 'leaderuser',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      expect(provider.canDeleteSchedules, isTrue);

      final success = await provider.deleteSchedule(
        authProvider: auth,
        scheduleId: 'sched-7',
      );

      expect(success, isTrue);
      expect(provider.submitError, isNull);
      expect(fakeApi.deleteCallCount, 1);
      expect(fakeApi.lastDeletedScheduleId, 'sched-7');
      expect(fakeApi.fetchCallCount, 2); // initial load + post-delete refresh
      expect(provider.schedules, isEmpty);
    });

    test('leader without admin role cannot delete schedule', () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-7',
              rangerId: 'ranger-a',
              workDate: '2026-03-24',
              note: 'old',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T00:00:00Z',
              updatedAt: '2026-03-19T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            accountRole: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
          username: 'fieldleader',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      expect(provider.canDeleteSchedules, isFalse);

      final success = await provider.deleteSchedule(
        authProvider: auth,
        scheduleId: 'sched-7',
      );

      expect(success, isFalse);
      expect(provider.submitError, 'Admin role required');
      expect(fakeApi.deleteCallCount, 0);
    });

    test('blocks concurrent leader submissions to prevent duplicate writes', () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-new',
              rangerId: 'ranger-a',
              workDate: '2026-03-25',
              note: 'night patrol',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-20T00:00:00Z',
              updatedAt: '2026-03-20T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);
      fakeApi.createCompleter = Completer<void>();

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      final firstSubmit = provider.createSchedule(
        authProvider: auth,
        rangerId: 'ranger-a',
        workDate: DateTime(2026, 3, 25),
        note: 'night patrol',
      );

      final secondSubmit = await provider.createSchedule(
        authProvider: auth,
        rangerId: 'ranger-a',
        workDate: DateTime(2026, 3, 25),
        note: 'duplicate attempt',
      );

      expect(secondSubmit, isFalse);
      expect(provider.submitError, 'Schedule submission in progress');
      expect(fakeApi.createCallCount, 1);

      fakeApi.createCompleter!.complete();
      final firstSubmitResult = await firstSubmit;

      expect(firstSubmitResult, isTrue);
      expect(fakeApi.createCallCount, 1);
    });

    test('load error states include missing token and API failure', () async {
      final fakeApi = _FakeMobileScheduleApi(const <MobileScheduleListResult>[]);
      final provider = ScheduleProvider(scheduleApi: fakeApi);
      final noSessionAuth = AuthProvider();

      await provider.loadSchedules(
        authProvider: noSessionAuth,
        month: DateTime(2026, 3),
      );

      expect(provider.loadError, 'Missing mobile access token');
      expect(provider.hasSchedules, isFalse);

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );
      fakeApi.fetchError = MobileApiException(500, 'failed load');

      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      expect(provider.loadError, 'Schedule service is temporarily unavailable');
      expect(provider.hasSchedules, isFalse);
    });

    test('uses cached schedules when refresh fails and marks offline state',
        () async {
      final cache = _InMemoryReadModelCache();
      await cache.saveSchedules(
        cacheKey:
            'month=2026-03|role=ranger|ranger=all|session=${_sessionPartition('refresh-ranger')}',
        value: const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-cached',
              rangerId: 'rangeruser',
              workDate: '2026-03-20',
              note: 'cached note',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T00:00:00Z',
              updatedAt: '2026-03-19T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        syncedAt: DateTime.utc(2026, 3, 19, 0),
      );

      final fakeApi = _FakeMobileScheduleApi(const <MobileScheduleListResult>[])
        ..fetchError = MobileApiException(503, 'network down');

      final provider = ScheduleProvider(scheduleApi: fakeApi, cache: cache);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadSchedules(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );

      expect(provider.hasSchedules, isTrue);
      expect(provider.loadError, isNull);
      expect(provider.refreshError, 'Schedule service is temporarily unavailable');
      expect(provider.isOfflineFallback, isTrue);
      expect(provider.isStaleData, isTrue);
    });

    test('merges reconnect schedule payload by schedule_id without duplicates',
        () async {
      final cache = _InMemoryReadModelCache();
      await cache.saveSchedules(
        cacheKey:
            'month=2026-03|role=leader|ranger=all|session=${_sessionPartition('refresh-leader')}',
        value: const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-1',
              rangerId: 'ranger-a',
              workDate: '2026-03-20',
              note: 'old note',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T00:00:00Z',
              updatedAt: '2026-03-19T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        syncedAt: DateTime.utc(2026, 3, 19, 0),
      );

      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-1',
              rangerId: 'ranger-a',
              workDate: '2026-03-20',
              note: 'new note',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T00:00:00Z',
              updatedAt: '2026-03-20T00:00:00Z',
            ),
            MobileScheduleItem(
              scheduleId: 'sched-2',
              rangerId: 'ranger-b',
              workDate: '2026-03-21',
              note: 'added',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-20T00:00:00Z',
              updatedAt: '2026-03-20T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi, cache: cache);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadSchedules(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );

      expect(provider.schedules.where((item) => item.scheduleId == 'sched-1').length, 1);
      expect(provider.schedules.where((item) => item.scheduleId == 'sched-2').length, 1);
      expect(
        provider.schedules.firstWhere((item) => item.scheduleId == 'sched-1').note,
        'new note',
      );
      expect(provider.refreshError, isNull);
      expect(provider.isOfflineFallback, isFalse);
    });

    test('authoritative month refresh drops stale cached schedules', () async {
      final cache = _InMemoryReadModelCache();
      await cache.saveSchedules(
        cacheKey:
            'month=2026-03|role=leader|ranger=all|session=${_sessionPartition('refresh-leader')}',
        value: const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-stale',
              rangerId: 'ranger-a',
              workDate: '2026-03-08',
              note: 'stale cached row',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-07T00:00:00Z',
              updatedAt: '2026-03-07T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        syncedAt: DateTime.utc(2026, 3, 7, 0),
      );

      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-live',
              rangerId: 'ranger-b',
              workDate: '2026-03-22',
              note: 'authoritative row',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-21T00:00:00Z',
              updatedAt: '2026-03-21T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi, cache: cache);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadSchedules(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );

      expect(provider.schedules.length, 1);
      expect(provider.schedules.first.scheduleId, 'sched-live');
      expect(
        provider.schedules.any((item) => item.scheduleId == 'sched-stale'),
        isFalse,
      );
      expect(provider.refreshError, isNull);
    });

    test('does not widen ranger scope from stale admin login state',
        () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-ranger',
              rangerId: 'rangeruser',
              workDate: '2026-03-20',
              note: 'own row',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T00:00:00Z',
              updatedAt: '2026-03-19T00:00:00Z',
            ),
            MobileScheduleItem(
              scheduleId: 'sched-other',
              rangerId: 'other-ranger',
              workDate: '2026-03-20',
              note: 'other row',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T00:00:00Z',
              updatedAt: '2026-03-19T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
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

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      expect(provider.scopeRole, 'ranger');
      expect(provider.schedules.length, 1);
      expect(provider.schedules.first.rangerId, 'rangeruser');
      expect(provider.availableRangerIds, <String>['rangeruser']);
    });

    test('retries schedule fetch once after token refresh on unauthorized',
        () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-retry',
              rangerId: 'rangeruser',
              workDate: '2026-03-25',
              note: 'retry success',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-24T00:00:00Z',
              updatedAt: '2026-03-24T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'rangeruser',
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ])
        ..fetchError = MobileApiException(401, 'expired')
        ..throwFetchErrorForCalls = 1;

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-old',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      fakeApi.onFetchCall = (callCount) {
        if (callCount == 1) {
          auth.setMobileSession(
            accessToken: 'token-new',
            refreshToken: 'refresh-ranger',
            role: 'ranger',
            username: 'rangeruser',
          );
        }
      };

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      expect(fakeApi.fetchCallCount, 2);
      expect(fakeApi.fetchAccessTokens, <String>['token-old', 'token-new']);
      expect(provider.hasSchedules, isTrue);
      expect(provider.loadError, isNull);
    });

    test('retries schedule create once after token refresh on unauthorized',
        () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-new',
              rangerId: 'ranger-a',
              workDate: '2026-03-25',
              note: 'night patrol',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-20T00:00:00Z',
              updatedAt: '2026-03-20T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ])
        ..createError = MobileApiException(401, 'expired')
        ..throwCreateErrorForCalls = 1;

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-old',
          refreshToken: 'refresh-leader',
          role: 'leader',
          username: 'leaderuser',
        );

      fakeApi.onCreateCall = (callCount) {
        if (callCount == 1) {
          auth.setMobileSession(
            accessToken: 'token-new',
            refreshToken: 'refresh-leader',
            role: 'leader',
            username: 'leaderuser',
          );
        }
      };

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      final success = await provider.createSchedule(
        authProvider: auth,
        rangerId: 'ranger-a',
        workDate: DateTime(2026, 3, 25),
        note: 'night patrol',
      );

      expect(success, isTrue);
      expect(fakeApi.createCallCount, 2);
      expect(fakeApi.createAccessTokens, <String>['token-old', 'token-new']);
      expect(provider.submitError, isNull);
    });

    test('retries schedule delete once after token refresh on unauthorized',
        () async {
      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: 'sched-delete',
              rangerId: 'ranger-a',
              workDate: '2026-03-25',
              note: 'delete me',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-20T00:00:00Z',
              updatedAt: '2026-03-20T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            accountRole: 'admin',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[],
          scope: MobileScheduleScope(
            role: 'leader',
            accountRole: 'admin',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ])
        ..deleteError = MobileApiException(401, 'expired')
        ..throwDeleteErrorForCalls = 1;

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-old',
          refreshToken: 'refresh-admin',
          role: 'leader',
          username: 'leaderuser',
        );

      fakeApi.onDeleteCall = (callCount) {
        if (callCount == 1) {
          auth.setMobileSession(
            accessToken: 'token-new',
            refreshToken: 'refresh-admin',
            role: 'leader',
            username: 'leaderuser',
          );
        }
      };

      final provider = ScheduleProvider(scheduleApi: fakeApi);
      await provider.loadSchedules(authProvider: auth, month: DateTime(2026, 3));

      final success = await provider.deleteSchedule(
        authProvider: auth,
        scheduleId: 'sched-delete',
      );

      expect(success, isTrue);
      expect(fakeApi.deleteCallCount, 2);
      expect(fakeApi.deleteAccessTokens, <String>['token-old', 'token-new']);
      expect(provider.submitError, isNull);
    });

    test(
      'authoritative refresh replaces cached fallback rows when schedule_id is missing',
      () async {
      final cache = _InMemoryReadModelCache();
      await cache.saveSchedules(
        cacheKey:
            'month=2026-03|role=leader|ranger=all|session=${_sessionPartition('refresh-leader')}',
        value: const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: '',
              rangerId: 'ranger-a',
              workDate: '2026-03-20',
              note: 'first',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T00:00:00Z',
              updatedAt: '2026-03-19T00:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        syncedAt: DateTime.utc(2026, 3, 19, 0),
      );

      final fakeApi = _FakeMobileScheduleApi([
        const MobileScheduleListResult(
          items: <MobileScheduleItem>[
            MobileScheduleItem(
              scheduleId: ' ',
              rangerId: 'ranger-a',
              workDate: '2026-03-20',
              note: 'second',
              updatedBy: 'leaderuser',
              createdAt: '2026-03-19T05:00:00Z',
              updatedAt: '2026-03-19T05:00:00Z',
            ),
          ],
          scope: MobileScheduleScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = ScheduleProvider(scheduleApi: fakeApi, cache: cache);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadSchedules(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );

      expect(provider.schedules.length, 1);
      expect(
        provider.schedules.map((item) => item.note.trim()).toSet(),
        <String>{'second'},
      );
      expect(provider.refreshError, isNull);
    });
  });
}
