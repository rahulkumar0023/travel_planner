import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import '../models/trip.dart';
import 'dashboard_screen.dart';
import 'trip_selection_screen.dart';
import 'expenses_screen.dart';
import 'budgets_screen.dart';

class AppShell extends StatefulWidget {
  final ApiService api;
  const AppShell({super.key, required this.api});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Trip? _activeTrip;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _activeTrip = TripStorageService.loadLightweight();

    // If no trip is selected yet, open the picker after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_activeTrip == null && mounted) {
        final picked = await Navigator.of(context).push<Trip>(
          MaterialPageRoute(builder: (_) => TripSelectionScreen(api: widget.api)),
        );
        if (!mounted) return;
        if (picked != null) {
          await TripStorageService.save(picked);
          setState(() => _activeTrip = picked);
        }
      }
    });
  }

  void _switchTrip() async {
    final picked = await Navigator.of(context).push<Trip>(
      MaterialPageRoute(builder: (_) => TripSelectionScreen(api: widget.api)),
    );
    if (picked != null) {
      await TripStorageService.save(picked);
      if (!mounted) return;
      setState(() => _activeTrip = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      DashboardScreen(
        activeTrip: _activeTrip,
        onSwitchTrip: _switchTrip,
        api: widget.api,
      ),
      ExpensesScreen(api: widget.api),
      BudgetsScreen(api: widget.api),
    ];

    return Scaffold(
      body: tabs[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Expenses'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), label: 'Budgets'),
        ],
      ),
    );
  }
}
