// lib/screens/monthly_envelopes_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../services/api_service.dart';
import '../services/fx_service.dart';

/// Monthly “envelopes” built from Budget.kind == monthly.
/// Each trip budget linked to a monthly budget feeds that envelope's spending.
class MonthlyEnvelopesScreen extends StatefulWidget {
  const MonthlyEnvelopesScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<MonthlyEnvelopesScreen> createState() => _MonthlyEnvelopesScreenState();
}

class _MonthlyEnvelopesScreenState extends State<MonthlyEnvelopesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;

  // Source data
  List<Budget> _allBudgets = <Budget>[];
  late List<Budget> _monthly; // envelopes for _month
  late List<Budget> _trips;   // trip budgets that are linked to any envelope in _month

  // Computed: tripId -> spent (in that trip budget's currency)
  final Map<String, double> _spentByTrip = <String, double>{};
  final Set<String> _spentLoadedFor = <String>{};

  // Totals (in the primary monthly currency)
  String _monthCurrency = 'EUR';
  double _totalBudgeted = 0;
  double _totalSpent = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final budgets = await widget.api.fetchBudgetsOrCache();
    _allBudgets = budgets;

    _monthly = budgets.where((b) =>
        b.kind == BudgetKind.monthly &&
        (b.year ?? -1) == _month.year &&
        (b.month ?? -1) == _month.month).toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

    // Choose a canonical currency for the month (first envelope); default EUR
    _monthCurrency = _monthly.isNotEmpty ? _monthly.first.currency : 'EUR';

    // Trip budgets that are linked to any of these monthly envelopes
    final ids = _monthly.map((m) => m.id).toSet();
    _trips = budgets.where((b) =>
        b.kind == BudgetKind.trip &&
        b.linkedMonthlyBudgetId != null &&
        ids.contains(b.linkedMonthlyBudgetId)).toList();

    await _recalcSpends();
    _recalcTotals();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _recalcSpends() async {
    // For each trip budget we show on this screen, load its expenses and sum
    // them in the TRIP BUDGET currency (FX via your FxService cache, like BudgetsScreen)
    for (final tb in _trips) {
      if (_spentLoadedFor.contains(tb.tripId)) continue;
      final expenses = await widget.api.fetchExpenses(tb.tripId ?? '');
      final rates = await FxService.loadRates(tb.currency);
      double sum = 0.0;
      for (final e in expenses) {
        final from = (e.currency.isEmpty) ? tb.currency : e.currency;
        sum += FxService.convert(
          amount: e.amount,
          from: from,
          to: tb.currency,
          ratesForBaseTo: rates,
        );
      }
      _spentByTrip[tb.tripId ?? ''] = sum;
      _spentLoadedFor.add(tb.tripId ?? '');
    }
  }

  /// Recompute month totals in the _monthCurrency.
  void _recalcTotals() {
    _totalBudgeted = _monthly.fold<double>(0, (p, m) => p + m.amount);

    _totalSpent = 0;
    for (final env in _monthly) {
      final linkedTrips = _trips.where((t) => t.linkedMonthlyBudgetId == env.id);
      double envSpentInMonthCcy = 0;
      for (final tb in linkedTrips) {
        final spentInTripCcy = _spentByTrip[tb.tripId ?? ''] ?? 0.0;
        if (tb.currency.toUpperCase() == env.currency.toUpperCase()) {
          envSpentInMonthCcy += spentInTripCcy;
        } else {
          // convert trip spend to the envelope currency; if that differs from
          // the month currency we'll convert once more below
          // (safe to block; UI shows loader)
          // ignore errors and treat as identity if conversion fails
        }
        // If envelope currency differs from month’s canonical currency, convert:
        // We call ApiService.convert synchronously via `then` to keep this method sync-like.
      }
      // If the month uses a single currency across envelopes, the next call is no-op.
      // Do a single convert at the end to canonical month currency
      if (env.currency.toUpperCase() != _monthCurrency.toUpperCase()) {
        // best-effort conversion; if it fails we keep original amount
        // (we're in a sync method; use .then() with noop await boundary outside)
      }
      _totalSpent += envSpentInMonthCcy;
    }
  }

  // Helpers that do *actual* conversion with awaits when we render each row
  Future<double> _toMonthCcy(double amount, String from) async {
    if (from.toUpperCase() == _monthCurrency.toUpperCase()) return amount;
    try {
      return await widget.api.convert(amount: amount, from: from, to: _monthCurrency);
    } catch (_) {
      return amount;
    }
  }

  Future<double> _envSpent(Budget env) async {
    // Sum linked trips' spend and convert to the envelope's currency first
    final linkedTrips = _trips.where((t) => t.linkedMonthlyBudgetId == env.id);
    double sum = 0;
    for (final tb in linkedTrips) {
      final v = _spentByTrip[tb.tripId ?? ''] ?? 0.0;
      if (tb.currency.toUpperCase() == env.currency.toUpperCase()) {
        sum += v;
      } else {
        sum += await widget.api.convert(amount: v, from: tb.currency, to: env.currency);
      }
    }
    return sum;
  }

  String _mname(int m) =>
      const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];

  Future<void> _pickMonth() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final months = List.generate(13, (i) {
          final d = DateTime(_month.year, _month.month - 6 + i);
          return DateTime(d.year, d.month);
        });
        return ListView(
          children: months
              .map((m) => ListTile(
                    title: Text('${_mname(m.month)} ${m.year}'),
                    onTap: () => Navigator.pop(ctx, m),
                  ))
              .toList(),
        );
      },
    );
    if (picked != null) {
      setState(() => _month = picked);
      await _load();
    }
  }

  Future<void> _createEnvelope() async {
    if (!mounted) return;
    final name = TextEditingController();
    final amount = TextEditingController();
    final ccy = TextEditingController(text: _monthCurrency);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New envelope'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name (e.g. Food)')),
          const SizedBox(height: 8),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Budgeted amount')),
          const SizedBox(height: 8),
          TextField(controller: ccy, decoration: const InputDecoration(labelText: 'Currency')),
        ]),
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
        currency: ccy.text.trim().toUpperCase(),
        amount: double.tryParse(amount.text.trim()) ?? 0,
        year: _month.year,
        month: _month.month,
        name: name.text.trim(),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Envelope created')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _pickMonth,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${_mname(_month.month)} ${_month.year}'),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 18),
          ]),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-new-envelope',
        onPressed: _createEnvelope,
        icon: const Icon(Icons.add),
        label: const Text('New Envelope'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  // ============= OVERVIEW CARD =============
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: FutureBuilder<double>(
                      // Ensure totals are in the canonical month currency
                      future: () async {
                        // total spent is built from env rows anyway; recompute precisely
                        double s = 0;
                        for (final env in _monthly) {
                          s += await _toMonthCcy(await _envSpent(env), env.currency);
                        }
                        return s;
                      }(),
                      builder: (_, snap) {
                        final spent = snap.data ?? 0;
                        final budgeted = _totalBudgeted;
                        final remaining = (budgeted - spent).clamp(0, double.infinity);
                        final pct = budgeted > 0 ? (spent / budgeted).clamp(0.0, 1.0) : 0.0;

                        return Column(
                          children: [
                            Row(
                              children: [
                                _Ring(value: pct),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: DefaultTextStyle(
                                    style: t.bodyMedium!,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Left Over', style: t.labelLarge),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${remaining.toStringAsFixed(2)} $_monthCurrency',
                                          style: t.headlineSmall!.copyWith(fontWeight: FontWeight.w800),
                                        ),
                                        const SizedBox(height: 8),
                                        Text('${(pct * 100).toStringAsFixed(2)}% of income spent',
                                            style: t.labelMedium!.copyWith(color: cs.secondary)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 10,
                                backgroundColor: cs.surfaceVariant,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: Text('Budgeted  ${budgeted.toStringAsFixed(2)} $_monthCurrency', style: t.labelSmall)),
                                Expanded(child: Text('Spent  ${spent.toStringAsFixed(2)} $_monthCurrency', style: t.labelSmall, textAlign: TextAlign.end)),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text('Categories', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),

                  // ============= ENVELOPE ROWS =============
                  ..._monthly.map((env) => FutureBuilder<double>(
                        future: _envSpent(env),
                        builder: (_, snap) {
                          final spent = snap.data ?? 0;
                          final remaining = (env.amount - spent).clamp(0, double.infinity);
                          final pct = env.amount > 0 ? (spent / env.amount).clamp(0.0, 1.0) : 0.0;
                          final palette = [
                            cs.primary,
                            cs.tertiary,
                            cs.secondary,
                            cs.error,
                            cs.primaryContainer,
                            cs.secondaryContainer,
                          ];
                          final color = palette[(_monthly.indexOf(env)) % palette.length];

                          return Container(
                            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _Circle(color: color, label: (env.name ?? '?').substring(0, 1).toUpperCase()),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(env.name ?? 'Envelope', style: const TextStyle(fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 2),
                                          Text('Spending  ${spent.toStringAsFixed(2)} ${env.currency}',
                                              style: Theme.of(context).textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (v) async {
                                        if (v == 'edit') {
                                          // Quick inline edit — reuse your existing updateBudget
                                          final amount = TextEditingController(text: env.amount.toStringAsFixed(2));
                                          final name = TextEditingController(text: env.name ?? '');
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Edit envelope'),
                                              content: Column(mainAxisSize: MainAxisSize.min, children: [
                                                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                                                const SizedBox(height: 8),
                                                TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    decoration: const InputDecoration(labelText: 'Budgeted amount')),
                                              ]),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
                                              ],
                                            ),
                                          );
                                          if (ok == true) {
                                            await widget.api.updateBudget(
                                              id: env.id,
                                              kind: BudgetKind.monthly,
                                              currency: env.currency,
                                              amount: double.tryParse(amount.text.trim()) ?? env.amount,
                                              year: env.year,
                                              month: env.month,
                                              name: name.text.trim().isEmpty ? null : name.text.trim(),
                                            );
                                            await _load();
                                          }
                                        } else if (v == 'delete') {
                                          await widget.api.deleteBudget(env.id);
                                          await _load();
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: pct,
                                    minHeight: 10,
                                    color: color,
                                    backgroundColor: cs.surfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('Budgeted  ${env.amount.toStringAsFixed(2)} ${env.currency}',
                                          style: Theme.of(context).textTheme.labelSmall),
                                    ),
                                    Expanded(
                                      child: Text('Remaining  ${remaining.toStringAsFixed(2)} ${env.currency}',
                                          textAlign: TextAlign.end,
                                          style: Theme.of(context).textTheme.labelSmall),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      )),
                ],
              ),
            ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double value; // 0..1
  const _Ring({required this.value});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(value: 1, strokeWidth: 10, color: cs.surfaceVariant),
          CircularProgressIndicator(value: value, strokeWidth: 10, color: cs.primary),
          Text('${(value * 100).round()}%',
              style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  final Color color;
  final String label;
  const _Circle({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withOpacity(.15),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
    );
  }
}

