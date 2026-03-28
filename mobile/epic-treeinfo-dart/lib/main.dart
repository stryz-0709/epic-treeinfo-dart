import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/incident_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/tree_provider.dart';
import 'providers/work_management_provider.dart';
import 'screens/home_screen.dart';
import 'screens/incident_management_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/schedule_management_screen.dart';
import 'screens/tree_detail_screen.dart';
import 'screens/link_tree_screen.dart';
import 'screens/feature_placeholder_screen.dart';
import 'screens/work_management_screen.dart';
import 'services/earthranger_auth.dart';
import 'services/mobile_api_service.dart';
import 'services/mobile_checkin_queue.dart';
import 'services/mobile_read_model_cache.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_open_checkin_lifecycle.dart';

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
        dotenv.env['ER_OAUTH_TOKEN_URL'] ?? 'https://epictech.pamdas.org/oauth2/token/',
    allowedOauthHosts: oauthAllowedHosts,
  );

  final mobileApiService = MobileApiService(
    baseUrl: dotenv.env['BACKEND_BASE_URL'] ?? 'http://localhost:8000',
  );

  final readModelCache = SharedPreferencesMobileReadModelCache();
  final checkinQueueStore = SharedPreferencesMobileCheckinQueueStore();
  final checkinReplayQueue = MobileCheckinReplayQueue(
    store: checkinQueueStore,
  );

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
                    return MaterialPageRoute(
                      builder: (_) => const LandingScreen(),
                    );
                  case '/login':
                    return MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    );
                  case '/detail':
                    final queryId = routeSettings.arguments as String? ?? '';
                    return MaterialPageRoute(
                      builder: (_) => TreeDetailScreen(queryId: queryId),
                    );
                  case '/link':
                    final nfcId = routeSettings.arguments as String? ?? '';
                    return MaterialPageRoute(
                      builder: (_) => LinkTreeScreen(nfcId: nfcId),
                    );
                  case '/home':
                    return MaterialPageRoute(builder: (_) => const HomeScreen());
                  case '/work-management':
                    return MaterialPageRoute(
                      builder: (_) => const WorkManagementScreen(),
                    );
                  case '/incident-management':
                    return MaterialPageRoute(
                      builder: (_) => const IncidentManagementScreen(),
                    );
                  case '/resource-management':
                    return MaterialPageRoute(
                      builder: (_) => const HomeScreen(),
                    );
                  case '/schedule-management':
                    return MaterialPageRoute(
                      builder: (_) => const ScheduleManagementScreen(),
                    );
                  case '/reports-management':
                    return MaterialPageRoute(
                      builder: (_) => const WorkManagementScreen(),
                    );
                  case '/patrol-management':
                    return MaterialPageRoute(
                      builder: (_) => const IncidentManagementScreen(),
                    );
                  case '/maps':
                    return MaterialPageRoute(
                      builder: (_) => const FeaturePlaceholderScreen(
                        titleKey: 'maps',
                        navIndex: 1,
                      ),
                    );
                  case '/alerts':
                    return MaterialPageRoute(
                      builder: (_) => const FeaturePlaceholderScreen(
                        titleKey: 'alerts',
                        navIndex: 2,
                      ),
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
                      builder: (_) => const FeaturePlaceholderScreen(
                        titleKey: 'account',
                        navIndex: 4,
                      ),
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
