import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treeinfo_dart/providers/auth_provider.dart';
import 'package:treeinfo_dart/services/mobile_api_service.dart';

class _FakeMobileAuthApi implements MobileAuthApi {
  MobileAuthSession? loginSession;
  MobileAuthSession? refreshSession;
  Completer<MobileAuthSession>? loginCompleter;
  MobileAuthIdentity identity = const MobileAuthIdentity(
    username: 'rangeruser',
    role: 'ranger',
  );

  bool throwOnLogin = false;
  bool throwOnRefresh = false;
  bool throwOnFetchIdentity = false;

  int logoutCallCount = 0;
  String? lastRefreshTokenUsed;

  @override
  Future<MobileAuthSession> loginMobile({
    required String username,
    required String password,
  }) async {
    if (throwOnLogin) {
      throw MobileApiException(401, 'invalid');
    }

    if (loginCompleter != null) {
      return loginCompleter!.future;
    }

    return loginSession ??
        MobileAuthSession(
          accessToken: 'access-token-login',
          refreshToken: 'refresh-token-login',
          tokenType: 'bearer',
          role: 'ranger',
          expiresIn: 900,
          username: username,
        );
  }

  @override
  Future<MobileAuthSession> refreshMobileSession({
    required String refreshToken,
  }) async {
    lastRefreshTokenUsed = refreshToken;
    if (throwOnRefresh) {
      throw MobileApiException(401, 'invalid refresh');
    }
    return refreshSession ??
        const MobileAuthSession(
          accessToken: 'access-token-refresh',
          refreshToken: 'refresh-token-refresh',
          tokenType: 'bearer',
          role: 'ranger',
          expiresIn: 900,
          username: 'rangeruser',
        );
  }

  @override
  Future<void> logoutMobileSession({required String refreshToken}) async {
    logoutCallCount += 1;
    lastRefreshTokenUsed = refreshToken;
  }

  @override
  Future<MobileAuthIdentity> fetchCurrentMobileUser({
    required String accessToken,
  }) async {
    if (throwOnFetchIdentity) {
      throw MobileApiException(500, 'identity endpoint unavailable');
    }
    return identity;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AuthProvider security defaults', () {
    test('admin login clears mobile session and fails closed when unconfigured',
        () {
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'token-ranger',
          refreshToken: 'refresh-ranger',
          role: 'ranger',
          username: 'rangeruser',
        );

      expect(auth.hasMobileAccessToken, isTrue);
      expect(auth.mobileRole, 'ranger');

      final loginSucceeded = auth.login('epic', 'password');

      expect(loginSucceeded, isFalse);
      expect(auth.isAdmin, isFalse);
      expect(auth.error, 'login_not_configured');
      expect(auth.mobileAccessToken, isNull);
      expect(auth.mobileRefreshToken, isNull);
      expect(auth.mobileRole, isNull);
      expect(auth.mobileUsername, isNull);
      expect(auth.mobileDisplayName, isNull);
    });

    test('debug test hook can set admin state in test runtime', () {
      final auth = AuthProvider();

      auth.debugSetAdminForTesting(true);
      expect(auth.isAdmin, isTrue);

      auth.debugSetAdminForTesting(false);
      expect(auth.isAdmin, isFalse);
    });

    test('loginWithMobileApi persists session when remember me is enabled',
        () async {
      final auth = AuthProvider();
      final api = _FakeMobileAuthApi();

      final ok = await auth.loginWithMobileApi(
        authApi: api,
        username: 'rangeruser',
        password: 'safe-ranger-password',
        rememberMe: true,
      );

      final prefs = await SharedPreferences.getInstance();

      expect(ok, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.mobileRole, 'ranger');
      expect(auth.mobileUsername, 'rangeruser');
      expect(auth.mobileDisplayName, isNull);
      expect(prefs.getBool('mobile_auth_remember_me'), isTrue);
      expect(prefs.getString('mobile_auth_access_token'), 'access-token-login');
      expect(prefs.getString('mobile_auth_refresh_token'), 'refresh-token-login');
      expect(prefs.getString('mobile_auth_role'), 'ranger');
      expect(prefs.getString('mobile_auth_username'), 'rangeruser');
      expect(prefs.getString('mobile_auth_display_name'), isNull);
    });

