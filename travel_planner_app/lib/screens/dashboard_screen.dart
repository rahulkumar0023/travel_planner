// imports patch start
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/trip.dart';
import '../models/expense.dart';
import '../models/budget.dart';
import '../models/currencies.dart';

import 'dart:io';
import 'dart:convert';

import '../services/api_service.dart';
import '../services/prefs_service.dart';
import '../services/trip_storage_service.dart';
import '../services/local_trip_store.dart'; // <-- keep
import '../services/participants_service.dart';
import '../services/fx_service.dart';
import '../services/archived_trips_store.dart';
import '../services/outbox_service.dart';

import 'expense_form_screen.dart';
import 'group_balance_screen.dart';
import 'participants_screen.dart';
import 'settings_screen.dart';
import 'budgets_screen.dart';
import 'trip_selection_screen.dart';
import 'receipt_viewer_screen.dart'; // NEW file below
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

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  // --- multi-currency spent state ---
  final Map<String, double> _spentByCurrency = <String, double>{};
  double _spentInTripCcy = 0.0;
  bool _recalcInFlight = false;

  Trip? _activeTrip;
  late final Box<Expense> _box;
  List<Expense> _expenses = [];
  String? _homeCurrencyCode;
  double? _approxHomeValue;

  double? _tripBudgetOverride; // filled if we detect a matching Trip budget

  // Insights state
  Map<String, double> _byCcy = <String, double>{};          // e.g. {'EUR': 50, 'INR': 10_000}
  Map<String, double> _byCategoryBase = <String, double>{}; // in trip currency
  double _spentInBase = 0.0;
  double _dailyBurn = 0.0;
  int? _daysLeft;

  bool _isArchivedTrip = false;

  // --- linked monthly info for the active trip budget ---
  Budget? _tripBudgetObj;          // the trip's Budget row (kind=trip)
  Budget? _linkedMonthlyObj;       // the linked monthly budget, if any
  double? _budgetApproxInLinked;   // ≈ trip budget amount in the monthly currency

// initState patch start
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flushOutbox();
    _box = Hive.box<Expense>('expensesBox');
    _boot(); // 👈 NEW

    // 👇 NEW: subscribe to budgets changes start
    BudgetsSync.instance.addListener(_onBudgetsChanged);
    // 👇 NEW: subscribe to budgets changes end

    // 👇 NEW: sync budget override from cache on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeSyncTripBudgetOverrideFromCache();
      _syncActiveTripExpenses();
    });
  }
// initState patch end

  // 👇 NEW: boot sequence start
  Future<void> _boot() async {
    await _ensureActiveTrip();
    await _loadLocal();            // will recalc + then update home (see patch below)
    await _loadTripBudgetOverride();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadLocal().then((_) => _recalcSpentInTripCurrency());
    final id = _activeTrip?.id;
    if (id != null) {
      ArchivedTripsStore.isArchived(id).then((v) {
        if (mounted) setState(() => _isArchivedTrip = v);
      });
    } else {
      if (mounted) setState(() => _isArchivedTrip = false);
    }
  }


  // _ensureActiveTrip method start
  Future<void> _ensureActiveTrip() async {
    _activeTrip = TripStorageService.loadLightweight();
    if (_activeTrip == null) {
      if (mounted) setState(() => _isArchivedTrip = false); // triggers empty-state
      return;
    }
    // Optional: verify it still exists in cache so deleted trips don't show
    try {
      final cached = await LocalTripStore.load();
      final exists = cached.any((t) => t.id == _activeTrip!.id);
      if (!exists) {
        await TripStorageService.clear();
        _activeTrip = null;
        if (mounted) setState(() => _isArchivedTrip = false);
        return;
      }
    } catch (_) {}
    _isArchivedTrip = await ArchivedTripsStore.isArchived(_activeTrip!.id);
    if (mounted) setState(() {});
  }
// _ensureActiveTrip method end

