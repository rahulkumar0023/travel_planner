import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:travel_planner_app/services/hive_migrations.dart';
import 'models/expense.dart';
import 'screens/app_shell.dart';
import 'screens/sign_in_screen.dart';
import 'services/api_service.dart';
import 'services/trip_storage_service.dart';
import 'services/monthly_store.dart';
import 'app_nav.dart';
import 'services/deep_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive init for offline expenses
  await Hive.initFlutter();
  // After Hive.initFlutter() + registerAdapter() + openBox(...)

  Hive.registerAdapter(ExpenseAdapter());
  await Hive.deleteBoxFromDisk('expensesBox');
  await Hive.openBox<Expense>('expensesBox');
  await HiveMigrations.backfillExpenseCurrency();
  // 👇 NEW: Monthly store init (place next to your other Hive inits)
  await MonthlyStore.instance.init();
  // Trip storage init
  await TripStorageService.init();

  final api = ApiService();
  await DeepLinkService.instance.ensureStarted();
  // Decide initial route based on restored session
  final restored = await api.restoreSession();
  final startRoute = restored ? '/home' : '/sign-in';

  runApp(TravelPlannerApp(api: api, initialRoute: startRoute));
}

class TravelPlannerApp extends StatelessWidget {
  final ApiService api;
  final String initialRoute;
  const TravelPlannerApp(
      {super.key, required this.api, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF0EA5A5);
    // 👇 NEW: routes for sign-in and home
    // app routes start
    return MaterialApp(
      title: 'Travel Planner',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        cardTheme: const CardThemeData(
            surfaceTintColor: Colors.transparent, elevation: 0),
        appBarTheme:
            const AppBarTheme(centerTitle: true, scrolledUnderElevation: 0),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        cardTheme: const CardThemeData(elevation: 0),
      ),
      routes: {
        '/sign-in': (ctx) => SignInScreen(api: api),
        '/home': (ctx) => AppShell(api: api),
      },
      initialRoute: initialRoute,
    );
    // app routes end
  }
}
