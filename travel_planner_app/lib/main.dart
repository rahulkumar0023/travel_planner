import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/expense.dart';
import 'screens/app_shell.dart';
import 'services/api_service.dart';
import 'services/trip_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive init for offline expenses
  await Hive.initFlutter();
  Hive.registerAdapter(ExpenseAdapter());
  await Hive.openBox<Expense>('expensesBox');

  // Trip storage init
  await TripStorageService.init();

  // Read API base from --dart-define (with safe default)
  const base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://travel-planner-api-uo05.onrender.com',
  );

  final api = ApiService(baseUrl: base);

  runApp(TravelPlannerApp(api: api));
}

class TravelPlannerApp extends StatelessWidget {
  final ApiService api;
  const TravelPlannerApp({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF0EA5A5);
    return MaterialApp(
      title: 'Travel Planner',
      debugShowCheckedModeBanner: false,
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
      home: AppShell(api: api), // ⬅ make sure AppShell takes ApiService
    );
  }
}
