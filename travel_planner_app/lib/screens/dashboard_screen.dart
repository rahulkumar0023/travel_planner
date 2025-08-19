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
import '../services/fx_service.dart';

import 'expense_form_screen.dart';
import 'group_balance_screen.dart';
import 'participants_screen.dart';
import 'settings_screen.dart';
import 'budgets_screen.dart';
import 'trip_selection_screen.dart';
// 👇 NEW import start
import '../services/budgets_sync.dart';
// 👇 NEW: read budgets cache to keep Home in sync with Budgets tab
import '../services/local_budget_store.dart';
// 👇 NEW import end
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


  double _spentInTripCcy = 0.0;
  bool _recalcInFlight = false; // just to avoid overlapping recalcs

  Trip? _activeTrip;
  late final Box<Expense> _box;
  List<Expense> _expenses = [];
  String? _homeCurrencyCode;
  double? _approxHomeValue;

  double? _tripBudgetOverride; // filled if we detect a matching Trip budget

  // --- linked monthly info for the active trip budget ---
  Budget? _tripBudgetObj;          // the trip's Budget row (kind=trip)
  Budget? _linkedMonthlyObj;       // the linked monthly budget, if any
  double? _budgetApproxInLinked;   // ≈ trip budget amount in the monthly currency

// initState patch start
  @override
  void initState() {
    super.initState();
    _box = Hive.box<Expense>('expensesBox');
    _boot(); // 👈 NEW

    // 👇 NEW: subscribe to budgets changes start
    BudgetsSync.instance.addListener(_onBudgetsChanged);
    // 👇 NEW: subscribe to budgets changes end

    // 👇 NEW: sync budget override from cache on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeSyncTripBudgetOverrideFromCache();
    });
  }
// initState patch end

  // 👇 NEW: boot sequence start
  Future<void> _boot() async {
    await _ensureActiveTrip();
    await _loadLocal();            // will recalc + then update home (see patch below)
    await _loadTripBudgetOverride();
  }


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

  // --- spend buckets helpers start ---
// Group local expenses by their *own* currency (PLN/EUR/TRY/etc.)
  Map<String, double> _bucketsByCurrency() {
    final m = <String, double>{};
    final tripCcy = _activeTrip?.currency ?? 'EUR';
    for (final e in _expenses) {
      final c = (e.currency.isEmpty) ? tripCcy : e.currency;
      m[c] = (m[c] ?? 0) + e.amount;
    }
    return m;
  }

  Future<Map<String, double>> _approxBucketsToTrip(
      Map<String, double> buckets, String toCcy) async {
    final out = <String, double>{};
    for (final e in buckets.entries) {
      final from = e.key.toUpperCase();
      final amt  = e.value;
      if (amt == 0) continue;

      if (from == toCcy.toUpperCase()) {
        out[from] = amt;
      } else {
        try {
          out[from] = await widget.api.convert(amount: amt, from: from, to: toCcy);
        } catch (_) {
          out[from] = amt; // safe fallback
        }
      }
    }
    return out;
  }



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

// --- recalc spent in trip currency start ---
  Future<void> _recalcSpentInTripCurrency() async {
    final t = _activeTrip;
    if (t == null) {
      if (mounted) setState(() => _spentInTripCcy = 0.0);
      return;
    }
    if (_recalcInFlight) return;
    _recalcInFlight = true;

    try {
      // 1) group all expenses by their own currency
      final buckets = _bucketsByCurrency(); // e.g. { 'PLN': 50.0, 'INR': 300.0, ... }

      // 2) convert each bucket to the TRIP currency using the backend converter
      double total = 0.0;
      for (final entry in buckets.entries) {
        final from = entry.key.toUpperCase();
        final amt  = entry.value;
        if (amt == 0) continue;

        final converted = (from == t.currency.toUpperCase())
            ? amt
            : await widget.api.convert(amount: amt, from: from, to: t.currency);

        total += converted;
      }

      if (!mounted) return;
      setState(() => _spentInTripCcy = total);

      // 👇 NEW: keep the “≈ home” line in sync with the fresh total
      await _updateApproxHome();
    } catch (e) {
      // fallback: naive sum so the UI doesn't break
      final fallback = _expenses.fold<double>(0.0, (p, e) => p + e.amount);
      if (mounted) setState(() => _spentInTripCcy = fallback);
    } finally {
      _recalcInFlight = false;
    }
  }
