import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import '../models/budget.dart';
import '../services/fx_service.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> with TickerProviderStateMixin {
  late Future<List<Budget>> _future;
  String _home = TripStorageService.getHomeCurrency();

  // Budgets knownTripIds fields start
  final Map<String, double> _spentByTrip = {};      // (already present in your file)
  final Set<String> _spentLoadedFor = <String>{};   // (already present)
  Set<String> _knownTripIds = <String>{};           // NEW
  bool _loadingSpends = false;                      // (already present)
// Budgets knownTripIds fields end


  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchBudgetsOrCache();
    _loadTripIds();
  }

// Budgets _refresh sync start
  Future<void> _refresh() async {
    setState(() { _loadingSpends = true; });

    // 1) load known trips (server first, fallback inside the helper if you use it)
    List<Trip> trips = <Trip>[];
    try {
      trips = await widget.api.fetchTripsOrCache();  // requires LocalTripStore; else use fetchTrips()
    } catch (_) {}
    _knownTripIds = trips.map((t) => t.id).toSet();

    // 2) reload budgets
    setState(() {
      _future = widget.api.fetchBudgetsOrCache();
    });
    final budgets = await _future;

    // 3) clear spent caches for any removed trip
    _spentByTrip.removeWhere((tripId, _) => !_knownTripIds.contains(tripId));
    _spentLoadedFor.removeWhere((tripId) => !_knownTripIds.contains(tripId));

    // 4) recalc spends for the remaining visible budgets
    await _recalcSpends(budgets);

    if (!mounted) return;
    setState(() { _loadingSpends = false; });
  }
// Budgets _refresh sync end

// _loadTripIds method start
  Future<void> _loadTripIds() async {
    try {
      final trips = await widget.api.fetchTripsOrCache();
      _knownTripIds
        ..clear()
        ..addAll(trips.map((t) => t.id));
      if (mounted) setState(() {}); // let the filter re-run
    } catch (_) {
      // ignore; if trips can't be loaded, we just won't filter by ids yet
    }
  }
