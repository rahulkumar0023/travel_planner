import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/expense.dart';
import 'screens/trip_selection_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/trip_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // Clean start - remove this after first successful run
  await Hive.deleteBoxFromDisk('expensesBox');

  Hive.registerAdapter(ExpenseAdapter());
  await Hive.openBox('expensesBox');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travel Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkTripSelection();
  }

  Future<void> _checkTripSelection() async {
    await Future.delayed(const Duration(milliseconds: 500));

    final hasTrip = await TripStorageService.hasSelectedTrip();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => hasTrip ? const DashboardScreen() : const TripSelectionScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.airplanemode_active,
              size: 64,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Travel Planner',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
