import 'package:flutter/material.dart';
import '../models/trip.dart';
import 'dashboard_screen.dart';
import 'group_balance_screen.dart';
import 'trip_picker_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // TODO: replace with your real trip selection persistence
  Trip _activeTrip = Trip(
    id: 't1',
    name: 'Italy Trip',
    startDate: DateTime(2025, 9, 1),
    endDate: DateTime(2025, 9, 10),
    initialBudget: 1500.0,
    currency: 'EUR',
    participants: const ['Rahul', 'Alex', 'Maya'],
  );

  void _setActiveTrip(Trip t) => setState(() => _activeTrip = t);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(activeTrip: _activeTrip),
      GroupBalanceScreen(activeTrip: _activeTrip!),
      TripPickerScreen(
        current: _activeTrip,
        onPick: (t) {
          _setActiveTrip(t);
          setState(() => _index = 0); // jump back to Dashboard
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_activeTrip.name)),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: pages[_index],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Balances',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Trips',
          ),
        ],
      ),
    );
  }
}