// _loadTripIds method end

  Future<void> _createMonthlyDialog() async {
    final now = DateTime.now();
    String _monthName(int m) =>
        const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];

    final nameCtrl   = TextEditingController(text: '${_monthName(now.month)} ${now.year}');
    final yearCtrl   = TextEditingController(text: now.year.toString());
    final monthCtrl  = TextEditingController(text: now.month.toString());
    final amountCtrl = TextEditingController();
    final currencyCtrl = TextEditingController(text: _home); // your home currency

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Monthly Budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name (optional)')),
            const SizedBox(height: 8),
            TextField(controller: yearCtrl,
                decoration: const InputDecoration(labelText: 'Year')),
            const SizedBox(height: 8),
            TextField(controller: monthCtrl,
                decoration: const InputDecoration(labelText: 'Month (1–12)')),
            const SizedBox(height: 8),
            TextField(controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount')),
            const SizedBox(height: 8),
            TextField(controller: currencyCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Currency (ISO 4217)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await widget.api.createBudget(
        kind: BudgetKind.monthly,
        currency: currencyCtrl.text.trim().toUpperCase(),
        amount: double.tryParse(amountCtrl.text.trim()) ?? 0,
        year: int.tryParse(yearCtrl.text.trim()),
        month: int.tryParse(monthCtrl.text.trim()),
        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Monthly budget created')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create budget: $e')),
        );
      }
    }
  }

  Future<void> _createTripDialog() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final currencyCtrl = TextEditingController(text: _home);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Trip Budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Krakow Trip)')),
            const SizedBox(height: 8),
            TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
            const SizedBox(height: 8),
            TextField(controller: currencyCtrl, decoration: const InputDecoration(labelText: 'Currency (ISO 4217)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.api.createBudget(
          kind: BudgetKind.trip,
          currency: currencyCtrl.text.trim().toUpperCase(),
          amount: double.tryParse(amountCtrl.text.trim()) ?? 0,
          name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        );
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trip budget created')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create budget: $e')),
          );
        }
      }
    }

  }

  Future<void> _editMonthly(Budget m) async {
    final yearCtrl = TextEditingController(text: (m.year ?? 0).toString());
    final monthCtrl = TextEditingController(text: (m.month ?? 0).toString());
    final amountCtrl = TextEditingController(text: m.amount.toString());
    final nameCtrl = TextEditingController(text: m.name ?? '');
    final currencyCtrl = TextEditingController(text: m.currency);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Monthly Budget'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (optional)')),
          const SizedBox(height: 8),
          TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: 'Year')),
          const SizedBox(height: 8),
          TextField(controller: monthCtrl, decoration: const InputDecoration(labelText: 'Month (1–12)')),
          const SizedBox(height: 8),
          TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
          const SizedBox(height: 8),
          TextField(controller: currencyCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Currency (ISO 4217)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.updateBudget(
        id: m.id,
        kind: BudgetKind.monthly,
        currency: currencyCtrl.text.trim().toUpperCase(),
        amount: double.tryParse(amountCtrl.text.trim()) ?? m.amount,
        year: int.tryParse(yearCtrl.text.trim()),
        month: int.tryParse(monthCtrl.text.trim()),
        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      );
      await _refresh();
      _showSnack('Monthly budget updated');
    } catch (e) {
      _showSnack('Could not update: $e');
    }
  }

  Future<void> _editTrip(Budget t) async {
    final nameCtrl = TextEditingController(text: t.name ?? '');
    final amountCtrl = TextEditingController(text: t.amount.toString());
    final currencyCtrl = TextEditingController(text: t.currency);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Trip Budget'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
          const SizedBox(height: 8),
          TextField(controller: currencyCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Currency (ISO 4217)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.updateBudget(
        id: t.id,
        kind: BudgetKind.trip,
        currency: currencyCtrl.text.trim().toUpperCase(),
        amount: double.tryParse(amountCtrl.text.trim()) ?? t.amount,
        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        tripId: t.tripId,
        linkedMonthlyBudgetId: t.linkedMonthlyBudgetId,
      );
      await _refresh();
      _showSnack('Trip budget updated');
    } catch (e) {
      _showSnack('Could not update: $e');
    }
  }

  Future<void> _deleteBudget(Budget b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete budget?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteBudget(b.id);
      await _refresh();
      _showSnack('Budget deleted');
    } catch (e) {
      _showSnack('Could not delete: $e');
    }
  }

  Future<void> _unlinkTrip(Budget t) async {
    try {
      await widget.api.unlinkTripBudget(tripBudgetId: t.id);
      await _refresh();
      _showSnack('Unlinked from monthly');
    } catch (e) {
      _showSnack('Could not unlink: $e');
    }
  }

  Future<void> _linkTripToMonthly(Budget trip, List<Budget> monthly) async {
    final selected = await showDialog<Budget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Link to monthly budget'),
        children: [
          for (final m in monthly)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text(
                (m.name?.isNotEmpty == true)
                    ? '${m.name} • ${m.amount.toStringAsFixed(0)} ${m.currency}'
                    : '${m.year}-${m.month?.toString().padLeft(2, '0')} • ${m.amount.toStringAsFixed(0)} ${m.currency}',
              ),
            )
        ],
      ),
    );
    if (selected != null) {
      await widget.api.linkTripBudget(tripBudgetId: trip.id, monthlyBudgetId: selected.id);
      _refresh();
    }
  }

  Future<double> _approx(String fromCurrency, double amount) async {
    _home = TripStorageService.getHomeCurrency();
    return widget.api.convert(
      amount: amount,
      from: fromCurrency.toUpperCase(),
      to: _home.toUpperCase(),
    );
  }

