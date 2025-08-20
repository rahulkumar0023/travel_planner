import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/monthly.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  final ApiService api;
  const MonthlyBudgetScreen({super.key, required this.api});

  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<dynamic>> _future; // [summary, envelopes]

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final summary = await widget.api.fetchMonthlySummary(_month);
    final envs = await widget.api.fetchMonthlyEnvelopes(_month);
    return [summary, envs];
  }

  Future<void> _pickMonth() async {
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
        _future = _load();
      });
    }
  }

  String _mmm(int m) => const [
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
      ][m - 1];

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
        onRefresh: () async {
          setState(() => _future = _load());
          await _future;
        },
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 100),
                Center(
                    child: Text('Could not load monthly view:\n${snap.error}')),
              ]);
            }

            final summary =
                (snap.data as List)[0] as MonthlyBudgetSummary;
            final budgets =
                (snap.data as List)[1] as List<MonthlyEnvelope>;
            final leftOver = summary.remaining;
            final pct = summary.pctSpent;

            return ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                // Overview Card
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge),
                                const SizedBox(height: 4),
                                Text(
                                  leftOver.toStringAsFixed(2),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall!
                                      .copyWith(
                                          fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                    '${(pct * 100).toStringAsFixed(2)}% of income spent',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium!
                                        .copyWith(
                                            color: cs.secondary)),
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
                        totalBudgeted: summary.totalBudgeted,
                        totalSpent: summary.totalSpent,
                        leftOver: leftOver,
                      ),
                    ],
                  ),
                ),

                // Envelope rows
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text('Categories',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium!
                          .copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 4),
                ...budgets.map((b) => _BudgetRow(budget: b)).toList(),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OverviewStats extends StatelessWidget {
  final double totalBudgeted;
  final double totalSpent;
  final double leftOver;
  const _OverviewStats(
      {required this.totalBudgeted,
      required this.totalSpent,
      required this.leftOver});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget stat(String label, double amount, Color color) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium!
                    .copyWith(color: cs.secondary)),
            const SizedBox(height: 4),
            Text(amount.toStringAsFixed(2),
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return Row(
      children: [
        stat('Planned', totalBudgeted, cs.primary),
        stat('Spent', totalSpent, cs.tertiary),
        stat('Left', leftOver, cs.primary),
      ],
    );
  }
}

class _Ring extends StatelessWidget {
  final double value;
  const _Ring({required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 6,
            backgroundColor: cs.surfaceVariant,
            color: cs.primary,
          ),
          Center(
              child: Text('${(value * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.labelMedium)),
        ],
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  final MonthlyEnvelope budget;
  const _BudgetRow({required this.budget});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining =
        (budget.planned - budget.spent).clamp(0.0, double.infinity);
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
              Expanded(
                child: Text(budget.name,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(width: 8),
              Text(budget.planned.toStringAsFixed(2),
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge!
                      .copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: budget.pct,
              minHeight: 8,
              backgroundColor: cs.surfaceVariant,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spent: ${budget.spent.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelMedium),
              Text('Left: ${remaining.toStringAsFixed(2)}',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium!
                      .copyWith(color: cs.secondary)),
            ],
          ),
        ],
      ),
    );
  }
}
