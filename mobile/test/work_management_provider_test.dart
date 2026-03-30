import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treeinfo_dart/providers/auth_provider.dart';
import 'package:treeinfo_dart/providers/work_management_provider.dart';
import 'package:treeinfo_dart/services/mobile_api_service.dart';
import 'package:treeinfo_dart/services/mobile_checkin_queue.dart';
import 'package:treeinfo_dart/services/mobile_read_model_cache.dart';

String _sessionPartition(String seed) {
  return 'u${sha256.convert(utf8.encode(seed))}';
}

class _FakeMobileCheckinApi implements MobileCheckinApi {
  int callCount = 0;
  final List<MobileCheckinResult> _responses;
  final List<String> submittedAccessTokens = <String>[];
  final List<String> submittedIdempotencyKeys = <String>[];
  final List<String> submittedClientTimes = <String>[];
  final List<String> submittedTimezones = <String>[];
  final List<String> submittedAppVersions = <String>[];

  _FakeMobileCheckinApi(this._responses);

  @override
  Future<MobileCheckinResult> submitAppOpenCheckin({
    required String accessToken,
    String idempotencyKey = '',
    String clientTime = '',
    String timezone = '',
    String appVersion = '',
  }) async {
    callCount += 1;
    submittedAccessTokens.add(accessToken);
    submittedIdempotencyKeys.add(idempotencyKey);
    submittedClientTimes.add(clientTime);
    submittedTimezones.add(timezone);
    submittedAppVersions.add(appVersion);
    if (_responses.isEmpty) {
      return const MobileCheckinResult(
        status: 'already_exists',
        dayKey: '',
        serverTime: '2026-03-20T00:00:00Z',
        timezone: 'Asia/Ho_Chi_Minh',
        idempotencyKey: '',
      );
    }
    return _responses.removeAt(0);
  }
}

class _SequenceMobileCheckinApi implements MobileCheckinApi {
  int callCount = 0;
  final List<Object> _steps;
  final List<String> submittedAccessTokens = <String>[];
  final List<String> submittedIdempotencyKeys = <String>[];
  final List<String> submittedClientTimes = <String>[];
  final List<String> submittedTimezones = <String>[];
  final List<String> submittedAppVersions = <String>[];
  void Function(int callCount)? onSubmitCall;

  _SequenceMobileCheckinApi(this._steps);

  @override
  Future<MobileCheckinResult> submitAppOpenCheckin({
    required String accessToken,
    String idempotencyKey = '',
    String clientTime = '',
    String timezone = '',
    String appVersion = '',
  }) async {
    callCount += 1;
    submittedAccessTokens.add(accessToken);
    submittedIdempotencyKeys.add(idempotencyKey);
    submittedClientTimes.add(clientTime);
    submittedTimezones.add(timezone);
    submittedAppVersions.add(appVersion);
    onSubmitCall?.call(callCount);
    if (_steps.isEmpty) {
      throw StateError('No sequence step available');
    }

    final step = _steps.removeAt(0);
    if (step is MobileCheckinResult) {
      return step;
    }
    if (step is Completer<MobileCheckinResult>) {
      return step.future;
    }
    if (step is Future<MobileCheckinResult>) {
      return await step;
    }
    if (step is Exception) {
      throw step;
    }
    if (step is Error) {
      throw step;
    }
    throw StateError('Unsupported checkin sequence step: $step');
  }
}

class _FakeMobileWorkSummaryApi implements MobileWorkSummaryApi {
  int callCount = 0;
  final List<String> requestedAccessTokens = <String>[];
  final List<String?> requestedRangerIds = <String?>[];
  final List<int> requestedPages = <int>[];
  final List<MobileWorkSummaryResult> _responses;
  Object? errorToThrow;
  int throwErrorForCalls = 0;
  void Function(int callCount)? onFetchCall;

  _FakeMobileWorkSummaryApi(this._responses, {this.errorToThrow});

  @override
  Future<MobileWorkSummaryResult> fetchWorkSummary({
    required String accessToken,
    required DateTime fromDay,
    required DateTime toDay,
    String? rangerId,
    int page = 1,
    int pageSize = 62,
  }) async {
    callCount += 1;
    requestedAccessTokens.add(accessToken);
    requestedRangerIds.add(rangerId);
    requestedPages.add(page);
    onFetchCall?.call(callCount);

    if (errorToThrow != null &&
        (throwErrorForCalls <= 0 || callCount <= throwErrorForCalls)) {
      throw errorToThrow!;
    }

    if (_responses.isEmpty) {
      return const MobileWorkSummaryResult(
        items: <MobileWorkSummaryItem>[],
        scope: MobileWorkScope(
          role: 'ranger',
          teamScope: false,
          requestedRangerId: null,
          effectiveRangerId: 'ranger-default',
        ),
        pagination: MobileWorkPagination(
          page: 1,
          pageSize: 62,
          total: 0,
          totalPages: 0,
        ),
        fromDay: '2026-03-01',
        toDay: '2026-03-31',
      );
    }

    return _responses.removeAt(0);
  }
}

class _QueuedMobileWorkSummaryApi implements MobileWorkSummaryApi {
  int callCount = 0;
  final List<String?> requestedRangerIds = <String?>[];
  final List<Completer<MobileWorkSummaryResult>> _queue;

  _QueuedMobileWorkSummaryApi(this._queue);

