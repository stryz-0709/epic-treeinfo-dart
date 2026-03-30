import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treeinfo_dart/providers/auth_provider.dart';
import 'package:treeinfo_dart/providers/settings_provider.dart';
import 'package:treeinfo_dart/providers/work_management_provider.dart';
import 'package:treeinfo_dart/screens/work_management_screen.dart';
import 'package:treeinfo_dart/services/mobile_api_service.dart';
import 'package:treeinfo_dart/services/mobile_checkin_queue.dart';

class _InMemoryQueueStore implements MobileCheckinQueueStore {
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

class _FakeSummaryApi implements MobileWorkSummaryApi {
  @override
  Future<MobileWorkSummaryResult> fetchWorkSummary({
    required String accessToken,
    required DateTime fromDay,
    required DateTime toDay,
    String? rangerId,
    int page = 1,
    int pageSize = 62,
  }) async {
    return const MobileWorkSummaryResult(
      items: <MobileWorkSummaryItem>[],
      scope: MobileWorkScope(
        role: 'ranger',
        teamScope: false,
        requestedRangerId: null,
        effectiveRangerId: 'rangeruser',
      ),
      pagination: MobileWorkPagination(
        page: 1,
        pageSize: 62,
        total: 0,
        totalPages: 1,
      ),
      fromDay: '2026-03-01',
      toDay: '2026-03-31',
    );
  }
}

class _SequenceCheckinApi implements MobileCheckinApi {
  final List<Object> _steps;
  int callCount = 0;

  _SequenceCheckinApi(this._steps);

  @override
  Future<MobileCheckinResult> submitAppOpenCheckin({
    required String accessToken,
    String idempotencyKey = '',
    String clientTime = '',
    String timezone = '',
    String appVersion = '',
  }) async {
    callCount += 1;
    if (_steps.isEmpty) {
      throw StateError('No checkin response configured.');
    }

    final step = _steps.removeAt(0);
    if (step is MobileCheckinResult) {
      return step;
    }
    if (step is Exception) {
      throw step;
    }
    if (step is Error) {
      throw step;
    }

    throw StateError('Unsupported checkin step: $step');
  }
}

Widget _buildHarness({
  required AuthProvider authProvider,
  required SettingsProvider settingsProvider,
  required WorkManagementProvider workProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<WorkManagementProvider>.value(value: workProvider),
    ],
    child: const MaterialApp(home: WorkManagementScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders sync status panel and retries failed item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final queue = MobileCheckinReplayQueue(
      store: _InMemoryQueueStore(),
      maxAttempts: 1,
      nowUtc: () => DateTime.utc(2026, 3, 25, 2, 0, 0),
      jitterSource: () => 0,
      uuidGenerator: () => 'sync-item-1',
    );

    final queued = await queue.enqueueCheckin(
      userId: 'rangeruser',
      dayKey: '2026-03-25',
      timezoneName: 'Asia/Ho_Chi_Minh',
      appVersion: '1.0.0',
    );
    await queue.markReplayFailure(
      queueId: queued.queueId,
      errorMessage: 'offline',
    );

    final checkinApi = _SequenceCheckinApi([
      MobileCheckinResult(
        status: 'created',
        dayKey: '2026-03-25',
        serverTime: '2026-03-25T00:12:00Z',
        timezone: 'Asia/Ho_Chi_Minh',
        idempotencyKey: queued.idempotencyKey,
      ),
    ]);

    final authProvider = AuthProvider()
      ..setMobileSession(
        accessToken: 'token-ranger',
        refreshToken: 'refresh-ranger',
        role: 'ranger',
        username: 'rangeruser',
      );

    final workProvider = WorkManagementProvider(
      mobileCheckinApi: checkinApi,
      mobileWorkSummaryApi: _FakeSummaryApi(),
      checkinQueue: queue,
    );

    await tester.pumpWidget(
      _buildHarness(
        authProvider: authProvider,
        settingsProvider: SettingsProvider(),
        workProvider: workProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work_sync_status_panel')), findsOneWidget);

    final retryButton = find.byKey(Key('work_sync_retry_${queued.queueId}'));
    expect(retryButton, findsOneWidget);

    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(checkinApi.callCount, 1);
    final items = await queue.listItems();
    expect(items.first.status, MobileCheckinQueueStatus.synced);
  });

  testWidgets('shows retry-all control when multiple failed items exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final checkinApi = _SequenceCheckinApi(const <Object>[]);
    var generatedId = 0;
    final queue = MobileCheckinReplayQueue(
      store: _InMemoryQueueStore(),
      maxAttempts: 1,
      nowUtc: () => DateTime.utc(2026, 3, 25, 3, 0, 0),
      jitterSource: () => 0,
      uuidGenerator: () => 'sync-item-${generatedId++}',
    );

    final first = await queue.enqueueCheckin(
      userId: 'rangeruser',
      dayKey: '2026-03-25',
      timezoneName: 'Asia/Ho_Chi_Minh',
      appVersion: '1.0.0',
    );
    final second = await queue.enqueueCheckin(
      userId: 'rangeruser',
      dayKey: '2026-03-26',
      timezoneName: 'Asia/Ho_Chi_Minh',
      appVersion: '1.0.0',
    );

    await queue.markReplayFailure(queueId: first.queueId, errorMessage: 'offline');
    await queue.markReplayFailure(queueId: second.queueId, errorMessage: 'offline');

    final authProvider = AuthProvider()
      ..setMobileSession(
        accessToken: 'token-ranger',
        refreshToken: 'refresh-ranger',
        role: 'ranger',
        username: 'rangeruser',
      );

    final workProvider = WorkManagementProvider(
      mobileCheckinApi: checkinApi,
      mobileWorkSummaryApi: _FakeSummaryApi(),
      checkinQueue: queue,
    );

    await tester.pumpWidget(
      _buildHarness(
        authProvider: authProvider,
        settingsProvider: SettingsProvider(),
        workProvider: workProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work_sync_retry_all_button')), findsOneWidget);
  });
}