// _openTripPicker method (final) start
  Future<void> _openTripPicker() async {
    final picked = await Navigator.of(context).push<Trip>(
      MaterialPageRoute(builder: (_) => TripSelectionScreen(api: widget.api)),
    );
    if (picked != null) {
      await TripStorageService.save(picked);
      final arch = await ArchivedTripsStore.isArchived(picked.id);
      if (!mounted) return;
      setState(() {
        _activeTrip = picked;
        _isArchivedTrip = arch;
      });
      await _syncActiveTripExpenses();
      await _loadTripBudgetOverride();
      await _updateApproxHome();
    }
  }
// _openTripPicker method (final) end

// Recalculate _spentByCurrency and _spentInTripCcy using FxService (base = trip currency)
  Future<void> _recalcSpentInTripCurrency() async {
    final t = _activeTrip;
    if (t == null) {
      if (mounted) {
        setState(() {
          _spentByCurrency.clear();
          _spentInTripCcy = 0.0;
        });
      }
      return;
    }
    if (_recalcInFlight) return;
    _recalcInFlight = true;

    try {
      final base = t.currency.toUpperCase();
      final rates = await FxService.loadRates(base); // cached by base

      final by = <String, double>{};
      double total = 0.0;

      for (final e in _expenses) {
        final from = (e.currency.isEmpty ? base : e.currency).toUpperCase();
        by[from] = (by[from] ?? 0) + e.amount;

        total += FxService.convert(
          amount: e.amount,
          from: from,
          to: base,
          ratesForBaseTo: rates,
        );
      }

      if (!mounted) return;
      setState(() {
        _spentByCurrency
          ..clear()
          ..addAll(by);
        _spentInTripCcy = total;
      });
    } finally {
      _recalcInFlight = false;
    }
  }

  Future<void> _recomputeInsights() async {
    final t = _activeTrip;
    if (t == null) return;

    // 1) group by currency (raw)
    final byCcy = <String, double>{};
    for (final e in _expenses) {
      final c = (e.currency.isEmpty ? t.currency : e.currency).toUpperCase();
      byCcy[c] = (byCcy[c] ?? 0) + e.amount;
    }

    // 2) convert every expense to trip currency (one FX table)
    final rates = await FxService.loadRates(t.currency);
    double sumBase = 0.0;
    final byCatBase = <String, double>{};
    for (final e in _expenses) {
      final from = (e.currency.isEmpty ? t.currency : e.currency).toUpperCase();
      final base = FxService.convert(
        amount: e.amount,
        from: from,
        to: t.currency,
        ratesForBaseTo: rates,
      );
      sumBase += base;
      final cat = (e.category.isEmpty ? 'Other' : e.category);
      byCatBase[cat] = (byCatBase[cat] ?? 0) + base;
    }

    // 3) daily burn & days left
    final daysSoFar = (DateTime.now().difference(t.startDate).inDays + 1).clamp(1, 36500);
    final burn = sumBase / daysSoFar;
    int? daysLeft;
    final budget = (_tripBudgetOverride ?? t.initialBudget);
    if (budget > 0 && burn > 0) {
      final rem = (budget - sumBase);
      daysLeft = rem <= 0 ? 0 : (rem / burn).ceil();
    }

    if (!mounted) return;
    setState(() {
      _byCcy = byCcy;
      _byCategoryBase = byCatBase;
      _spentInBase = sumBase;
      _dailyBurn = burn;
      _daysLeft = daysLeft;
    });
  }




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
    await _recomputeInsights();
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

  Future<void> _syncActiveTripExpenses({bool silent = true}) async {
    final t = _activeTrip;
    if (t == null) return;
    try {
      // 1) pull latest from server
      final remote = await widget.api.fetchExpenses(t.id);

      // 2) wipe this trip's local rows and re-add from server
      final toDelete = _box.values.where((e) => e.tripId == t.id).toList();
      for (final e in toDelete) {
        try {
          await e.delete();
        } catch (_) {}
      }
      for (final r in remote) {
        await _box.add(r);
      }

      // 3) refresh UI + totals
      await _loadLocal();
      await _recalcSpentInTripCurrency();
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Expenses synced')));
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
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

  Future<void> _manageSpendCurrencies() async {
    final trip = _activeTrip;
    if (trip == null) return;

    final base = trip.currency.toUpperCase();
    final selected = <String>{...((trip.spendCurrencies) ?? const <String>[])}
        .map((e) => e.toUpperCase())
        .where((c) => c != base)
        .toSet();

    final all = [...kCurrencyCodes]..sort();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String? addPick;
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(builder: (ctx, setBtm) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Spend currencies', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Base currency', style: Theme.of(ctx).textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    Chip(label: Text(base), avatar: const Icon(Icons.star, size: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Extra currencies', style: Theme.of(ctx).textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: selected.isEmpty
                      ? [Text('None', style: Theme.of(ctx).textTheme.bodySmall)]
                      : selected.map((c) => InputChip(
                          label: Text(c),
                          onDeleted: () => setBtm(() => selected.remove(c)),
                        )).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: addPick,
                        hint: const Text('Add currency'),
                        isExpanded: true,
                        items: all
                            .where((c) => c != base && !selected.contains(c))
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setBtm(() => addPick = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: (addPick == null)
                          ? null
                          : () => setBtm(() {
                                selected.add(addPick!);
                                addPick = null;
                              }),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                      onPressed: () async {
                        final updated = Trip(
                          id: trip.id,
                          name: trip.name,
                          startDate: trip.startDate,
                          endDate: trip.endDate,
                          initialBudget: trip.initialBudget,
                          currency: trip.currency,
                          participants: trip.participants,
                          spendCurrencies: selected.toList(),
                        );
                        await TripStorageService.save(updated);
                        try { await widget.api.updateTrip(updated); } catch (_) {}
                        if (!mounted) return;
                        setState(() => _activeTrip = updated);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Spend currencies updated')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            );
          }),
        );
      },
    );
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
            String? receiptPath, // NEW
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
              receiptPath: receiptPath,                 // NEW
            );
            await _box.add(e); // local first (Hive)
            setState(() => _expenses.insert(0, e));
            await _recalcSpentInTripCurrency();
            await _recomputeInsights();
            await _updateApproxHome();

            // 2) ALSO sync to server so Budgets can see it
            try {
              await widget.api.addExpense(e);
            } catch (err) {
              await OutboxService.enqueue(OutboxOp(
                method: 'POST',
                path: '/expenses',
                jsonBody: jsonEncode(e.toJson()),
              ));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved offline — will sync automatically')),
                );
              }
            }
          },
        ),
      ),
    );
  }



  // 👇 NEW: dispose listener start
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BudgetsSync.instance.removeListener(_onBudgetsChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _flushOutbox();
    }
  }

  Future<void> _flushOutbox() async {
    final sent = await OutboxService.flush(
      urlFor: widget.api.urlFor,
      headers: widget.api.headers,
    );
    if (sent > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synced $sent pending item(s)')),
      );
    }
    setState(() {});
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
          // OUTBOX BADGE
          FutureBuilder<int>(
            future: OutboxService.count(),
            builder: (_, snap) {
              final cnt = snap.data ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: cnt == 0 ? 'All synced' : 'Pending sync',
                    onPressed: _flushOutbox,
                    icon: Icon(cnt == 0 ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
                  ),
                  if (cnt > 0)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            onPressed: _openTripPicker,
            icon: const Icon(Icons.swap_horiz),
          ),
          IconButton(
            onPressed: _clearTripSelection,
            icon: const Icon(Icons.logout),
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
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'currencies') _manageSpendCurrencies();
              if (v == 'balances') {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => GroupBalanceScreen(tripId: _activeTrip!.id, currency: _activeTrip!.currency, api: widget.api, participants: _activeTrip!.participants, spendCurrencies: _activeTrip!.spendCurrencies),
                ));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'currencies', child: Text('Spend currencies…')),
              PopupMenuItem(value: 'balances', child: Text('View balances')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isArchivedTrip ? null : _addExpenseForm, // or _addExpenseQuick for quick test
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isArchivedTrip)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.archive_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('This trip is archived'),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(builder: (context) {
                    // assumes you already added:
                    // - double? _tripBudgetOverride;
                    // - double _spentInTripCcy; // FX-correct spent total
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

                        // Spent-by-currency breakdown (with approx to trip currency)
                        const SizedBox(height: 8),
                        Text('Spent currencies:', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        ..._spentByCurrency.entries.map((entry) {
                          final ccy = entry.key;
                          final amt = entry.value;
                          if (ccy.toUpperCase() == _activeTrip!.currency.toUpperCase()) {
                            return Text('${amt.toStringAsFixed(2)} $ccy');
                          }
                          // show ≈ line using FxService (cached)
                          return FutureBuilder<double>(
                            future: () async {
                              final base = _activeTrip!.currency.toUpperCase();
                              final rates = await FxService.loadRates(base);
                              return FxService.convert(
                                amount: amt,
                                from: ccy.toUpperCase(),
                                to: base,
                                ratesForBaseTo: rates,
                              );
                            }(),
                            builder: (_, snap) {
                              final approx = snap.data;
                              final approxTxt = (approx == null)
                                  ? ''
                                  : ' (≈ ${approx.toStringAsFixed(2)} ${_activeTrip!.currency})';
                              return Text('${amt.toStringAsFixed(2)} $ccy$approxTxt');
                            },
                          );
                        }).toList(),
                        Text('Total spent: ${_spentInTripCcy.toStringAsFixed(2)} ${_activeTrip!.currency}',
                            style: Theme.of(context).textTheme.bodySmall),

                      ],
                    );
// budget card -> Builder(...) end

                  }),

                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Insights (fixed math) ---
                  Text('Insights', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Daily burn: ${_dailyBurn.toStringAsFixed(2)} ${t.currency}/day'),
                      const SizedBox(width: 16),
                      Text('Days left: ${_daysLeft ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('By category', style: Theme.of(context).textTheme.bodyMedium),
                  Builder(builder: (_) {
                    if (_byCategoryBase.isEmpty) return const SizedBox.shrink();
                    final max = _byCategoryBase.values.fold<double>(0, (p, v) => v > p ? v : p);
                    return Column(
                      children: _byCategoryBase.entries.map((e) {
                        final pct = max <= 0 ? 0.0 : (e.value / max).clamp(0.0, 1.0);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(value: pct),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 120,
                                child: Text(
                                  '${e.key} • ${e.value.toStringAsFixed(2)} ${t.currency}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  }),
                  const SizedBox(height: 6),
                  // “Spent currencies” lines (unchanged list but now also correct overall totals)
                  if (_byCcy.isNotEmpty) ...[
                    Text('Spent currencies:', style: Theme.of(context).textTheme.bodyMedium),
                    ..._byCcy.entries.map((e) {
                      final approx = e.key.toUpperCase() == t.currency.toUpperCase()
                          ? ''
                          : ' (≈ using FX)';
                      return Text('${e.value.toStringAsFixed(2)} ${e.key}$approx');
                    }),
                    Text('Total spent: ${_spentInBase.toStringAsFixed(2)} ${t.currency}'),
                  ],
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
                leading: (e.receiptPath != null && e.receiptPath!.isNotEmpty)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(e.receiptPath!),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.receipt_long_outlined),
                title: Text(e.title),
                subtitle: Text(
                  '${e.category} • ${e.paidBy} • ${e.date.toLocal().toString().split(' ').first}',
                ),
                onTap: () {
                  if (e.receiptPath == null || e.receiptPath!.isEmpty) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReceiptViewerScreen(path: e.receiptPath!),
                    ),
                  );
                },
                trailing: Text('${e.amount.toStringAsFixed(2)} ${e.currency}'),
              ),
            ),
        ],
      ),
    );
  } 
}