  @override
  Future<MobileWorkSummaryResult> fetchWorkSummary({
    required String accessToken,
    required DateTime fromDay,
    required DateTime toDay,
    String? rangerId,
    int page = 1,
    int pageSize = 62,
  }) {
    callCount += 1;
    requestedRangerIds.add(rangerId);
    if (_queue.isEmpty) {
      throw StateError('No queued response completer');
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

class _InMemoryCheckinQueueStore implements MobileCheckinQueueStore {
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> loadQueueItems() async {
    return _records
        .map((record) => Map<String, dynamic>.from(record))
        .toList(growable: false);
  }

  @override
  Future<void> saveQueueItems(List<Map<String, dynamic>> records) async {
    _records = records
        .map((record) => Map<String, dynamic>.from(record))
        .toList(growable: false);
  }
}

class _ThrowingReadModelCache implements MobileReadModelCache {
  final bool throwOnLoadWorkSummary;
  final bool throwOnSaveWorkSummary;

  _ThrowingReadModelCache({
    this.throwOnLoadWorkSummary = false,
    this.throwOnSaveWorkSummary = false,
  });

  @override
  Future<CachedReadModel<MobileWorkSummaryResult>?> loadWorkSummary(
    String cacheKey,
  ) async {
    if (throwOnLoadWorkSummary) {
      throw StateError('load failed');
    }
    return null;
  }

  @override
  Future<void> saveWorkSummary({
    required String cacheKey,
    required MobileWorkSummaryResult value,
    required DateTime syncedAt,
  }) async {
    if (throwOnSaveWorkSummary) {
      throw StateError('save failed');
    }
  }

  @override
  Future<CachedReadModel<MobileIncidentListResult>?> loadIncidents(
    String cacheKey,
  ) async {
    return null;
  }

  @override
  Future<void> saveIncidents({
    required String cacheKey,
    required MobileIncidentListResult value,
    required DateTime syncedAt,
  }) async {}

  @override
  Future<CachedReadModel<MobileScheduleListResult>?> loadSchedules(
    String cacheKey,
  ) async {
    return null;
  }

  @override
  Future<void> saveSchedules({
    required String cacheKey,
    required MobileScheduleListResult value,
    required DateTime syncedAt,
  }) async {}
}

void main() {
  group('WorkManagementProvider app-open checkin trigger', () {
    test('runs auto-checkin for ranger session and updates day indicator', () async {
      final fakeApi = _FakeMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-20T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);
      final provider = WorkManagementProvider(mobileCheckinApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-1',
          refreshToken: 'refresh-1',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(fakeApi.callCount, 1);
      expect(provider.lastCheckinStatus, 'created');
      expect(provider.lastCheckinDayKey, isNotEmpty);
      expect(
        provider.lastCheckinDayKey,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
      expect(provider.checkinError, isNull);
    });

    test('repeated same-day app-open trigger keeps stable indicator state', () async {
      final fakeApi = _FakeMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-20T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
        const MobileCheckinResult(
          status: 'already_exists',
          dayKey: '',
          serverTime: '2026-03-20T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);
      final provider = WorkManagementProvider(mobileCheckinApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-1',
          refreshToken: 'refresh-1',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);
      final firstDayKey = provider.lastCheckinDayKey;
      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(fakeApi.callCount, 2);
      expect(firstDayKey, isNotNull);
      expect(provider.lastCheckinDayKey, firstDayKey);
      expect(provider.lastCheckinStatus, 'already_exists');
      expect(provider.checkinError, isNull);
    });

    test('no-op for non-ranger or missing mobile session', () async {
      final fakeApi = _FakeMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-20T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);
      final provider = WorkManagementProvider(mobileCheckinApi: fakeApi);

      final noSessionAuth = AuthProvider();
      await provider.triggerAppOpenCheckin(authProvider: noSessionAuth);
      expect(fakeApi.callCount, 0);

      final leaderAuth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-2',
          refreshToken: 'refresh-2',
          role: 'leader',
        );
      await provider.triggerAppOpenCheckin(authProvider: leaderAuth);
      expect(fakeApi.callCount, 0);

      final whitespaceTokenAuth = AuthProvider()
        ..setMobileSession(
          accessToken: '   ',
          refreshToken: 'refresh-3',
          role: 'ranger',
          username: 'rangeruser',
        );
      await provider.triggerAppOpenCheckin(authProvider: whitespaceTokenAuth);
      expect(fakeApi.callCount, 0);
      expect(provider.checkinError, isNull);
      expect(provider.isSyncingCheckin, isFalse);
    });

    test('clears previous checkin state when session is non-ranger', () async {
      final fakeApi = _FakeMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-20T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);
      final provider = WorkManagementProvider(mobileCheckinApi: fakeApi);

      final rangerAuth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: rangerAuth);
      expect(provider.lastCheckinDayKey, isNotNull);

      final leaderAuth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.triggerAppOpenCheckin(authProvider: leaderAuth);

      expect(provider.lastCheckinDayKey, isNull);
      expect(provider.lastCheckinStatus, isNull);
      expect(provider.lastCheckinServerTime, isNull);
    });

    test('failed checkin clears stale success status', () async {
      final fakeApi = _SequenceMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-20T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
        MobileApiException(500, 'boom'),
      ]);
      final provider = WorkManagementProvider(mobileCheckinApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);
      expect(provider.lastCheckinStatus, 'created');

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(provider.lastCheckinStatus, isNull);
      expect(provider.lastCheckinDayKey, isNull);
      expect(provider.lastCheckinServerTime, isNull);
      expect(provider.checkinError, 'Unable to sync check-in right now.');
    });

    test('falls back to computed project day key when server day key is empty', () async {
      final fakeApi = _FakeMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-20T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);
      final provider = WorkManagementProvider(mobileCheckinApi: fakeApi);
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-1',
          refreshToken: 'refresh-1',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(provider.lastCheckinStatus, 'created');
      expect(provider.lastCheckinDayKey, isNotEmpty);
      expect(
        provider.lastCheckinDayKey,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
    });

    test('retries direct checkin once when access token rotates on 401',
        () async {
      final fakeApi = _SequenceMobileCheckinApi([
        MobileApiException(401, 'expired'),
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-20T00:03:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-old',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      fakeApi.onSubmitCall = (callCount) {
        if (callCount == 1) {
          auth.setMobileSession(
            accessToken: 'token-new',
            refreshToken: 'refresh-ranger',
            role: 'ranger',
            username: 'rangeruser',
          );
        }
      };

      final provider = WorkManagementProvider(mobileCheckinApi: fakeApi);

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(fakeApi.callCount, 2);
      expect(fakeApi.submittedAccessTokens, <String>['token-old', 'token-new']);
      expect(provider.lastCheckinStatus, 'created');
      expect(provider.checkinError, isNull);
    });

    test('keeps pending status and skips fresh submit when day already queued',
        () async {
      final nowUtc = DateTime.utc(2026, 3, 24, 3, 0, 0);
      final dayKey = MobileCheckinReplayQueue.projectDayKeyFromUtc(nowUtc);

      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        nowUtc: () => nowUtc,
        jitterSource: () => 0,
      );

      final queued = await replayQueue.enqueueCheckin(
        userId: 'rangeruser',
        dayKey: dayKey,
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      await replayQueue.markReplayFailure(
        queueId: queued.queueId,
        errorMessage: 'retry later',
      );

      final fakeApi = _FakeMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-24T00:10:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(fakeApi.callCount, 0);
      expect(provider.lastCheckinStatus, MobileCheckinQueueStatus.pending);
      expect(provider.lastCheckinDayKey, dayKey);
      expect(provider.pendingCheckinCount, 1);
      expect(provider.checkinError, isNull);
    });

    test('queues checkin as pending when transient failure occurs', () async {
      final fakeApi = _SequenceMobileCheckinApi([
        MobileApiException(503, 'temporary upstream error'),
      ]);
      final queueStore = _InMemoryCheckinQueueStore();
      final replayQueue = MobileCheckinReplayQueue(
        store: queueStore,
        nowUtc: () => DateTime.utc(2026, 3, 24, 1, 0, 0),
        jitterSource: () => 0,
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(provider.lastCheckinStatus, 'pending');
      expect(provider.checkinError, isNull);
      expect(provider.pendingCheckinCount, 1);
      expect(provider.failedCheckinCount, 0);

      final queuedItems = await replayQueue.listItems();
      expect(queuedItems.length, 1);
      expect(queuedItems.first.status, MobileCheckinQueueStatus.pending);
      expect(
        queuedItems.first.idempotencyKey,
        startsWith('rangeruser:checkin:${queuedItems.first.dayKey}:'),
      );
      expect(fakeApi.submittedTimezones, <String>['Asia/Ho_Chi_Minh']);
      expect(fakeApi.submittedAppVersions, <String>['1.0.0']);
    });

    test('does not enqueue checkin when auth failure is returned', () async {
      final fakeApi = _SequenceMobileCheckinApi([
        MobileApiException(401, 'expired token'),
      ]);
      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        nowUtc: () => DateTime.utc(2026, 3, 24, 2, 0, 0),
        jitterSource: () => 0,
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(provider.lastCheckinStatus, isNull);
      expect(provider.pendingCheckinCount, 0);
      expect(provider.checkinError, 'Session expired. Please sign in again.');
      expect(await replayQueue.listItems(), isEmpty);
    });

    test('replays queued checkin idempotently on next trigger', () async {
      final fakeApi = _SequenceMobileCheckinApi([
        MobileApiException(503, 'network failure'),
        const MobileCheckinResult(
          status: 'already_exists',
          dayKey: '',
          serverTime: '2026-03-24T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-24T00:02:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);

      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        nowUtc: () => DateTime.utc(2026, 3, 24, 3, 0, 0),
        jitterSource: () => 0,
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);
      expect(provider.pendingCheckinCount, 1);

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(fakeApi.callCount, 3);
      expect(provider.pendingCheckinCount, 0);
      expect(provider.lastCheckinStatus, 'created');

      final queuedItems = await replayQueue.listItems();
      expect(queuedItems.length, 1);
      expect(queuedItems.first.status, MobileCheckinQueueStatus.synced);

      expect(fakeApi.submittedIdempotencyKeys.length, 3);
      expect(fakeApi.submittedIdempotencyKeys[0], isNotEmpty);
      expect(fakeApi.submittedIdempotencyKeys[1], fakeApi.submittedIdempotencyKeys[0]);
      expect(
        fakeApi.submittedIdempotencyKeys[2],
        isNot(equals(fakeApi.submittedIdempotencyKeys[0])),
      );
    });

    test('replay day-key mismatch blocks fresh submit and keeps queue pending',
        () async {
      final fakeApi = _SequenceMobileCheckinApi([
        MobileApiException(503, 'network failure'),
        const MobileCheckinResult(
          status: 'already_exists',
          dayKey: '2099-01-01',
          serverTime: '2026-03-24T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
        const MobileCheckinResult(
          status: 'created',
          dayKey: '2026-03-24',
          serverTime: '2026-03-24T00:02:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);

      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        nowUtc: () => DateTime.utc(2026, 3, 24, 3, 0, 0),
        jitterSource: () => 0,
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);
      expect(provider.pendingCheckinCount, 1);

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(fakeApi.callCount, 2);
      expect(provider.pendingCheckinCount, 1);
      expect(provider.checkinError, 'Unable to verify replayed check-in day key.');
      expect(provider.lastCheckinStatus, MobileCheckinQueueStatus.pending);
    });

    test(
      'replay idempotency mismatch blocks fresh submit and keeps queue pending',
      () async {
        final fakeApi = _SequenceMobileCheckinApi([
          MobileApiException(503, 'network failure'),
          const MobileCheckinResult(
            status: 'already_exists',
            dayKey: '',
            serverTime: '2026-03-24T00:01:00Z',
            timezone: 'Asia/Ho_Chi_Minh',
            idempotencyKey: 'rangeruser:checkin:2026-03-24:unexpected-client',
          ),
          const MobileCheckinResult(
            status: 'created',
            dayKey: '2026-03-24',
            serverTime: '2026-03-24T00:02:00Z',
            timezone: 'Asia/Ho_Chi_Minh',
            idempotencyKey: '',
          ),
        ]);

        final replayQueue = MobileCheckinReplayQueue(
          store: _InMemoryCheckinQueueStore(),
          nowUtc: () => DateTime.utc(2026, 3, 24, 3, 0, 0),
          jitterSource: () => 0,
        );

        final provider = WorkManagementProvider(
          mobileCheckinApi: fakeApi,
          checkinQueue: replayQueue,
        );

        final auth = AuthProvider()
          ..setMobileSession(
            accessToken: 'token-ranger',
            refreshToken: 'refresh-ranger',
            role: 'ranger',
            username: 'rangeruser',
          );

        await provider.triggerAppOpenCheckin(authProvider: auth);
        expect(provider.pendingCheckinCount, 1);

        await provider.triggerAppOpenCheckin(authProvider: auth);

        expect(fakeApi.callCount, 2);
        expect(provider.pendingCheckinCount, 1);
        expect(
          provider.checkinError,
          'Unable to verify replayed check-in identity.',
        );
        expect(provider.lastCheckinStatus, MobileCheckinQueueStatus.pending);
      },
    );

    test('unexpected replay status blocks fresh submit and keeps queue pending',
        () async {
      final fakeApi = _SequenceMobileCheckinApi([
        MobileApiException(503, 'network failure'),
        const MobileCheckinResult(
          status: 'accepted',
          dayKey: '',
          serverTime: '2026-03-24T00:01:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
        const MobileCheckinResult(
          status: 'created',
          dayKey: '2026-03-24',
          serverTime: '2026-03-24T00:02:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);

      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        nowUtc: () => DateTime.utc(2026, 3, 24, 3, 0, 0),
        jitterSource: () => 0,
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);
      expect(provider.pendingCheckinCount, 1);

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(fakeApi.callCount, 2);
      expect(provider.pendingCheckinCount, 1);
      expect(provider.checkinError, 'Unable to verify replayed check-in status.');
      expect(provider.lastCheckinStatus, MobileCheckinQueueStatus.pending);
    });

    test('unexpected direct-submit status is rejected and not queued',
        () async {
      final fakeApi = _FakeMobileCheckinApi([
        const MobileCheckinResult(
          status: 'accepted',
          dayKey: '2026-03-24',
          serverTime: '2026-03-24T00:02:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: 'unexpected-status',
        ),
      ]);
      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        nowUtc: () => DateTime.utc(2026, 3, 24, 3, 30, 0),
        jitterSource: () => 0,
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(provider.lastCheckinStatus, isNull);
      expect(provider.pendingCheckinCount, 0);
      expect(provider.checkinError, 'Unable to sync check-in right now.');
      expect(await replayQueue.listItems(userId: 'rangeruser'), isEmpty);
    });

    test('unexpected direct-submit day key is rejected and not queued',
        () async {
      final fakeApi = _FakeMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '2099-01-01',
          serverTime: '2026-03-24T00:02:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: 'direct-day-mismatch',
        ),
      ]);
      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        nowUtc: () => DateTime.utc(2026, 3, 24, 3, 30, 0),
        jitterSource: () => 0,
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(provider.lastCheckinStatus, isNull);
      expect(provider.pendingCheckinCount, 0);
      expect(provider.checkinError, 'Unable to sync check-in right now.');
      expect(await replayQueue.listItems(userId: 'rangeruser'), isEmpty);
    });

    test('canonical direct-submit idempotency mismatch is rejected', () async {
      final fakeApi = _FakeMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '',
          serverTime: '2026-03-24T00:02:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: 'rangeruser:checkin:2000-01-01:unexpected-client',
        ),
      ]);
      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        nowUtc: () => DateTime.utc(2026, 3, 24, 3, 30, 0),
        jitterSource: () => 0,
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(provider.lastCheckinStatus, isNull);
      expect(provider.pendingCheckinCount, 0);
      expect(provider.checkinError, 'Unable to sync check-in right now.');
      expect(await replayQueue.listItems(userId: 'rangeruser'), isEmpty);
    });

    test('refreshCheckinSyncStatus only exposes active user queue items',
        () async {
      var queueIdCounter = 0;
      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        maxAttempts: 1,
        nowUtc: () => DateTime.utc(2026, 3, 25, 0, 0, 0),
        jitterSource: () => 0,
        uuidGenerator: () {
          queueIdCounter += 1;
          return 'refresh-sync-queue-$queueIdCounter';
        },
      );

      final itemA = await replayQueue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-25',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      await replayQueue.markReplayFailure(
        queueId: itemA.queueId,
        errorMessage: 'offline-a',
      );

      final itemB = await replayQueue.enqueueCheckin(
        userId: 'ranger-b',
        dayKey: '2026-03-26',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      await replayQueue.markReplayFailure(
        queueId: itemB.queueId,
        errorMessage: 'offline-b',
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: _FakeMobileCheckinApi(const <MobileCheckinResult>[]),
        checkinQueue: replayQueue,
      );

      final rangerAAuth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger-a',
          refreshToken: 'refresh-ranger-a',
          role: 'ranger',
          username: 'ranger-a',
        );

      await provider.refreshCheckinSyncStatus(authProvider: rangerAAuth);
      expect(provider.failedCheckinCount, 1);
      expect(provider.checkinSyncItems.length, 1);
      expect(provider.checkinSyncItems.first.dayKey, '2026-03-25');

      final rangerBAuth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger-b',
          refreshToken: 'refresh-ranger-b',
          role: 'ranger',
          username: 'ranger-b',
        );

      await provider.refreshCheckinSyncStatus(authProvider: rangerBAuth);
      expect(provider.failedCheckinCount, 1);
      expect(provider.checkinSyncItems.length, 1);
      expect(provider.checkinSyncItems.first.dayKey, '2026-03-26');
    });

    test('refreshCheckinSyncStatus exposes queue item states for UI', () async {
      final fakeApi = _SequenceMobileCheckinApi([
        MobileApiException(503, 'temporary outage'),
      ]);
      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        maxAttempts: 1,
        nowUtc: () => DateTime.utc(2026, 3, 25, 1, 0, 0),
        jitterSource: () => 0,
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.triggerAppOpenCheckin(authProvider: auth);
      await provider.refreshCheckinSyncStatus(authProvider: auth);

      expect(provider.checkinSyncItems.length, 1);
      expect(provider.checkinSyncItems.first.isPending, isTrue);
      expect(provider.pendingCheckinCount, 1);
      expect(provider.failedCheckinCount, 0);

      final queuedItem = (await replayQueue.listItems()).first;
      await replayQueue.markReplayFailure(
        queueId: queuedItem.queueId,
        errorMessage: 'still offline',
      );

      await provider.refreshCheckinSyncStatus(authProvider: auth);

      expect(provider.pendingCheckinCount, 0);
      expect(provider.failedCheckinCount, 1);
      expect(provider.checkinSyncItems.first.isFailed, isTrue);
      expect(provider.checkinSyncItems.first.lastError, 'still offline');
    });

    test('manual retry replays failed queue item and marks it synced', () async {
      final fakeApi = _SequenceMobileCheckinApi([
        const MobileCheckinResult(
          status: 'created',
          dayKey: '2026-03-25',
          serverTime: '2026-03-25T00:12:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: '',
        ),
      ]);

      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        maxAttempts: 1,
        nowUtc: () => DateTime.utc(2026, 3, 25, 2, 0, 0),
        jitterSource: () => 0,
        uuidGenerator: () => 'manual-retry-queue-id',
      );

      final queued = await replayQueue.enqueueCheckin(
        userId: 'rangeruser',
        dayKey: '2026-03-25',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      await replayQueue.markReplayFailure(
        queueId: queued.queueId,
        errorMessage: 'offline',
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.refreshCheckinSyncStatus(authProvider: auth);
      expect(provider.failedCheckinCount, 1);

      final result = await provider.retryFailedCheckins(
        authProvider: auth,
        queueId: queued.queueId,
      );

      expect(result, isTrue);
      expect(fakeApi.callCount, 1);
      expect(provider.failedCheckinCount, 0);
      expect(provider.pendingCheckinCount, 0);
      expect(provider.syncedCheckinCount, 1);
      expect(provider.lastCheckinStatus, 'created');
    });

    test('manual retry for one queue id does not replay other failed items',
        () async {
      var queueIdCounter = 0;
      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        maxAttempts: 1,
        nowUtc: () => DateTime.utc(2026, 3, 25, 2, 15, 0),
        jitterSource: () => 0,
        uuidGenerator: () {
          queueIdCounter += 1;
          return 'manual-retry-queue-$queueIdCounter';
        },
      );

      final failedA = await replayQueue.enqueueCheckin(
        userId: 'rangeruser',
        dayKey: '2026-03-25',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      await replayQueue.markReplayFailure(
        queueId: failedA.queueId,
        errorMessage: 'offline-a',
      );

      final failedB = await replayQueue.enqueueCheckin(
        userId: 'rangeruser',
        dayKey: '2026-03-26',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      await replayQueue.markReplayFailure(
        queueId: failedB.queueId,
        errorMessage: 'offline-b',
      );

      final fakeApi = _SequenceMobileCheckinApi([
        MobileCheckinResult(
          status: 'created',
          dayKey: failedA.dayKey,
          serverTime: '2026-03-25T00:20:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: failedA.idempotencyKey,
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.refreshCheckinSyncStatus(authProvider: auth);
      expect(provider.failedCheckinCount, 2);

      final result = await provider.retryFailedCheckins(
        authProvider: auth,
        queueId: failedA.queueId,
      );

      expect(result, isTrue);
      expect(fakeApi.callCount, 1);

      await provider.refreshCheckinSyncStatus(authProvider: auth);
      expect(provider.syncedCheckinCount, 1);
      expect(provider.failedCheckinCount, 1);
      expect(
        provider.checkinSyncItems
            .where((item) => item.isFailed)
            .map((item) => item.queueId),
        contains(failedB.queueId),
      );
    });

    test('app-open trigger is ignored while queue replay is already running',
        () async {
      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        maxAttempts: 1,
        nowUtc: () => DateTime.utc(2026, 3, 25, 2, 45, 0),
        jitterSource: () => 0,
        uuidGenerator: () => 'concurrent-replay-queue-id',
      );

      final queued = await replayQueue.enqueueCheckin(
        userId: 'rangeruser',
        dayKey: '2026-03-25',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      await replayQueue.markReplayFailure(
        queueId: queued.queueId,
        errorMessage: 'offline',
      );

      final blockingReplay = Completer<MobileCheckinResult>();
      final fakeApi = _SequenceMobileCheckinApi([blockingReplay]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      await provider.refreshCheckinSyncStatus(authProvider: auth);
      final retryFuture = provider.retryFailedCheckins(authProvider: auth);

      await Future<void>.delayed(Duration.zero);
      await provider.triggerAppOpenCheckin(authProvider: auth);

      expect(fakeApi.callCount, 1);

      blockingReplay.complete(
        MobileCheckinResult(
          status: 'created',
          dayKey: queued.dayKey,
          serverTime: '2026-03-25T00:30:00Z',
          timezone: 'Asia/Ho_Chi_Minh',
          idempotencyKey: queued.idempotencyKey,
        ),
      );

      expect(await retryFuture, isTrue);
      expect(fakeApi.callCount, 1);
    });

    test('manual retry is blocked when ranger session is unavailable',
        () async {
      final fakeApi = _SequenceMobileCheckinApi(const <Object>[]);
      final replayQueue = MobileCheckinReplayQueue(
        store: _InMemoryCheckinQueueStore(),
        maxAttempts: 1,
        nowUtc: () => DateTime.utc(2026, 3, 25, 2, 30, 0),
        jitterSource: () => 0,
      );

      final queued = await replayQueue.enqueueCheckin(
        userId: 'rangeruser',
        dayKey: '2026-03-25',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      await replayQueue.markReplayFailure(
        queueId: queued.queueId,
        errorMessage: 'offline',
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: fakeApi,
        checkinQueue: replayQueue,
      );
      final leaderAuth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.refreshCheckinSyncStatus(authProvider: leaderAuth);
      final result = await provider.retryFailedCheckins(authProvider: leaderAuth);

      expect(result, isFalse);
      expect(provider.checkinError, 'Session expired. Please sign in again.');
      expect(provider.failedCheckinCount, 0);
      expect(await replayQueue.listItems(userId: 'rangeruser'), hasLength(1));
      expect(fakeApi.callCount, 0);
    });
  });

  group('WorkManagementProvider summary role/filter state', () {
    test('does not widen ranger summary scope from stale admin login state',
        () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-02',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
            MobileWorkSummaryItem(
              rangerId: 'ranger-other',
              dayKey: '2026-03-02',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: 'ranger-self',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 2,
            totalPages: 1,
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
        username: 'ranger-self',
      );

      expect(auth.isAdmin, isFalse);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );

      expect(provider.isLeaderScope, isFalse);
      expect(provider.totalCountForDay(DateTime(2026, 3, 2)), 1);
      expect(provider.availableRangerIds, <String>['ranger-self']);
    });

    test('retries summary fetch once when token rotates after unauthorized',
        () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-a',
              dayKey: '2026-03-15',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ])
        ..errorToThrow = MobileApiException(401, 'expired')
        ..throwErrorForCalls = 1;

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-old',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      summaryApi.onFetchCall = (callCount) {
        if (callCount == 1) {
          auth.setMobileSession(
            accessToken: 'token-new',
            refreshToken: 'refresh-leader',
            role: 'leader',
          );
        }
      };

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 1),
      );

      expect(summaryApi.callCount, 2);
      expect(
        summaryApi.requestedAccessTokens,
        <String>['token-old', 'token-new'],
      );
      expect(provider.summaryError, isNull);
      expect(provider.hasCalendarData, isTrue);
    });

    test('loads leader team-scope month data and exposes ranger filter options',
        () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-a',
              dayKey: '2026-03-02',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
            MobileWorkSummaryItem(
              rangerId: 'ranger-b',
              dayKey: '2026-03-02',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
            MobileWorkSummaryItem(
              rangerId: 'ranger-b',
              dayKey: '2026-03-03',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 3,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );

      expect(provider.isLeaderScope, isTrue);
      expect(provider.teamScope, isTrue);
      expect(provider.availableRangerIds, <String>['ranger-a', 'ranger-b']);
      expect(provider.totalCountForDay(DateTime(2026, 3, 2)), 2);
      expect(provider.checkinCountForDay(DateTime(2026, 3, 2)), 1);
      expect(provider.summaryError, isNull);
    });

    test('leader ranger filter triggers scoped reload with ranger_id query',
        () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-a',
              dayKey: '2026-03-02',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
            MobileWorkSummaryItem(
              rangerId: 'ranger-b',
              dayKey: '2026-03-02',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 2,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-b',
              dayKey: '2026-03-02',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: false,
            requestedRangerId: 'ranger-b',
            effectiveRangerId: 'ranger-b',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );
      await provider.selectRangerFilter(
        authProvider: auth,
        rangerId: 'ranger-b',
      );

      expect(summaryApi.callCount, 2);
      expect(summaryApi.requestedRangerIds, <String?>[null, 'ranger-b']);
      expect(provider.selectedRangerId, 'ranger-b');
      expect(provider.availableRangerIds, <String>['ranger-a', 'ranger-b']);
      expect(provider.teamScope, isFalse);
      expect(provider.effectiveRangerId, 'ranger-b');
      expect(provider.totalCountForDay(DateTime(2026, 3, 2)), 1);
    });

