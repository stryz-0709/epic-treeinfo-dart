import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/incident_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/tree_provider.dart';
import 'providers/work_management_provider.dart';
import 'screens/incident_management_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/schedule_management_screen.dart';
import 'screens/link_tree_screen.dart';
import 'screens/account_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/feature_placeholder_screen.dart';
import 'screens/forest_compartment_management_screen.dart';
import 'screens/forest_resource_management_screen.dart';
import 'screens/map_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/work_management_screen.dart';
import 'services/earthranger_auth.dart';
import 'services/mobile_api_service.dart';
import 'services/mobile_checkin_queue.dart';
import 'services/mobile_read_model_cache.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_open_checkin_lifecycle.dart';

void _addBackendBaseUrlCandidate(List<String> target, String? candidate) {
  if (candidate == null) return;
  final trimmed = candidate.trim();
  if (trimmed.isEmpty) return;
  final normalized = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  if (normalized.isEmpty) return;
  if (!target.contains(normalized)) {
    target.add(normalized);
  }
}

List<String> _resolveBackendBaseUrlCandidates() {
  final commonBaseUrl = dotenv.env['BACKEND_BASE_URL'];
  final androidBaseUrl = dotenv.env['BACKEND_BASE_URL_ANDROID'];
  final iosBaseUrl = dotenv.env['BACKEND_BASE_URL_IOS'];
  final candidates = <String>[];

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    _addBackendBaseUrlCandidate(candidates, androidBaseUrl);
    _addBackendBaseUrlCandidate(candidates, commonBaseUrl);
    _addBackendBaseUrlCandidate(candidates, 'http://10.0.2.2:8000');
    _addBackendBaseUrlCandidate(candidates, 'http://localhost:8000');
    return candidates;
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    _addBackendBaseUrlCandidate(candidates, iosBaseUrl);
    _addBackendBaseUrlCandidate(candidates, commonBaseUrl);
    _addBackendBaseUrlCandidate(candidates, 'http://localhost:8000');
    _addBackendBaseUrlCandidate(candidates, 'http://127.0.0.1:8000');
    return candidates;
  }

  _addBackendBaseUrlCandidate(candidates, commonBaseUrl);
  _addBackendBaseUrlCandidate(candidates, 'http://localhost:8000');
  return candidates;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env file
  await dotenv.load(fileName: '.env');

  // Prefer edge-to-edge
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Instantiate services
  final supabaseService = SupabaseService(
    baseUrl: dotenv.env['SUPABASE_URL'] ?? '',
    apiKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  final oauthAllowedHosts =
      (dotenv.env['ER_OAUTH_ALLOWED_HOSTS'] ?? 'epictech.pamdas.org')
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();

  final earthRangerAuth = EarthRangerAuth(
    enablePasswordGrant:
        (dotenv.env['ER_PASSWORD_GRANT_ENABLED'] ?? 'false').toLowerCase() ==
        'true',
    oauthTokenUrl:
        dotenv.env['ER_OAUTH_TOKEN_URL'] ??
        'https://epictech.pamdas.org/oauth2/token/',
    allowedOauthHosts: oauthAllowedHosts,
  );

  final backendBaseUrls = _resolveBackendBaseUrlCandidates();
  final mobileApiService = MobileApiService(
    baseUrl: backendBaseUrls.first,
    fallbackBaseUrls: backendBaseUrls.skip(1).toList(growable: false),
  );

  final readModelCache = SharedPreferencesMobileReadModelCache();
  final checkinQueueStore = SharedPreferencesMobileCheckinQueueStore();
  final checkinReplayQueue = MobileCheckinReplayQueue(store: checkinQueueStore);

  runApp(
    TreeInfoApp(
      supabaseService: supabaseService,
      earthRangerAuth: earthRangerAuth,
      mobileApiService: mobileApiService,
      readModelCache: readModelCache,
      checkinReplayQueue: checkinReplayQueue,
    ),
  );
}

