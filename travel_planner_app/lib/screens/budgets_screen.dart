import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import '../models/budget.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> with TickerProviderStateMixin {
  late Future<List<Budget>> _future;
  String _home = TripStorageService.getHomeCurrency();

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchBudgetsOrCache();
  }

  Future<void> _refresh() async {
    setState(() {                       // ✅ no return value -> synchronous
      _future = widget.api.fetchBudgetsOrCache();
    });
    await _future;
  }

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

  // ➊ Find a monthly by id
  Budget? _monthlyById(String? id, List<Budget> monthly) {
    if (id == null) return null;
    for (final m in monthly) {
      if (m.id == id) return m;
    }
    return null;
  }

// ➋ Build a friendly label for a linked monthly
  String _linkedLabel(String? monthlyId, List<Budget> monthly) {
    final m = _monthlyById(monthlyId, monthly);
    if (m == null) return 'Not linked';
    final yyMm = '${m.year}-${(m.month ?? 0).toString().padLeft(2, '0')}';
    return 'Linked → ${ (m.name?.isNotEmpty == true) ? m.name! : yyMm }';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- money formatting + spent cache ---
// money formatter (very simple; replace with intl if you want)
  String _money(String ccy, num v) => '$ccy ${v.toStringAsFixed(0)}';

// Cache: tripId -> spent amount
  final Map<String, double> _spentByTrip = <String, double>{};
  final Set<String> _spentLoadedFor = <String>{};
  bool _loadingSpends = false;

// Schedule a recalc after the current frame (so we don't setState during build)
  void _scheduleSpendRecalc(List<Budget> all) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recalcSpends(all);
    });
  }

// Recalculate spends for any trip budgets whose tripId we haven't loaded yet
  Future<void> _recalcSpends(List<Budget> all) async {
    // collect new tripIds to load
    final ids = <String>[];
    for (final b in all) {
      if (b.kind == BudgetKind.trip && b.tripId != null && !_spentLoadedFor.contains(b.tripId)) {
        ids.add(b.tripId!);
      }
    }
    if (ids.isEmpty) return;

    setState(() => _loadingSpends = true);

    // fetch each trip's expenses and sum
    try {
      await Future.wait(ids.map((id) async {
        final expenses = await widget.api.fetchExpenses(id);
        final sum = expenses.fold<double>(0.0, (p, e) => p + (e.amount));
        _spentByTrip[id] = sum;
        _spentLoadedFor.add(id);
      }));
    } catch (_) {
      // ignore; UI will just show 0 spent if something fails
    }

    if (!mounted) return;
    setState(() => _loadingSpends = false);
  }


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
          final monthly = all.where((b) => b.kind == BudgetKind.monthly).toList();
          final trips   = all.where((b) => b.kind == BudgetKind.trip).toList();
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
                      subtitle: Builder(builder: (ctx) {
                        final spent = _spentByTrip[t.tripId ?? ''] ?? 0.0;
                        final remaining = (t.amount) - spent;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total: ${_money(t.currency, t.amount)}'),
                            Text('Spent: ${_money(t.currency, spent)}'),
                            Text('Remaining: ${_money(t.currency, remaining)}'),
                          ],
                        );
                      }),

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
            onPressed: _createMonthlyDialog,
            label: const Text('New Monthly'),
            icon: const Icon(Icons.calendar_today),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            onPressed: _createTripDialog,
            label: const Text('New Trip'),
            icon: const Icon(Icons.flight),
          ),
        ],
      ),
    );
  }
}