    test('ranger scope does not expose leader filter and keeps self view',
        () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-04',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'ranger-self',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );
      await provider.selectRangerFilter(
        authProvider: auth,
        rangerId: 'another-ranger',
      );

      expect(provider.isLeaderScope, isFalse);
      expect(provider.selectedRangerId, isNull);
      expect(provider.effectiveRangerId, 'ranger-self');
      expect(summaryApi.callCount, 1);
      expect(summaryApi.requestedRangerIds, <String?>[null]);
    });

    test('defensively filters leaked ranger rows from ranger-scoped payload',
        () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-04',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
            MobileWorkSummaryItem(
              rangerId: 'ranger-other',
              dayKey: '2026-03-04',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'ranger-self',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 2,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );

      expect(provider.totalCountForDay(DateTime(2026, 3, 4)), 1);
      expect(provider.checkinCountForDay(DateTime(2026, 3, 4)), 1);
      expect(provider.availableRangerIds, <String>['ranger-self']);
    });

    test('hides ranger-scoped summary when effective ranger is missing',
        () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-04',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );

      expect(provider.hasCalendarData, isFalse);
      expect(provider.totalCountForDay(DateTime(2026, 3, 4)), 0);
    });

    test('sets clear error state for missing token and API failures', () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final missingTokenApi = _FakeMobileWorkSummaryApi(const <MobileWorkSummaryResult>[]);

      final missingTokenProvider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: missingTokenApi,
      );
      final noSessionAuth = AuthProvider();

      await missingTokenProvider.loadWorkSummaryForMonth(
        authProvider: noSessionAuth,
        month: DateTime(2026, 3, 1),
      );

      expect(missingTokenProvider.summaryError, 'Missing mobile access token');
      expect(missingTokenProvider.hasCalendarData, isFalse);

      final failingApi = _FakeMobileWorkSummaryApi(
        const <MobileWorkSummaryResult>[],
        errorToThrow: MobileApiException(500, 'boom'),
      );
      final failingProvider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: failingApi,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await failingProvider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 1),
      );

      expect(
        failingProvider.summaryError,
        'Unable to load Work Management data.',
      );
      expect(failingProvider.hasCalendarData, isFalse);
    });

    test('uses cached summary when refresh fails and marks offline stale state',
        () async {
      final cache = _InMemoryReadModelCache();
      await cache.saveWorkSummary(
        cacheKey:
            'month=2026-03|role=ranger|ranger=all|session=${_sessionPartition('refresh-ranger')}',
        value: const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-10',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'ranger-self',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 62,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        syncedAt: DateTime.utc(2026, 3, 10, 2),
      );

      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi(
        const <MobileWorkSummaryResult>[],
        errorToThrow: MobileApiException(503, 'network down'),
      );

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
        cache: cache,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 10),
      );

      expect(provider.hasCalendarData, isTrue);
      expect(provider.totalCountForDay(DateTime(2026, 3, 10)), 1);
      expect(provider.summaryError, isNull);
      expect(
        provider.summaryRefreshError,
        'Unable to refresh Work Management data.',
      );
      expect(provider.isSummaryOfflineFallback, isTrue);
      expect(provider.isSummaryStaleData, isTrue);
      expect(provider.isUsingCachedSummary, isTrue);
    });

    test('merges reconnect payload without duplicate day+ranger rows', () async {
      final cache = _InMemoryReadModelCache();
      await cache.saveWorkSummary(
        cacheKey:
            'month=2026-03|role=ranger|ranger=all|session=${_sessionPartition('refresh-ranger')}',
        value: const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-11',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'ranger-self',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 62,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        syncedAt: DateTime.utc(2026, 3, 11, 1),
      );

      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-11',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-12',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'ranger-self',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 62,
            total: 2,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
        cache: cache,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 11),
      );

      expect(provider.totalCountForDay(DateTime(2026, 3, 11)), 1);
      expect(provider.checkinCountForDay(DateTime(2026, 3, 11)), 1);
      expect(provider.totalCountForDay(DateTime(2026, 3, 12)), 1);
      expect(provider.summaryError, isNull);
      expect(provider.summaryRefreshError, isNull);
      expect(provider.isSummaryOfflineFallback, isFalse);
    });

    test('clamps response scope to auth role for ranger sessions', () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-13',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
            MobileWorkSummaryItem(
              rangerId: 'ranger-other',
              dayKey: '2026-03-13',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: 'ranger-self',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 2,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 13),
      );

      expect(provider.isLeaderScope, isFalse);
      expect(provider.teamScope, isFalse);
      expect(provider.totalCountForDay(DateTime(2026, 3, 13)), 1);
      expect(provider.availableRangerIds, <String>['ranger-self']);
    });

    test('ignores stale out-of-order summary responses', () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final firstRequest = Completer<MobileWorkSummaryResult>();
      final secondRequest = Completer<MobileWorkSummaryResult>();
      final summaryApi = _QueuedMobileWorkSummaryApi([
        firstRequest,
        secondRequest,
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      final marchLoad = provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 1),
      );
      final aprilLoad = provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 4, 1),
      );

      secondRequest.complete(
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-a',
              dayKey: '2026-04-05',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-04-01',
          toDay: '2026-04-30',
        ),
      );
      await aprilLoad;

      firstRequest.complete(
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-a',
              dayKey: '2026-03-05',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      );
      await marchLoad;

      expect(provider.focusedMonth, DateTime(2026, 4));
      expect(provider.totalCountForDay(DateTime(2026, 4, 5)), 1);
      expect(provider.totalCountForDay(DateTime(2026, 3, 5)), 0);
    });

    test('loads all paginated work-summary pages for a month', () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-a',
              dayKey: '2026-03-20',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 400,
            totalPages: 2,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-b',
              dayKey: '2026-03-21',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 2,
            pageSize: 366,
            total: 400,
            totalPages: 2,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 1),
      );

      expect(summaryApi.callCount, 2);
      expect(summaryApi.requestedPages, <int>[1, 2]);
      expect(provider.totalCountForDay(DateTime(2026, 3, 20)), 1);
      expect(provider.totalCountForDay(DateTime(2026, 3, 21)), 1);
      expect(provider.availableRangerIds, <String>['ranger-a', 'ranger-b']);
    });

    test('superseded missing-token request resets loading state', () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final inFlightResponse = Completer<MobileWorkSummaryResult>();
      final summaryApi = _QueuedMobileWorkSummaryApi([inFlightResponse]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );

      final leaderAuth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader',
          refreshToken: 'refresh-leader',
          role: 'leader',
        );

      final inFlightLoad = provider.loadWorkSummaryForMonth(
        authProvider: leaderAuth,
        month: DateTime(2026, 3, 1),
      );

      final noTokenAuth = AuthProvider();
      await provider.loadWorkSummaryForMonth(
        authProvider: noTokenAuth,
        month: DateTime(2026, 4, 1),
      );

      inFlightResponse.complete(
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-a',
              dayKey: '2026-03-05',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      );
      await inFlightLoad;

      expect(provider.isLoadingSummary, isFalse);
      expect(provider.summaryError, 'Missing mobile access token');
    });

    test('resets leader filter state when session partition changes', () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-a',
              dayKey: '2026-03-10',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
            MobileWorkSummaryItem(
              rangerId: 'ranger-b',
              dayKey: '2026-03-10',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 2,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-b',
              dayKey: '2026-03-10',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: false,
            requestedRangerId: 'ranger-b',
            effectiveRangerId: 'ranger-b',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-c',
              dayKey: '2026-03-11',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );

      final leaderSessionA = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader-a',
          refreshToken: 'refresh-leader-a',
          role: 'leader',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: leaderSessionA,
        month: DateTime(2026, 3, 1),
      );
      await provider.selectRangerFilter(
        authProvider: leaderSessionA,
        rangerId: 'ranger-b',
      );

      expect(provider.selectedRangerId, 'ranger-b');
      expect(provider.availableRangerIds, <String>['ranger-a', 'ranger-b']);

      final leaderSessionB = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader-b',
          refreshToken: 'refresh-leader-b',
          role: 'leader',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: leaderSessionB,
        month: DateTime(2026, 3, 1),
      );

      expect(summaryApi.requestedRangerIds, <String?>[null, 'ranger-b', null]);
      expect(provider.selectedRangerId, isNull);
      expect(provider.availableRangerIds, <String>['ranger-c']);
    });

    test('clears in-memory summary immediately on session switch', () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final firstRequest = Completer<MobileWorkSummaryResult>();
      final secondRequest = Completer<MobileWorkSummaryResult>();
      final summaryApi = _QueuedMobileWorkSummaryApi([firstRequest, secondRequest]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
      );

      final leaderSessionA = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader-a',
          refreshToken: 'refresh-leader-a',
          role: 'leader',
        );

      final leaderSessionB = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-leader-b',
          refreshToken: 'refresh-leader-b',
          role: 'leader',
        );

      final firstLoad = provider.loadWorkSummaryForMonth(
        authProvider: leaderSessionA,
        month: DateTime(2026, 3, 1),
      );

      firstRequest.complete(
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-a',
              dayKey: '2026-03-15',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      );
      await firstLoad;

      expect(provider.hasCalendarData, isTrue);

      final secondLoad = provider.loadWorkSummaryForMonth(
        authProvider: leaderSessionB,
        month: DateTime(2026, 4, 1),
      );

      expect(provider.hasCalendarData, isFalse);

      secondRequest.complete(
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-b',
              dayKey: '2026-04-15',
              hasCheckin: false,
              checkinIndicator: 'none',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'leader',
            teamScope: true,
            requestedRangerId: null,
            effectiveRangerId: null,
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-04-01',
          toDay: '2026-04-30',
        ),
      );
      await secondLoad;

      expect(provider.totalCountForDay(DateTime(2026, 4, 15)), 1);
      expect(provider.totalCountForDay(DateTime(2026, 3, 15)), 0);
    });

    test('treats cache load exception as cache miss', () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-22',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'ranger-self',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
        cache: _ThrowingReadModelCache(throwOnLoadWorkSummary: true),
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 1),
      );

      expect(provider.hasCalendarData, isTrue);
      expect(provider.summaryError, isNull);
    });

    test('keeps fetched data when cache save fails', () async {
      final checkinApi = _FakeMobileCheckinApi(const <MobileCheckinResult>[]);
      final summaryApi = _FakeMobileWorkSummaryApi([
        const MobileWorkSummaryResult(
          items: <MobileWorkSummaryItem>[
            MobileWorkSummaryItem(
              rangerId: 'ranger-self',
              dayKey: '2026-03-23',
              hasCheckin: true,
              checkinIndicator: 'confirmed',
              summary: <String, dynamic>{},
            ),
          ],
          scope: MobileWorkScope(
            role: 'ranger',
            teamScope: false,
            requestedRangerId: null,
            effectiveRangerId: 'ranger-self',
          ),
          pagination: MobileWorkPagination(
            page: 1,
            pageSize: 366,
            total: 1,
            totalPages: 1,
          ),
          fromDay: '2026-03-01',
          toDay: '2026-03-31',
        ),
      ]);

      final provider = WorkManagementProvider(
        mobileCheckinApi: checkinApi,
        mobileWorkSummaryApi: summaryApi,
        cache: _ThrowingReadModelCache(throwOnSaveWorkSummary: true),
      );
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
        );

      await provider.loadWorkSummaryForMonth(
        authProvider: auth,
        month: DateTime(2026, 3, 1),
      );

      expect(provider.hasCalendarData, isTrue);
      expect(provider.summaryError, isNull);
      expect(
        provider.summaryRefreshError,
        'Work Management data loaded, but local cache update failed.',
      );
    });
  });
}
