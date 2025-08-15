import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import '../models/trip.dart';
import 'dashboard_screen.dart';
import 'trip_selection_screen.dart';
import 'budgets_screen.dart';
import 'settings_screen.dart';

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
      BudgetsScreen(api: widget.api),          // ← real Budgets
      SettingsScreen(api: widget.api),         // ← real Settings
    ];

    return Scaffold(
      body: tabs[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Budgets'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
