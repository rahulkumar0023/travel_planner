// app_shell imports patch start
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/deep_link_service.dart';
import '../services/local_trip_store.dart';
import '../services/trip_storage_service.dart';
import 'budgets_screen.dart';
import 'dashboard_screen.dart';
import 'expenses_screen.dart';
import 'monthly_budget_screen.dart'; // 👈 NEW
import 'sign_in_screen.dart';
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
  StreamSubscription<JoinInvite>? _inviteSub;
  Future<void> _joinQueue = Future.value();
  final Set<String> _consumedInvites = <String>{};
// app_shell dashboard key field end

  @override
  void initState() {
    super.initState();
    _activeTrip = TripStorageService.loadLightweight();

    DeepLinkService.instance.ensureStarted();
    _inviteSub = DeepLinkService.instance.joinStream.listen(_handleJoinInvite);
    final pending = DeepLinkService.instance.takePendingJoin();
    if (pending != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _handleJoinInvite(pending));
    }

    // If no trip is selected yet, open the picker after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ensure signed in first (restore secure storage-backed session)
      final restored = await widget.api.restoreSession();
      if (!restored && mounted) {
        final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => SignInScreen(api: widget.api)),
        );
        if (!mounted) return;
        if (ok != true) return; // user cancelled sign-in
      }

      if (_activeTrip == null && mounted) {
        final picked = await Navigator.of(context).push<Trip>(
          MaterialPageRoute(
              builder: (_) => TripSelectionScreen(api: widget.api)),
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
  void dispose() {
    _inviteSub?.cancel();
    super.dispose();
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
      MonthlyBudgetScreen(api: widget.api), // 👈 NEW: fourth tab
    ];

    return Scaffold(
      body: tabs[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'Expenses'),
          NavigationDestination(
              icon: Icon(Icons.savings_outlined), label: 'Budgets'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Monthly'), // 👈 NEW
        ],
      ),
    );
  }

  void _handleJoinInvite(JoinInvite invite) {
    _joinQueue = _joinQueue.then((_) => _processInvite(invite));
  }

  Future<void> _processInvite(JoinInvite invite) async {
    if (!mounted) return;
    if (_consumedInvites.contains(invite.raw)) return;

    if (!await widget.api.hasToken()) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => SignInScreen(api: widget.api)),
      );
      final signedInAfterFlow = ok == true && await widget.api.hasToken();
      if (!signedInAfterFlow) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to accept trip invites.')),
        );
        return;
      }
    }

    _consumedInvites.add(invite.raw);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
          content: Text('Joining trip...'), duration: Duration(seconds: 2)),
    );

    try {
      await widget.api.joinTrip(invite.tripId, invite.token);
      final trips = await widget.api.fetchTrips();
      await LocalTripStore.save(trips);
      Trip? joined;
      for (final t in trips) {
        if (t.id == invite.tripId) {
          joined = t;
          break;
        }
      }

      if (joined != null) {
        await TripStorageService.save(joined);
        if (!mounted) return;
        setState(() {
          _activeTrip = joined;
          _dashKey = UniqueKey();
        });
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text('Joined ${joined.name}.')),
        );
      } else {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
              content: Text(
                  'Joined trip. Refresh your trips to see the latest details.')),
        );
      }
    } catch (e) {
      _consumedInvites.remove(invite.raw);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to join trip: $e')),
      );
    }
  }
}
