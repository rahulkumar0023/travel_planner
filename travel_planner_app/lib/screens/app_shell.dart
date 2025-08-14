import 'package:flutter/material.dart';

import '../models/trip.dart';
import 'dashboard_screen.dart';
import 'group_balance_screen.dart';
import 'trip_form_screen.dart';
import 'trip_picker_screen.dart';
import 'itinerary_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // Active trip lives here, passed to child screens
  Trip? _activeTrip;

  void _setActiveTrip(Trip t) => setState(() => _activeTrip = t);

  @override
  Widget build(BuildContext context) {
    final pages = [
      if (_activeTrip == null)
        const _PickTripFirst()
      else
        DashboardScreen(activeTrip: _activeTrip!),
      if (_activeTrip == null)
        const _PickTripFirst()
      else
        GroupBalanceScreen(activeTrip: _activeTrip!),
      TripPickerScreen(
        onPick: (t) {
          _setActiveTrip(t);
          setState(() => _index = 0);
        },
      ),
      ItineraryScreen(
        getActiveTrip: () => _activeTrip, // may be null until user picks
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_activeTrip?.name ?? 'Select a trip')),
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
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Itinerary',
          ),
        ],
      ),
      floatingActionButton: _index == 2
          ? FloatingActionButton.extended(
              onPressed: () async {
                // create trip
                final created = await Navigator.of(context).push<Trip>(
                  MaterialPageRoute(builder: (_) => const TripFormScreen()),
                );
                if (created != null) {
                  _setActiveTrip(created);
                  setState(() => _index = 0);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('New trip'),
            )
          : null,
    );
  }
}

class _PickTripFirst extends StatelessWidget {
  const _PickTripFirst();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.public, size: 56),
            SizedBox(height: 12),
            Text('Pick or create a trip to get started',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

