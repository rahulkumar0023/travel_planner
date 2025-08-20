import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/budget.dart';
import '../models/expense.dart';

class MonthlyOverviewScreen extends StatefulWidget {
  const MonthlyOverviewScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<MonthlyOverviewScreen> createState() => _MonthlyOverviewScreenState();
}

class _MonthlyOverviewScreenState extends State<MonthlyOverviewScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<_MonthlyData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MonthlyData> _load() async {
    // 1) Fetch all budgets (monthly + trip)
    final budgets = await widget.api.fetchBudgetsOrCache();
    final monthly = budgets.where((b) => b.kind == BudgetKind.monthly).toList();
    final trips = budgets.where((b) => b.kind == BudgetKind.trip).toList();

    // 2) For each monthly budget, find linked trip budgets
    final byMonthly = <String, List<Budget>>{};
    for (final t in trips) {
      final mId = t.linkedMonthlyBudgetId;
      if (mId == null) continue;
      (byMonthly[mId] ??= <Budget>[]).add(t);
    }

    // 3) For each linked trip, pull expenses for the month and convert to monthly ccy
    final categories = <_CategoryRow>[];
    for (final m in monthly) {
      final linkedTrips = byMonthly[m.id] ?? const <Budget>[];
      double spentInMonthly = 0.0;

      for (final tb in linkedTrips) {
        final expenses = await widget.api.fetchExpenses(tb.tripId!);
        for (final e in expenses) {
          // Only include expenses inside selected month
          if (!_sameMonth(e.date, _month)) continue;
          final from = (e.currency.isEmpty) ? tb.currency : e.currency;
          // Convert each expense to the monthly budget currency
          final v = (from.toUpperCase() == m.currency.toUpperCase())
              ? e.amount
              : await widget.api
                  .convert(amount: e.amount, from: from, to: m.currency);
          spentInMonthly += v;
        }
      }

      categories.add(
        _CategoryRow(
          monthly: m,
          linkedTrips: linkedTrips,
          spent: spentInMonthly,
        ),
      );
    }

    // 4) Overview roll-ups
    final totalBudgeted = categories.fold<double>(0, (p, c) {
      // convert each category budget to the first monthly’s currency for a single % bar
      // Simpler: keep “% spent” per currency by weighting with each budget’s own currency.
      // For overview % we’ll compute “spent / budgeted” **within each category** and
      // average by budget size converted to EUR-ish via the convert endpoint.
      return p + c.monthly.amount;
    });
    final totalSpent = categories.fold<double>(0, (p, c) => p + c.spent);

    return _MonthlyData(
      month: _month,
      categories: categories,
      totalBudgeted: totalBudgeted,
      totalSpent: totalSpent,
    );
  }

  Future<void> _reload() async {
    final fut = _load();
    if (!mounted) return;
    setState(() => _future = fut);
    await fut;
  }

  bool _sameMonth(DateTime d, DateTime m) =>
      d.year == m.year && d.month == m.month;

  String _mmm(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  Future<void> _pickMonth() async {
    // quick month scroller (±6 months)
    final base = DateTime(_month.year, _month.month);
    final options = List.generate(13, (i) {
      final d = DateTime(base.year, base.month - 6 + i);
      return DateTime(d.year, d.month);
    });
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        children: [
          for (final d in options)
            ListTile(
              title: Text('${_mmm(d.month)} ${d.year}'),
              onTap: () => Navigator.pop(ctx, d),
            )
        ],
      ),
    );
    if (picked != null) {
      setState(() {
        _month = picked;
      });
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _pickMonth,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${_mmm(_month.month)} ${_month.year}'),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 18),
          ]),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<_MonthlyData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 100),
                Center(child: Text('Could not load monthly view:\n${snap.error}')),
              ]);
            }
            final data = snap.data!;
            final leftOver =
                (data.totalBudgeted - data.totalSpent).clamp(0.0, double.infinity);
            final pct = data.totalBudgeted == 0
                ? 0.0
                : (data.totalSpent / data.totalBudgeted).clamp(0.0, 1.0);

            return ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                // ======= Overview Card =======
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _Ring(value: pct),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Left Over',
                                    style:
                                        Theme.of(context).textTheme.labelLarge),
                                const SizedBox(height: 4),
                                // Note: currency varies by category; show number only here.
                                Text(
                                  leftOver.toStringAsFixed(2),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall!
                                      .copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                    '${(pct * 100).toStringAsFixed(2)}% of income spent',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium!
                                        .copyWith(color: cs.secondary)),
                              ],
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
                      const SizedBox(height: 12),
                      _OverviewStats(
                        totalBudgeted: data.totalBudgeted,
                        totalSpent: data.totalSpent,
                        leftOver: leftOver,
                      ),
                    ],
                  ),
                ),

                // ======= Category Rows (Envelopes) =======
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text('Categories',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium!
                          .copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 4),
                ...data.categories.map((c) => _CategoryTile(row: c)).toList(),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------- helpers & tiny view classes ----------

