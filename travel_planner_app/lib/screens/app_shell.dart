// app_shell imports patch start
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import '../models/trip.dart';
import 'budgets_screen.dart';
import 'dashboard_screen.dart';
import 'expenses_screen.dart';
import 'trip_selection_screen.dart';
// app_shell imports patch end


class AppShell extends StatefulWidget {
  final ApiService api;
  const AppShell({super.key, required this.api});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Trip? _activeTrip;
  int _tabIndex = 0;

  // app_shell dashboard key field start
  Key _dashKey = UniqueKey();
// app_shell dashboard key field end

  @override
  void initState() {
    super.initState();
    _activeTrip = TripStorageService.loadLightweight();

    // ===== App start: sync pending expenses start =====
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.api.syncPendingExpensesIfOnline();
    });
    // ===== App start: sync pending expenses end =====

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

  // app_shell _openTripPicker method start
  Future<void> _openTripPicker() async {
    final picked = await Navigator.of(context).push<Trip>(
      MaterialPageRoute(builder: (_) => TripSelectionScreen(api: widget.api)),
    );
    if (picked != null) {
      await TripStorageService.save(picked);
      if (!mounted) return;
      // Recreate DashboardScreen so it reloads the active trip
      setState(() {
        _dashKey = UniqueKey();
      });
    }
  }
// app_shell _openTripPicker method end

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
       // activeTrip: _activeTrip,
        key: _dashKey,
        onSwitchTrip: _openTripPicker,
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