// _monthlyById + _linkedLabel methods start
  Budget? _monthlyById(String? id, List<Budget> monthly) {
    if (id == null) return null;
    for (final m in monthly) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Human-friendly label for the linked monthly budget.
  /// Examples:
  ///  - "Not linked"
  ///  - "Linked to Oct 2025 Budget (EUR)"
  String _linkedLabel(String? linkedMonthlyBudgetId, List<Budget> monthly) {
    final m = _monthlyById(linkedMonthlyBudgetId, monthly);
    if (m == null) return 'Not linked';
    // If you store month=1..12 and year like in the model:
    final mm = (m.month ?? 0);
    final yy = (m.year ?? 0);
    final monthNames = const [
      '', 'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final when = (mm >= 1 && mm <= 12 && yy > 0) ? '${monthNames[mm]} $yy' : (m.name ?? 'Monthly');
    return 'Linked to $when Budget (${m.currency})';
  }
// _monthlyById + _linkedLabel methods end


// // ➋ Build a friendly label for a linked monthly
//   String _linkedLabel(String? monthlyId, List<Budget> monthly) {
//     final m = _monthlyById(monthlyId, monthly);
//     if (m == null) return 'Not linked';
//     final yyMm = '${m.year}-${(m.month ?? 0).toString().padLeft(2, '0')}';
//     return 'Linked → ${ (m.name?.isNotEmpty == true) ? m.name! : yyMm }';
//   }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- money formatting + spent cache ---
// money formatter (very simple; replace with intl if you want)
  String _money(String ccy, num v) => '$ccy ${v.toStringAsFixed(0)}';

// // Cache: tripId -> spent amount
//   final Map<String, double> _spentByTrip = <String, double>{};
//   final Set<String> _spentLoadedFor = <String>{};
//   bool _loadingSpends = false;

// Schedule a recalc after the current frame (so we don't setState during build)
  void _scheduleSpendRecalc(List<Budget> all) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recalcSpends(all);
    });
  }

// _recalcSpends with FX start
// Recalculate spends for any trip budgets whose tripId we haven't loaded yet
  Future<void> _recalcSpends(List<Budget> all) async {
    // collect new tripIds to load
    final ids = <String>[];
    for (final b in all) {
      if (b.kind == BudgetKind.trip &&
          b.tripId != null &&
          !_spentLoadedFor.contains(b.tripId)) {
        ids.add(b.tripId!);
      }
    }
    if (ids.isEmpty) return;

    setState(() => _loadingSpends = true);

    try {
      await Future.wait(ids.map((id) async {
        // 1) find the trip budget for this tripId so we know the budget currency
        Budget? tripBudget;
        for (final cand in all) {
          if (cand.kind == BudgetKind.trip && cand.tripId == id) {
            tripBudget = cand;
            break;
          }
        }
        if (tripBudget == null) {
          // nothing to sum into (shouldn't happen), mark as loaded w/ zero
          _spentByTrip[id] = 0.0;
          _spentLoadedFor.add(id);
          return;
        }

        // 2) fetch expenses for this trip
        final expenses = await widget.api.fetchExpenses(id);

        // 3) load FX table for the target (budget) currency
        final rates = await FxService.loadRates(tripBudget.currency);

        // 4) sum after converting each expense amount to the budget currency
        double sum = 0.0;
        for (final e in expenses) {
          final fromCcy = (e.currency == null || e.currency.isEmpty)
              ? tripBudget.currency
              : e.currency; // fallback for legacy rows
          sum += FxService.convert(
            amount: e.amount,
            from: fromCcy,
            to: tripBudget.currency,
            ratesForBaseTo: rates,
          );
        }

        _spentByTrip[id] = sum;
        _spentLoadedFor.add(id);
      }));
    } catch (_) {
      // ignore; UI will just show 0 spent if something fails
    }

    if (!mounted) return;
    setState(() => _loadingSpends = false);
  }
// _recalcSpends with FX end