// --- recalc spent in trip currency end ---




// _loadLocal method start (unchanged header)
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


    await _recalcSpentInTripCurrency();
    await _updateApproxHome();
  }
// _loadLocal method end


  Future<void> _updateApproxHome() async {
    final t = _activeTrip;
    if (t == null) return;
    try {
      final home = await PrefsService.getHomeCurrency();
      final approx = await widget.api.convert(
        amount: _spentInTripCcy,
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

      // 1) find the trip budget for the current trip (by tripId or name)
      Budget? tripB;
      for (final b in all) {
        if (b.kind == BudgetKind.trip &&
            ((b.tripId != null && b.tripId == t.id) ||
                ((b.name ?? '').toLowerCase() == t.name.toLowerCase()))) {
          tripB = b;
          break;
        }
      }

      // 2) locate the linked monthly (if any)
      Budget? linked;
      if (tripB?.linkedMonthlyBudgetId != null) {
        for (final b in all) {
          if (b.kind == BudgetKind.monthly && b.id == tripB!.linkedMonthlyBudgetId) {
            linked = b;
            break;
          }
        }
      }

      // 3) compute ≈ of the trip *budget amount* in the linked monthly currency
      double? approx;
      if (tripB != null && linked != null) {
        try {
          approx = await widget.api.convert(
            amount: tripB.amount,
            from: tripB.currency,
            to: linked.currency,
          );
        } catch (_) {
          approx = null;
        }
      }

      if (!mounted) return;
      setState(() {
        _tripBudgetOverride   = tripB?.amount; // keep your override logic
        _tripBudgetObj        = tripB;
        _linkedMonthlyObj     = linked;
        _budgetApproxInLinked = approx;
      });
    } catch (_) {
      // ignore; card will simply omit the linked lines
    }
  }

  String _linkedMonthlyLabel() {
    final m = _linkedMonthlyObj;
    if (m == null) return 'Not linked';
    final mm = m.month ?? 0;
    final yy = m.year ?? 0;
    const names = ['', 'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final when = (mm >= 1 && mm <= 12 && yy > 0) ? '${names[mm]} $yy' : (m.name ?? 'Monthly');
    return 'Linked to $when Budget (${m.currency})';
  }

  // _maybeSyncTripBudgetOverrideFromCache start
  Future<void> _maybeSyncTripBudgetOverrideFromCache() async {
    final t = _activeTrip;
    if (t == null) return;

    // Read cached budgets (written by Budgets screen / fetchBudgetsOrCache).
    final cached = await LocalBudgetStore.load();

    Budget? match;
    for (final b in cached) {
      if (b.kind == BudgetKind.trip &&
          (b.tripId == t.id ||
              ((b.name ?? '').toLowerCase() == t.name.toLowerCase()))) {
        match = b;
        break;
      }
    }

    final newAmt = match?.amount;
    if (newAmt != null && newAmt != _tripBudgetOverride) {
      if (!mounted) return;
      setState(() => _tripBudgetOverride = newAmt);
    }
  }
  // _maybeSyncTripBudgetOverrideFromCache end

  // _maybeRefreshOverrideFromServer start
  Future<void> _maybeRefreshOverrideFromServer() async {
    try {
      await _loadTripBudgetOverride();
    } catch (_) {/* ignore */}
  }
  // _maybeRefreshOverrideFromServer end

  Future<void> _clearTripSelection() async {
    await TripStorageService.clear();
    widget.onSwitchTrip();
  }

// 👇 NEW: budgets change handler
// _onBudgetsChanged method start
  void _onBudgetsChanged() async {
    // Re-read the matching Trip Budget (so “Budget: …” stays correct)
    await _loadTripBudgetOverride();
    // Optional: also refresh conversions if you want
    await _updateApproxHome();
    if (mounted) setState(() {}); // repaint the card
  }
// _onBudgetsChanged method end

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
            await _recalcSpentInTripCurrency();
            await _updateApproxHome();
          },
        ),
      ),
    );
  }



  // 👇 NEW: dispose listener start
  @override
  void dispose() {
    BudgetsSync.instance.removeListener(_onBudgetsChanged);
    super.dispose();
  }