class _MonthlyData {
  final DateTime month;
  final List<_CategoryRow> categories;
  final double totalBudgeted;
  final double totalSpent;
  _MonthlyData({
    required this.month,
    required this.categories,
    required this.totalBudgeted,
    required this.totalSpent,
  });
}

class _CategoryRow {
  final Budget monthly; // the monthly “envelope”
  final List<Budget> linkedTrips; // trip budgets linked to this envelope
  final double spent; // in monthly.currency
  _CategoryRow(
      {required this.monthly, required this.linkedTrips, required this.spent});

  double get remaining =>
      (monthly.amount - spent).clamp(0.0, double.infinity);
  double get pct =>
      monthly.amount == 0 ? 0 : (spent / monthly.amount).clamp(0.0, 1.0);
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.row});
  final _CategoryRow row;

  String _labelForMonthly(Budget m) {
    if (m.name != null && m.name!.isNotEmpty) return m.name!;
    if (m.month != null && m.year != null) {
      const names = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      final when = (m.month! >= 1 && m.month! <= 12)
          ? '${names[m.month!]} ${m.year}'
          : '';
      return when.isEmpty ? 'Monthly' : when;
    }
    return 'Monthly';
  }

  @override
  Widget build(BuildContext context) {
    final m = row.monthly;
    final cs = Theme.of(context).colorScheme;
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
          // Title + budget amount
          Row(
            children: [
              Expanded(
                child: Text(
                  _labelForMonthly(m),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text('${m.amount.toStringAsFixed(2)} ${m.currency}',
                  style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: row.pct,
              minHeight: 10,
              color: cs.primary,
              backgroundColor: cs.surfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Spending  ${row.spent.toStringAsFixed(2)} ${m.currency}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Expanded(
                child: Text(
                  'Remaining  ${row.remaining.toStringAsFixed(2)} ${m.currency}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          if (row.linkedTrips.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Linked trips: ${row.linkedTrips.map((t) => t.name ?? 'Trip').join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _OverviewStats extends StatelessWidget {
  final double totalBudgeted, totalSpent, leftOver;
  const _OverviewStats({
    required this.totalBudgeted,
    required this.totalSpent,
    required this.leftOver,
  });
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget cell(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.labelSmall),
              const SizedBox(height: 2),
              Text(value,
                  style: t.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Row(children: [
      cell('Total Budgeted', totalBudgeted.toStringAsFixed(2)),
      cell('Budget Spent', totalSpent.toStringAsFixed(2)),
      cell('Remaining to Spend', leftOver.toStringAsFixed(2)),
    ]);
  }
}

class _Ring extends StatelessWidget {
  final double value; // 0..1
  const _Ring({required this.value});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
              value: 1, strokeWidth: 10, color: cs.surfaceVariant),
          CircularProgressIndicator(
              value: value, strokeWidth: 10, color: cs.primary),
          Text('${(value * 100).round()}%',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium!
                  .copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