// ➌ Convert to a specific currency (used for “linked” ≈ line)
  Future<double?> _approxTo({
    required String from,
    required String to,
    required double amount,
  }) async {
    if (from.toUpperCase() == to.toUpperCase()) return amount;
    try {
      return await widget.api.convert(
        amount: amount,
        from: from.toUpperCase(),
        to: to.toUpperCase(),
      );
    } catch (_) {
      return null;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<List<Budget>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load budgets:\n${snap.error}'));
          }
          final all = snap.data ?? const <Budget>[];
          _scheduleSpendRecalc(all); // budgets = the full list you’re displaying
          // Budgets filter orphan start
// Keep all monthly budgets, but only keep trip budgets if we know their trip still exists
          final filtered = all.where((b) {
            if (b.kind != BudgetKind.trip) return true;     // keep monthly
            if (b.tripId == null) return false;             // malformed, hide
            return _knownTripIds.contains(b.tripId!);       // only show if the trip still exists
          }).toList();

// From here on, use 'filtered' instead of 'all'
          final monthly = filtered.where((b) => b.kind == BudgetKind.monthly).toList();
          final trips   = filtered.where((b) => b.kind == BudgetKind.trip).toList();
// Budgets filter orphan end

          final usingCache = widget.api.lastBudgetsFromCache;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (usingCache)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Showing cached budgets (offline or server unavailable). Pull to refresh.'),
                ),
              Text('Monthly', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (monthly.isEmpty)
                const Text('No monthly budgets yet.'),
              for (final m in monthly)
                FutureBuilder<double>(
                  future: _approx(m.currency, m.amount),
                  builder: (_, approx) => Card(
                    child: ListTile(
                      title: Text(
                        (m.name?.isNotEmpty == true)
                            ? '${m.name} • ${m.amount.toStringAsFixed(0)} ${m.currency}'
                            : '${m.year}-${m.month?.toString().padLeft(2, '0')} • ${m.amount.toStringAsFixed(0)} ${m.currency}',
                      ),
                      subtitle: Builder(builder: (ctx) {
                        // find all trip budgets that link to this monthly budget
                        final linkedTrips = trips.where((tb) => tb.linkedMonthlyBudgetId == m.id);
                        final spent = linkedTrips.fold<double>(0.0, (p, tb) => p + (_spentByTrip[tb.tripId ?? ''] ?? 0.0));
                        final remaining = (m.amount) - spent;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total: ${_money(m.currency, m.amount)}'),
                            Text('Spent: ${_money(m.currency, spent)}'),
                            Text('Remaining: ${_money(m.currency, remaining)}'),
                          ],
                        );
                      }),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _editMonthly(m);
                          if (v == 'delete') _deleteBudget(m);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ),

                ),
              const SizedBox(height: 16),
              Text('Trip', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (trips.isEmpty)
                const Text('No trip budgets yet.'),
              for (final t in trips)
                FutureBuilder<double>(
                  future: _approx(t.currency, t.amount),
                  builder: (_, approx) => Card(
                    child: ListTile(
                      title: Text('${t.name ?? 'Trip'} • ${t.amount.toStringAsFixed(0)} ${t.currency}'),
                      // Trip budget subtitle patch start
                      subtitle: FutureBuilder<double?>(
                        // compute ≈ of the trip-budget amount in the linked monthly currency (if any)
                        future: () async {
                          final linked = _monthlyById(t.linkedMonthlyBudgetId, monthly);
                          if (linked == null) return null;
                          // If you already have _approxTo(from:, to:, amount:), use it. Otherwise see note below.
                          return _approxTo(from: t.currency, to: linked.currency, amount: t.amount);
                        }(),
                        builder: (_, linkedApprox) {
                          final spent = _spentByTrip[t.tripId ?? ''] ?? 0.0;
                          final remaining = (t.amount) - spent;

                          final lines = <Widget>[
                            // your existing totals
                            Text('Total: ${_money(t.currency, t.amount)}'),
                            Text('Spent: ${_money(t.currency, spent)}'),
                            Text('Remaining: ${_money(t.currency, remaining)}'),
                            const SizedBox(height: 4),

                            // Linked label (always show, even before future resolves)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.link, size: 14),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _linkedLabel(t.linkedMonthlyBudgetId, monthly),
                                    style: Theme.of(context).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ];

                          // ≈ linked monthly currency line (only when linked and computed)
                          if (linkedApprox.hasData) {
                            final linked = _monthlyById(t.linkedMonthlyBudgetId, monthly)!;
                            lines.add(
                              Text(
                                '≈ ${linkedApprox.data!.toStringAsFixed(2)} ${linked.currency} (linked)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: lines,
                          );
                        },
                      ),
// Trip budget subtitle patch end


                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'link') _linkTripToMonthly(t, monthly);
                          if (v == 'unlink') _unlinkTrip(t);
                          if (v == 'edit') _editTrip(t);
                          if (v == 'delete') _deleteBudget(t);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          const PopupMenuDivider(),
                          if (t.linkedMonthlyBudgetId == null)
                            const PopupMenuItem(value: 'link', child: Text('Link to monthly'))
                          else ...[
                            const PopupMenuItem(value: 'link', child: Text('Change link')),
                            const PopupMenuItem(value: 'unlink', child: Text('Unlink')),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fab-new-monthly', // <-- add
            onPressed: _createMonthlyDialog,
            label: const Text('New Monthly'),
            icon: const Icon(Icons.calendar_today),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'fab-new-trip', // <-- add
            onPressed: _createTripDialog,
            label: const Text('New Trip'),
            icon: const Icon(Icons.flight),
          ),
        ],
      ),
    );
  }
}