// 👇 NEW: dispose listener end


  @override
  Widget build(BuildContext context) {
    final t = _activeTrip;

    // 👇 NEW: cheap check from cache & optional server refresh after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeSyncTripBudgetOverrideFromCache();
      _maybeRefreshOverrideFromServer();
    });

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
        // AppBar two-line title start
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _activeTrip!.name,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Dashboard',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        // AppBar two-line title end
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
                    final spent = _spentInTripCcy;
                    final remainingRaw = budget - spent;
                    final remaining = remainingRaw < 0 ? 0 : remainingRaw; // clamp to 0
                    final overBy = remainingRaw < 0 ? -remainingRaw : 0;



// budget card -> Builder(...) start
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Trip name header start
                        Text(
                          _activeTrip!.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        // Trip name header end

                        // --- compute numbers (trip currency) ---
                        // 👇 NEW: always use the FX-correct total we recalc into _spentInTripCcy
                        Text(
                          hasBudget
                              ? 'Budget: ${budget.toStringAsFixed(0)} ${t.currency}'
                              : 'Budget: Not set',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),

                        // Spent/Remaining in TRIP currency
                        Text('Spent: ${_spentInTripCcy.toStringAsFixed(2)} ${t.currency}'),
                        if (hasBudget) ...[
                          // clamp remaining to 0, show "Over by" when exceeded
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
                              await _loadTripBudgetOverride(); // refresh after returning
                              await _recalcSpentInTripCurrency(); // 👈 NEW
                              await _updateApproxHome();          // 👈 NEW
                            },
                          ),
                        ],

                        // approx home line start
                        if (_approxHomeValue != null &&
                            _homeCurrencyCode != null &&
                            _homeCurrencyCode!.toUpperCase() != t.currency.toUpperCase()) ...[
                          const SizedBox(height: 8),
                          Text('≈ ${_approxHomeValue!.toStringAsFixed(2)} $_homeCurrencyCode'),
                        ],
                        // approx home line end

                        // --- linked monthly info (always show a label; ≈ line only when computed) ---
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.link, size: 14),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _linkedMonthlyLabel(),
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (_linkedMonthlyObj != null && _budgetApproxInLinked != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '≈ ${_budgetApproxInLinked!.toStringAsFixed(2)} ${_linkedMonthlyObj!.currency} (linked)',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),

                        // -----------------------
                        // 👇 NEW: Per-currency breakdown (backend conversion, null-safe)
                        const SizedBox(height: 8),
                        Text('Spent currencies:', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),

                        Builder(builder: (_) {
                          final buckets = _bucketsByCurrency();     // build once to avoid rebuild drift
                          final codes = buckets.keys.toList()..sort();
                          if (codes.isEmpty) return const SizedBox.shrink();

                          return FutureBuilder<Map<String, double>>(
                            future: _approxBucketsToTrip(buckets, t.currency),
                            builder: (_, snap) {
                              final approx = snap.data; // may be null while waiting
                              final rows = <Widget>[];

                              for (final c in codes) {
                                final raw = buckets[c] ?? 0.0;
                                if (c.toUpperCase() == t.currency.toUpperCase()) {
                                  rows.add(Text('${raw.toStringAsFixed(2)} $c'));
                                } else if (approx == null || !approx.containsKey(c)) {
                                  rows.add(Text('${raw.toStringAsFixed(2)} $c (≈ … ${t.currency})'));
                                } else {
                                  rows.add(Text(
                                    '${raw.toStringAsFixed(2)} $c (≈ ${approx[c]!.toStringAsFixed(2)} ${t.currency})',
                                  ));
                                }
                              }

                              rows.add(const SizedBox(height: 4));
                              rows.add(Text(
                                'Total spent: ${_spentInTripCcy.toStringAsFixed(2)} ${t.currency}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ));

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: rows,
                              );
                            },
                          );
                        }),

                      ],
                    );
// budget card -> Builder(...) end

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
