import 'package:flutter_test/flutter_test.dart';
import 'package:treeinfo_dart/services/mobile_checkin_queue.dart';

class _InMemoryQueueStore implements MobileCheckinQueueStore {
  List<Map<String, dynamic>> records = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> loadQueueItems() async {
    return records
        .map((record) => Map<String, dynamic>.from(record))
        .toList(growable: false);
  }

  @override
  Future<void> saveQueueItems(List<Map<String, dynamic>> records) async {
    this.records = records
        .map((record) => Map<String, dynamic>.from(record))
        .toList(growable: false);
  }
}

class _DelayedInMemoryQueueStore extends _InMemoryQueueStore {
  static const Duration loadDelay = Duration(milliseconds: 5);
  static const Duration saveDelay = Duration(milliseconds: 5);

  @override
  Future<List<Map<String, dynamic>>> loadQueueItems() async {
    await Future<void>.delayed(loadDelay);
    return super.loadQueueItems();
  }

  @override
  Future<void> saveQueueItems(List<Map<String, dynamic>> records) async {
    await Future<void>.delayed(saveDelay);
    await super.saveQueueItems(records);
  }
}

void main() {
  group('MobileCheckinReplayQueue', () {
    test('composes project day key using Asia/Ho_Chi_Minh boundary', () {
      final beforeBoundary = DateTime.utc(2026, 3, 20, 16, 59, 59);
      final atBoundary = DateTime.utc(2026, 3, 20, 17, 0, 0);

      expect(
        MobileCheckinReplayQueue.projectDayKeyFromUtc(beforeBoundary),
        '2026-03-20',
      );
      expect(
        MobileCheckinReplayQueue.projectDayKeyFromUtc(atBoundary),
        '2026-03-21',
      );
    });

    test('enqueue builds pending record with idempotency key format', () async {
      final store = _InMemoryQueueStore();
      final now = DateTime.utc(2026, 3, 23, 3, 15, 0);
      final queue = MobileCheckinReplayQueue(
        store: store,
        nowUtc: () => now,
        jitterSource: () => 0,
        uuidGenerator: () => 'client-uuid-01',
      );

      final item = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
        clientTimeUtc: now,
      );

      expect(item.status, MobileCheckinQueueStatus.pending);
      expect(item.attemptCount, 0);
      expect(item.idempotencyKey, 'ranger-a:checkin:2026-03-23:client-uuid-01');

      final summary = await queue.summarize();
      expect(summary.pendingCount, 1);
      expect(summary.failedCount, 0);
      expect(summary.nextRetryAt, isNull);
    });

    test('enqueue deduplicates pending checkin by user/action/day', () async {
      final store = _InMemoryQueueStore();
      final now = DateTime.utc(2026, 3, 23, 4, 0, 0);
      var uuidCounter = 0;
      final queue = MobileCheckinReplayQueue(
        store: store,
        nowUtc: () => now,
        jitterSource: () => 0,
        uuidGenerator: () {
          uuidCounter += 1;
          return 'client-uuid-$uuidCounter';
        },
      );

      final first = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      final second = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      expect(first.queueId, second.queueId);
      expect(uuidCounter, 1);

      final items = await queue.listItems();
      expect(items.length, 1);
    });

    test('concurrent enqueue operations still deduplicate to one pending item', () async {
      final store = _DelayedInMemoryQueueStore();
      var uuidCounter = 0;
      final queue = MobileCheckinReplayQueue(
        store: store,
        nowUtc: () => DateTime.utc(2026, 3, 23, 4, 30, 0),
        jitterSource: () => 0,
        uuidGenerator: () {
          uuidCounter += 1;
          return 'client-uuid-$uuidCounter';
        },
      );

      final results = await Future.wait(<Future<MobileCheckinQueueItem>>[
        queue.enqueueCheckin(
          userId: 'ranger-a',
          dayKey: '2026-03-23',
          timezoneName: 'Asia/Ho_Chi_Minh',
          appVersion: '1.0.0',
        ),
        queue.enqueueCheckin(
          userId: 'ranger-a',
          dayKey: '2026-03-23',
          timezoneName: 'Asia/Ho_Chi_Minh',
          appVersion: '1.0.0',
        ),
      ]);

      expect(results[0].queueId, results[1].queueId);

      final items = await queue.listItems();
      expect(items.length, 1);
      expect(items.first.status, MobileCheckinQueueStatus.pending);
    });

    test('enqueue rejects mismatched custom idempotency keys', () async {
      final store = _InMemoryQueueStore();
      final queue = MobileCheckinReplayQueue(
        store: store,
        nowUtc: () => DateTime.utc(2026, 3, 23, 4, 45, 0),
        jitterSource: () => 0,
        uuidGenerator: () => 'client-uuid-09',
      );

      await expectLater(
        () => queue.enqueueCheckin(
          userId: 'ranger-a',
          dayKey: '2026-03-23',
          timezoneName: 'Asia/Ho_Chi_Minh',
          appVersion: '1.0.0',
          clientUuid: 'client-uuid-09',
          idempotencyKey: 'bad-key',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('replay failure advances backoff and eventually marks failed', () async {
      final store = _InMemoryQueueStore();
      var now = DateTime.utc(2026, 3, 23, 5, 0, 0);
      final queue = MobileCheckinReplayQueue(
        store: store,
        initialRetryDelay: const Duration(seconds: 5),
        maxRetryDelay: const Duration(minutes: 15),
        maxAttempts: 3,
        jitterRatio: 0,
        nowUtc: () => now,
        jitterSource: () => 0,
        uuidGenerator: () => 'client-uuid-01',
      );

      final queued = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      var updated = await queue.markReplayFailure(
        queueId: queued.queueId,
        errorMessage: 'network error',
      );
      expect(updated, isNotNull);
      expect(updated!.status, MobileCheckinQueueStatus.pending);
      expect(updated.attemptCount, 1);
      expect(updated.nextRetryAt, now.add(const Duration(seconds: 5)));

      now = now.add(const Duration(seconds: 4));
      var ready = await queue.readyForReplay();
      expect(ready, isEmpty);

      now = now.add(const Duration(seconds: 1));
      ready = await queue.readyForReplay();
      expect(ready.length, 1);

      updated = await queue.markReplayFailure(
        queueId: queued.queueId,
        errorMessage: 'network error again',
      );
      expect(updated, isNotNull);
      expect(updated!.status, MobileCheckinQueueStatus.pending);
      expect(updated.attemptCount, 2);
      expect(updated.nextRetryAt, now.add(const Duration(seconds: 10)));

      now = now.add(const Duration(seconds: 10));
      updated = await queue.markReplayFailure(
        queueId: queued.queueId,
        errorMessage: 'still failing',
      );
      expect(updated, isNotNull);
      expect(updated!.status, MobileCheckinQueueStatus.failed);
      expect(updated.attemptCount, 3);
      expect(updated.nextRetryAt, isNull);

      final summary = await queue.summarize();
      expect(summary.pendingCount, 0);
      expect(summary.failedCount, 1);
    });

    test('markSynced clears pending retry metadata', () async {
      final store = _InMemoryQueueStore();
      final now = DateTime.utc(2026, 3, 23, 6, 0, 0);
      final queue = MobileCheckinReplayQueue(
        store: store,
        nowUtc: () => now,
        jitterSource: () => 0,
        uuidGenerator: () => 'client-uuid-02',
      );

      final queued = await queue.enqueueCheckin(
        userId: 'ranger-b',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      final synced = await queue.markSynced(queued.queueId);
      expect(synced, isNotNull);
      expect(synced!.status, MobileCheckinQueueStatus.synced);
      expect(synced.nextRetryAt, isNull);
      expect(synced.lastError, isNull);

      final summary = await queue.summarize();
      expect(summary.pendingCount, 0);
      expect(summary.failedCount, 0);
    });

    test('prepareFailedForManualRetry moves failed item back to pending',
        () async {
      final store = _InMemoryQueueStore();
      var now = DateTime.utc(2026, 3, 23, 6, 30, 0);
      final queue = MobileCheckinReplayQueue(
        store: store,
        maxAttempts: 2,
        jitterRatio: 0,
        nowUtc: () => now,
        jitterSource: () => 0,
        uuidGenerator: () => 'client-uuid-03',
      );

      final queued = await queue.enqueueCheckin(
        userId: 'ranger-c',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      await queue.markReplayFailure(
        queueId: queued.queueId,
        errorMessage: 'temporary outage',
      );

      now = now.add(const Duration(seconds: 5));
      final failed = await queue.markReplayFailure(
        queueId: queued.queueId,
        errorMessage: 'still offline',
      );

      expect(failed, isNotNull);
      expect(failed!.status, MobileCheckinQueueStatus.failed);
      expect(failed.attemptCount, 2);
      expect(failed.lastError, 'still offline');

      now = now.add(const Duration(seconds: 3));
      final retryPrepared = await queue.prepareFailedForManualRetry(
        queued.queueId,
      );

      expect(retryPrepared, isNotNull);
      expect(retryPrepared!.status, MobileCheckinQueueStatus.pending);
      expect(retryPrepared.attemptCount, 0);
      expect(retryPrepared.nextRetryAt, isNull);
      expect(retryPrepared.lastError, isNull);

      final summary = await queue.summarize();
      expect(summary.pendingCount, 1);
      expect(summary.failedCount, 0);
    });

    test('user-scoped summarize and replay readiness filter by user id',
        () async {
      final store = _InMemoryQueueStore();
      var queueIdCounter = 0;
      final queue = MobileCheckinReplayQueue(
        store: store,
        nowUtc: () => DateTime.utc(2026, 3, 23, 7, 0, 0),
        jitterSource: () => 0,
        uuidGenerator: () {
          queueIdCounter += 1;
          return 'scoped-queue-$queueIdCounter';
        },
      );

      final itemA = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      final itemB = await queue.enqueueCheckin(
        userId: 'ranger-b',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      final summaryA = await queue.summarizeForUser('ranger-a');
      expect(summaryA.pendingCount, 1);
      expect(summaryA.failedCount, 0);

      final summaryB = await queue.summarizeForUser('ranger-b');
      expect(summaryB.pendingCount, 1);
      expect(summaryB.failedCount, 0);

      final readyA = await queue.readyForReplay(userId: 'ranger-a');
      expect(readyA, hasLength(1));
      expect(readyA.first.queueId, itemA.queueId);

      final readyB = await queue.readyForReplay(userId: 'ranger-b');
      expect(readyB, hasLength(1));
      expect(readyB.first.queueId, itemB.queueId);
    });

    test('enqueue duplicate failed item rearms existing queue record', () async {
      final store = _InMemoryQueueStore();
      final queue = MobileCheckinReplayQueue(
        store: store,
        maxAttempts: 1,
        jitterRatio: 0,
        nowUtc: () => DateTime.utc(2026, 3, 23, 7, 30, 0),
        jitterSource: () => 0,
        uuidGenerator: () => 'rearm-queue-id',
      );

      final first = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      final failed = await queue.markReplayFailure(
        queueId: first.queueId,
        errorMessage: 'offline',
      );

      expect(failed, isNotNull);
      expect(failed!.status, MobileCheckinQueueStatus.failed);

      final rearmed = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      expect(rearmed.queueId, first.queueId);
      expect(rearmed.status, MobileCheckinQueueStatus.pending);
      expect(rearmed.attemptCount, 0);
      expect(rearmed.nextRetryAt, isNull);
      expect(rearmed.lastError, isNull);
      expect(await queue.listItems(), hasLength(1));
    });

    test('persist retains bounded synced history while keeping unsynced items',
        () async {
      final store = _InMemoryQueueStore();
      var now = DateTime.utc(2026, 3, 23, 8, 0, 0);
      var queueIdCounter = 0;
      final queue = MobileCheckinReplayQueue(
        store: store,
        maxSyncedHistory: 1,
        nowUtc: () => now,
        jitterSource: () => 0,
        uuidGenerator: () {
          queueIdCounter += 1;
          return 'compaction-queue-$queueIdCounter';
        },
      );

      final first = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      await queue.markSynced(first.queueId);

      now = now.add(const Duration(minutes: 1));
      final second = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-24',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      await queue.markSynced(second.queueId);

      now = now.add(const Duration(minutes: 1));
      final third = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-25',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      await queue.markSynced(third.queueId);

      final afterSyncedCompaction = await queue.listItems();
      expect(afterSyncedCompaction, hasLength(1));
      expect(afterSyncedCompaction.first.queueId, third.queueId);
      expect(afterSyncedCompaction.first.isSynced, isTrue);

      now = now.add(const Duration(minutes: 1));
      await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-26',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      final finalItems = await queue.listItems();
      expect(finalItems, hasLength(2));
      expect(finalItems.where((item) => item.isSynced), hasLength(1));
      expect(finalItems.where((item) => item.isPending), hasLength(1));
    });

    test('user-scoped mutation prevents cross-user queue id collisions',
        () async {
      final store = _InMemoryQueueStore();
      final queue = MobileCheckinReplayQueue(
        store: store,
        nowUtc: () => DateTime.utc(2026, 3, 23, 9, 0, 0),
        jitterSource: () => 0,
        uuidGenerator: () => 'shared-queue-id',
      );

      final rangerA = await queue.enqueueCheckin(
        userId: 'ranger-a',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );
      final rangerB = await queue.enqueueCheckin(
        userId: 'ranger-b',
        dayKey: '2026-03-23',
        timezoneName: 'Asia/Ho_Chi_Minh',
        appVersion: '1.0.0',
      );

      expect(rangerA.queueId, rangerB.queueId);

      await queue.markSynced(
        rangerA.queueId,
        userId: 'ranger-b',
      );

      final items = await queue.listItems();
      final itemA = items.firstWhere((item) => item.userId == 'ranger-a');
      final itemB = items.firstWhere((item) => item.userId == 'ranger-b');

      expect(itemA.isPending, isTrue);
      expect(itemB.isSynced, isTrue);
    });
  });
}
