import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/tree_provider.dart';
import 'screens/home_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/tree_detail_screen.dart';
import 'screens/link_tree_screen.dart';
import 'services/earthranger_auth.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';

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
    apiKey: dotenv.env['SUPABASE_KEY'] ?? '',
  );

  final earthRangerAuth = EarthRangerAuth(
    username: dotenv.env['ER_USERNAME'] ?? '',
    password: dotenv.env['ER_PASSWORD'] ?? '',
  );

  runApp(
    TreeInfoApp(
      supabaseService: supabaseService,
      earthRangerAuth: earthRangerAuth,
    ),
  );
}

class TreeInfoApp extends StatelessWidget {
  final SupabaseService supabaseService;
  final EarthRangerAuth earthRangerAuth;

  const TreeInfoApp({
    super.key,
    required this.supabaseService,
    required this.earthRangerAuth,
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
        Provider<SupabaseService>.value(value: supabaseService),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: settings.l.get('app_name'),
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            initialRoute: '/',
            onGenerateRoute: (routeSettings) {
              switch (routeSettings.name) {
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
                default:
                  return MaterialPageRoute(
                    builder: (_) => const LandingScreen(),
                  );
              }
            },
          );
        },
      ),
    );
  }
}
