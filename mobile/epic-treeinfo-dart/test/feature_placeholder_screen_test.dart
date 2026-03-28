import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treeinfo_dart/providers/auth_provider.dart';
import 'package:treeinfo_dart/providers/settings_provider.dart';
import 'package:treeinfo_dart/providers/work_management_provider.dart';
import 'package:treeinfo_dart/screens/feature_placeholder_screen.dart';
import 'package:treeinfo_dart/services/mobile_api_service.dart';

class _NoopMobileCheckinApi implements MobileCheckinApi {
  @override
  Future<MobileCheckinResult> submitAppOpenCheckin({
    required String accessToken,
    String idempotencyKey = '',
    String clientTime = '',
    String timezone = '',
    String appVersion = '',
  }) async {
    return const MobileCheckinResult(
      status: 'already_exists',
      dayKey: '2026-03-24',
      serverTime: '2026-03-24T00:00:00Z',
      timezone: 'Asia/Ho_Chi_Minh',
      idempotencyKey: 'noop-idempotency',
    );
  }
}

class _FakeMobileApiService extends MobileApiService {
  _FakeMobileApiService() : super(baseUrl: 'http://localhost:8000');

  int logoutCalls = 0;
  String? lastRefreshToken;

  @override
  Future<void> logoutMobileSession({required String refreshToken}) async {
    logoutCalls += 1;
    lastRefreshToken = refreshToken;
  }
}

Widget _buildHarness({
  required AuthProvider authProvider,
  required SettingsProvider settingsProvider,
  required WorkManagementProvider workProvider,
  required MobileApiService mobileApiService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<WorkManagementProvider>.value(value: workProvider),
      Provider<MobileApiService>.value(value: mobileApiService),
    ],
    child: MaterialApp(
      initialRoute: '/account',
      routes: {
        '/account': (_) => const FeaturePlaceholderScreen(
              titleKey: 'account',
              navIndex: 4,
            ),
        '/login': (_) => const Scaffold(
              body: Center(child: Text('LOGIN_SCREEN')),
            ),
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows logout button on account screen for authenticated user', (
    tester,
  ) async {
    final authProvider = AuthProvider()
      ..setMobileSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        role: 'ranger',
        username: 'rangeruser',
      );

    final workProvider = WorkManagementProvider(
      mobileCheckinApi: _NoopMobileCheckinApi(),
    );

    await tester.pumpWidget(
      _buildHarness(
        authProvider: authProvider,
        settingsProvider: SettingsProvider(),
        workProvider: workProvider,
        mobileApiService: _FakeMobileApiService(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account_logout_button')), findsOneWidget);
  });

  testWidgets('hides logout button on account screen for unauthenticated user', (
    tester,
  ) async {
    final authProvider = AuthProvider();
    final workProvider = WorkManagementProvider(
      mobileCheckinApi: _NoopMobileCheckinApi(),
    );

    await tester.pumpWidget(
      _buildHarness(
        authProvider: authProvider,
        settingsProvider: SettingsProvider(),
        workProvider: workProvider,
        mobileApiService: _FakeMobileApiService(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account_logout_button')), findsNothing);
  });

  testWidgets('tapping logout signs out and navigates back to login route', (
    tester,
  ) async {
    final authProvider = AuthProvider()
      ..setMobileSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        role: 'leader',
        username: 'leaderuser',
      );

    final fakeMobileApi = _FakeMobileApiService();
    final workProvider = WorkManagementProvider(
      mobileCheckinApi: _NoopMobileCheckinApi(),
    );

    await tester.pumpWidget(
      _buildHarness(
        authProvider: authProvider,
        settingsProvider: SettingsProvider(),
        workProvider: workProvider,
        mobileApiService: fakeMobileApi,
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account_logout_button')));
    await tester.pumpAndSettle();

    expect(fakeMobileApi.logoutCalls, 1);
    expect(fakeMobileApi.lastRefreshToken, 'refresh-token');
    expect(authProvider.isAuthenticated, isFalse);
    expect(find.text('LOGIN_SCREEN'), findsOneWidget);
  });
}
