// imports patch start
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/trip.dart';
import '../models/expense.dart';
import '../models/budget.dart';

import '../services/api_service.dart';
import '../services/prefs_service.dart';
import '../services/trip_storage_service.dart';
import '../services/local_trip_store.dart'; // <-- keep
import '../services/participants_service.dart';

import 'expense_form_screen.dart';
import 'group_balance_screen.dart';
import 'participants_screen.dart';
import 'settings_screen.dart';
import 'budgets_screen.dart';
import 'trip_selection_screen.dart';        // <-- keep
// imports patch end


class DashboardScreen extends StatefulWidget {
  final VoidCallback onSwitchTrip;
  final ApiService api;

  const DashboardScreen({
    super.key,
    required this.onSwitchTrip,
    required this.api,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Trip? _activeTrip;
  late final Box<Expense> _box;
  List<Expense> _expenses = [];
  String? _homeCurrencyCode;
  double? _approxHomeValue;

  double? _tripBudgetOverride; // filled if we detect a matching Trip budget

// initState patch start
  @override
  void initState() {
    super.initState();
    _ensureActiveTrip(); // <- add missing semicolon

    _box = Hive.box<Expense>('expensesBox');
    _loadLocal();
    _updateApproxHome();
    _loadTripBudgetOverride();
  }
// initState patch end


  double get _totalSpent =>
      _expenses.fold<double>(0, (sum, e) => sum + e.amount);

  // _ensureActiveTrip method start
  Future<void> _ensureActiveTrip() async {
    _activeTrip = TripStorageService.loadLightweight();
    if (_activeTrip == null) {
      if (mounted) setState(() {}); // triggers empty-state
      return;
    }
    // Optional: verify it still exists in cache so deleted trips don't show
    try {
      final cached = await LocalTripStore.load();
      final exists = cached.any((t) => t.id == _activeTrip!.id);
      if (!exists) {
        await TripStorageService.clear();
        _activeTrip = null;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }
// _ensureActiveTrip method end

// _openTripPicker method (final) start
  Future<void> _openTripPicker() async {
    final picked = await Navigator.of(context).push<Trip>(
      MaterialPageRoute(builder: (_) => TripSelectionScreen(api: widget.api)),
    );
    if (picked != null) {
      await TripStorageService.save(picked);
      setState(() => _activeTrip = picked);
      // refresh dependent UI
      await _loadLocal();
      await _updateApproxHome();
      await _loadTripBudgetOverride();
    }
  }
// _openTripPicker method (final) end




  Future<void> _loadLocal() async {
    final t = _activeTrip;
    if (t == null) {
      setState(() => _expenses = []);
      return;
    }
    final all = _box.values.toList();
    setState(() {
      _expenses = all.where((e) => e.tripId == t.id).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    });
  }

  Future<void> _updateApproxHome() async {
    final t = _activeTrip;
    if (t == null) return;
    try {
      final home = await PrefsService.getHomeCurrency();
      final approx = await widget.api.convert(
        amount: _totalSpent,
        from: t.currency,
        to: home,
      );
      if (!mounted) return;
      setState(() {
        _homeCurrencyCode = home;
        _approxHomeValue = approx;
      });
    } catch (_) {
      // ignore conversion errors for now
    }
  }

  Future<void> _loadTripBudgetOverride() async {
    final t = _activeTrip;
    if (t == null) return;
    try {
      final all = await widget.api.fetchBudgetsOrCache();
      Budget? match;
      for (final b in all) {
        if (b.kind == BudgetKind.trip &&
            ((b.tripId != null && b.tripId == t.id) ||
                ((b.name ?? '').toLowerCase() == t.name.toLowerCase()))) {
          match = b;
          break;
        }
      }
      if (!mounted) return;
      setState(() => _tripBudgetOverride = match?.amount);
    } catch (_) {
      // Ignore errors; we’ll just keep using Trip.initialBudget
    }
  }

  Future<void> _clearTripSelection() async {
    await TripStorageService.clear();
    widget.onSwitchTrip();
  }

  Future<void> _addExpenseForm() async {
    final t = _activeTrip;
    if (t == null) return;

    // Fetch participants from your participants service (NOT http)
    final List<String> participants = t.participants; // fallback to trip participants

    // 👇 NEW: collect currencies for this trip
    final budgets = await widget.api.fetchBudgetsOrCache();
    final tripCurrencies = <String>{
      t.currency.toUpperCase(), // always include trip base currency
    };
    for (final b in budgets) {
      if (b.kind == BudgetKind.trip && b.tripId == t.id) {
        tripCurrencies.add(b.currency.toUpperCase());
      }
    }
    final availableCurrencies = tripCurrencies.toList()..sort();

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          participants: participants,
          defaultCurrency: t.currency,
          availableCurrencies: availableCurrencies, // 👈 pass choices here
          onSubmit: ({
            required String title,
            required double amount,
            required String category,
            required String paidBy,
            required List<String> sharedWith,
            required String currency, // <-- new param
          }) async {
            final e = Expense(
              id: DateTime.now().toIso8601String(),
              tripId: t.id,
              title: title,
              amount: amount,
              category: category,
              date: DateTime.now(),
              paidBy: paidBy,
              sharedWith: sharedWith,
              currency : currency, // <-- new param
            );
            await _box.add(e); // local first (Hive)
            setState(() => _expenses.insert(0, e));
            _updateApproxHome();
          },
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final t = _activeTrip;

    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No trip selected'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _openTripPicker,
                child: const Text('Select a trip'),
              ),
            ],
          ),
        ),
      );
    }

    final spent = _totalSpent;
    final remaining = (t.initialBudget) - spent;

    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard • ${t.name}'),
        actions: [
          IconButton(
            onPressed: _openTripPicker,
            icon: const Icon(Icons.swap_horiz),
          ),
          IconButton(
            onPressed: _clearTripSelection,
            icon: const Icon(Icons.logout),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Balances',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupBalanceScreen(
                    tripId: t.id,
                    currency: t.currency,
                    api: widget.api,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(api: widget.api),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Participants',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ParticipantsScreen(tripId: t.id),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExpenseForm, // or _addExpenseQuick for quick test
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(builder: (context) {
                    // assumes you already added:
                    // - double? _tripBudgetOverride;
                    // - double _totalSpent; (your existing spent computation)
                    // - double? _approxHomeValue; String? _homeCurrencyCode; (optional approx line)
                    // - import 'budgets_screen.dart';
                    final t = _activeTrip!;
                    final budget = (_tripBudgetOverride ?? t.initialBudget);
                    final hasBudget = budget > 0;
                    final spent = _totalSpent;
                    final remainingRaw = budget - spent;
                    final remaining = remainingRaw < 0 ? 0 : remainingRaw; // clamp to 0
                    final overBy = remainingRaw < 0 ? -remainingRaw : 0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasBudget
                              ? 'Budget: ${budget.toStringAsFixed(0)} ${t.currency}'
                              : 'Budget: Not set',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('Spent: ${spent.toStringAsFixed(2)} ${t.currency}'),
                        if (hasBudget) ...[
                          Text('Remaining: ${remaining.toStringAsFixed(2)} ${t.currency}'),
                          if (overBy > 0)
                            Text(
                              'Over by: ${overBy.toStringAsFixed(2)} ${t.currency}',
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                        ] else ...[
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.savings_outlined),
                            label: const Text('Set trip budget'),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => BudgetsScreen(api: widget.api)),
                              );
                              if (!mounted) return;
                              _loadTripBudgetOverride(); // refetch after returning
                            },
                          ),
                        ],
                        if (_approxHomeValue != null && _homeCurrencyCode != null) ...[
                          const SizedBox(height: 8),
                          Text('≈ ${_approxHomeValue!.toStringAsFixed(2)} $_homeCurrencyCode'),
                        ],
                      ],
                    );
                  }),

                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Recent expenses',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_expenses.isEmpty)
            const Text('No expenses yet. Tap + to add one.')
          else
            ..._expenses.reversed.map(
              (e) => ListTile(
                title: Text(e.title),
                subtitle: Text(
                  '${e.category} • ${e.paidBy} • ${e.date.toLocal().toString().split(' ').first}',
                ),
                trailing: Text('${e.amount.toStringAsFixed(2)} ${e.currency}'),
              ),
            ),
        ],
      ),
    );
  }
}