    test(
        'loginWithMobileApi keeps username for identity and stores display name for UI',
        () async {
      final auth = AuthProvider();
      final api = _FakeMobileAuthApi()
        ..loginSession = const MobileAuthSession(
          accessToken: 'access-token-login',
          refreshToken: 'refresh-token-login',
          tokenType: 'bearer',
          role: 'ranger',
          expiresIn: 900,
          username: 'rangeruser',
          displayName: 'Session Ranger Name',
        )
        ..identity = const MobileAuthIdentity(
          username: 'rangeruser',
          role: 'ranger',
          displayName: 'Ranger User',
        );

      final ok = await auth.loginWithMobileApi(
        authApi: api,
        username: 'rangeruser',
        password: 'safe-ranger-password',
        rememberMe: true,
      );

      final prefs = await SharedPreferences.getInstance();

      expect(ok, isTrue);
      expect(auth.mobileUsername, 'rangeruser');
      expect(auth.mobileDisplayName, 'Ranger User');
      expect(prefs.getString('mobile_auth_username'), 'rangeruser');
      expect(prefs.getString('mobile_auth_display_name'), 'Ranger User');
    });

    test('loginWithMobileApi failure clears any existing mobile session',
        () async {
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'stale-access-token',
          refreshToken: 'stale-refresh-token',
          role: 'leader',
          username: 'leaderuser',
        );
      final api = _FakeMobileAuthApi()..throwOnLogin = true;

      final ok = await auth.loginWithMobileApi(
        authApi: api,
        username: 'wronguser',
        password: 'wrong-password',
        rememberMe: true,
      );

      expect(ok, isFalse);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.isAdmin, isFalse);
      expect(auth.mobileAccessToken, isNull);
      expect(auth.mobileRefreshToken, isNull);
      expect(auth.mobileRole, isNull);
      expect(auth.mobileUsername, isNull);
      expect(auth.mobileDisplayName, isNull);
      expect(auth.error, 'invalid_credentials');
    });

    test('logout prevents in-flight login response from restoring session',
        () async {
      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'existing-access-token',
          refreshToken: 'existing-refresh-token',
          role: 'ranger',
          username: 'rangeruser',
        );
      final api = _FakeMobileAuthApi()
        ..loginCompleter = Completer<MobileAuthSession>();

      final loginFuture = auth.loginWithMobileApi(
        authApi: api,
        username: 'rangeruser',
        password: 'safe-ranger-password',
        rememberMe: true,
      );

      await Future<void>.delayed(Duration.zero);
      await auth.logoutMobileSession(authApi: api);

      api.loginCompleter!.complete(
        const MobileAuthSession(
          accessToken: 'late-access-token',
          refreshToken: 'late-refresh-token',
          tokenType: 'bearer',
          role: 'ranger',
          expiresIn: 900,
          username: 'rangeruser',
        ),
      );

      final loginSucceeded = await loginFuture;
      final prefs = await SharedPreferences.getInstance();

      expect(loginSucceeded, isFalse);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.mobileAccessToken, isNull);
      expect(auth.mobileRefreshToken, isNull);
      expect(prefs.getString('mobile_auth_access_token'), isNull);
      expect(prefs.getString('mobile_auth_refresh_token'), isNull);
    });

    test(
        'loginWithMobileApi clears persisted session when remember me is disabled',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mobile_auth_remember_me': true,
        'mobile_auth_access_token': 'old-access-token',
        'mobile_auth_refresh_token': 'old-refresh-token',
        'mobile_auth_role': 'leader',
        'mobile_auth_username': 'old-user',
      });

      final auth = AuthProvider();
      final api = _FakeMobileAuthApi()
        ..identity = const MobileAuthIdentity(
          username: 'leaderuser',
          role: 'leader',
        )
        ..loginSession = const MobileAuthSession(
          accessToken: 'new-access-token',
          refreshToken: 'new-refresh-token',
          tokenType: 'bearer',
          role: 'leader',
          expiresIn: 900,
          username: 'leaderuser',
        );

      final ok = await auth.loginWithMobileApi(
        authApi: api,
        username: 'leaderuser',
        password: 'strong-password-123',
        rememberMe: false,
      );

      final prefs = await SharedPreferences.getInstance();

      expect(ok, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.mobileRole, 'leader');
      expect(prefs.getBool('mobile_auth_remember_me'), isFalse);
      expect(prefs.getString('mobile_auth_access_token'), isNull);
      expect(prefs.getString('mobile_auth_refresh_token'), isNull);
      expect(prefs.getString('mobile_auth_role'), isNull);
      expect(prefs.getString('mobile_auth_username'), isNull);
    });

    test('restoreRememberedSession refreshes persisted session', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mobile_auth_remember_me': true,
        'mobile_auth_refresh_token': 'stored-refresh-token',
        'mobile_auth_username': 'stored-user',
      });

      final auth = AuthProvider();
      final api = _FakeMobileAuthApi()
        ..refreshSession = const MobileAuthSession(
          accessToken: 'refreshed-access-token',
          refreshToken: 'refreshed-refresh-token',
          tokenType: 'bearer',
          role: 'ranger',
          expiresIn: 900,
          username: 'stored-user',
        );

      await auth.restoreRememberedSession(authApi: api);

      final prefs = await SharedPreferences.getInstance();

      expect(auth.restoreAttempted, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.mobileAccessToken, 'refreshed-access-token');
      expect(auth.mobileRefreshToken, 'refreshed-refresh-token');
      expect(api.lastRefreshTokenUsed, 'stored-refresh-token');
      expect(
        prefs.getString('mobile_auth_access_token'),
        'refreshed-access-token',
      );
      expect(
        prefs.getString('mobile_auth_refresh_token'),
        'refreshed-refresh-token',
      );
    });

    test('restoreRememberedSession clears invalid persisted session', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mobile_auth_remember_me': true,
        'mobile_auth_access_token': 'stale-access-token',
        'mobile_auth_refresh_token': 'stale-refresh-token',
        'mobile_auth_role': 'ranger',
        'mobile_auth_username': 'rangeruser',
      });

      final auth = AuthProvider();
      final api = _FakeMobileAuthApi()..throwOnRefresh = true;

      await auth.restoreRememberedSession(authApi: api);

      final prefs = await SharedPreferences.getInstance();

      expect(auth.restoreAttempted, isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.mobileAccessToken, isNull);
      expect(auth.mobileRefreshToken, isNull);
      expect(prefs.getBool('mobile_auth_remember_me'), isTrue);
      expect(prefs.getString('mobile_auth_access_token'), isNull);
      expect(prefs.getString('mobile_auth_refresh_token'), isNull);
      expect(prefs.getString('mobile_auth_role'), isNull);
      expect(prefs.getString('mobile_auth_username'), isNull);
    });

    test('logoutMobileSession clears local and persisted session state',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mobile_auth_remember_me': true,
        'mobile_auth_access_token': 'persisted-access',
        'mobile_auth_refresh_token': 'persisted-refresh',
        'mobile_auth_role': 'leader',
        'mobile_auth_username': 'leaderuser',
      });

      final auth = AuthProvider()
        ..setMobileSession(
          accessToken: 'runtime-access',
          refreshToken: 'runtime-refresh',
          role: 'leader',
          username: 'leaderuser',
        );
      final api = _FakeMobileAuthApi();

      await auth.logoutMobileSession(authApi: api);

      final prefs = await SharedPreferences.getInstance();

      expect(api.logoutCallCount, 1);
      expect(api.lastRefreshTokenUsed, 'runtime-refresh');
      expect(auth.isAuthenticated, isFalse);
      expect(auth.rememberMe, isFalse);
      expect(prefs.getBool('mobile_auth_remember_me'), isNull);
      expect(prefs.getString('mobile_auth_access_token'), isNull);
      expect(prefs.getString('mobile_auth_refresh_token'), isNull);
    });
  });
}