class TreeInfoApp extends StatelessWidget {
  final SupabaseService supabaseService;
  final EarthRangerAuth earthRangerAuth;
  final MobileApiService mobileApiService;
  final MobileReadModelCache readModelCache;
  final MobileCheckinReplayQueue checkinReplayQueue;

  const TreeInfoApp({
    super.key,
    required this.supabaseService,
    required this.earthRangerAuth,
    required this.mobileApiService,
    required this.readModelCache,
    required this.checkinReplayQueue,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(
          create: (_) => TreeProvider(
            supabaseService: supabaseService,
            earthRangerAuth: earthRangerAuth,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => WorkManagementProvider(
            mobileCheckinApi: mobileApiService,
            mobileWorkSummaryApi: mobileApiService,
            cache: readModelCache,
            checkinQueue: checkinReplayQueue,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => IncidentProvider(
            incidentApi: mobileApiService,
            cache: readModelCache,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ScheduleProvider(
            scheduleApi: mobileApiService,
            cache: readModelCache,
          ),
        ),
        Provider<MobileApiService>.value(value: mobileApiService),
        Provider<SupabaseService>.value(value: supabaseService),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return AppOpenCheckinLifecycle(
            child: MaterialApp(
              title: settings.l.get('app_name'),
              debugShowCheckedModeBanner: false,
              themeMode: settings.themeMode,
              theme: buildLightTheme(),
              darkTheme: buildDarkTheme(),
              initialRoute: '/login',
              onGenerateRoute: (routeSettings) {
                switch (routeSettings.name) {
                  case '/':
                  case '/landing':
                    return MaterialPageRoute(builder: (_) => const MainShell());
                  case '/login':
                    return MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    );
                  case '/signup':
                    return MaterialPageRoute(
                      builder: (_) => const SignupScreen(),
                    );
                  case '/detail':
                    final queryId = routeSettings.arguments as String? ?? '';
                    return MaterialPageRoute(
                      builder: (_) => ForestResourceManagementScreen(
                        initialQuery: queryId,
                      ),
                    );
                  case '/link':
                    final nfcId = routeSettings.arguments as String? ?? '';
                    return MaterialPageRoute(
                      builder: (_) => LinkTreeScreen(nfcId: nfcId),
                    );
                  case '/home':
                    return MaterialPageRoute(
                      builder: (_) => const ForestResourceManagementScreen(),
                    );
                  case '/work-management':
                    return MaterialPageRoute(
                      builder: (_) => const WorkManagementScreen(),
                    );
                  case '/incident-management':
                    return MaterialPageRoute(
                      builder: (_) => const ForestCompartmentManagementScreen(),
                    );
                  case '/compartment-management':
                    return MaterialPageRoute(
                      builder: (_) => const ForestCompartmentManagementScreen(),
                    );
                  case '/resource-management':
                    final initialQuery = routeSettings.arguments as String?;
                    return MaterialPageRoute(
                      builder: (_) => ForestResourceManagementScreen(
                        initialQuery: initialQuery,
                      ),
                    );
                  case '/schedule-management':
                    return MaterialPageRoute(
                      builder: (_) => const ScheduleManagementScreen(),
                    );
                  case '/reports-management':
                    return MaterialPageRoute(
                      builder: (_) => const ReportsScreen(),
                    );
                  case '/forest-compartment':
                    return MaterialPageRoute(
                      builder: (_) => const ForestCompartmentManagementScreen(),
                    );
                  case '/patrol-management':
                    return MaterialPageRoute(
                      builder: (_) => const IncidentManagementScreen(),
                    );
                  case '/maps':
                    return MaterialPageRoute(builder: (_) => const MapScreen());
                  case '/alerts':
                    return MaterialPageRoute(
                      builder: (_) => const AlertsScreen(),
                    );
                  case '/notifications':
                    return MaterialPageRoute(
                      builder: (_) => const FeaturePlaceholderScreen(
                        titleKey: 'notifications',
                        navIndex: 3,
                      ),
                    );
                  case '/account':
                    return MaterialPageRoute(
                      builder: (_) => const AccountScreen(),
                    );
                  default:
                    return MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    );
                }
              },
            ),
          );
        },
      ),
    );
  }
}
