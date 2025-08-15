import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../services/api_service.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  final ApiService api;
  const MonthlyBudgetScreen({super.key, required this.api});

  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<MonthlyBudgetSummary> _summaryFut;
  late Future<List<Budget>> _budgetsFut;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _summaryFut = widget.api.fetchMonthlySummary(_month);
    _budgetsFut = widget.api.fetchMonthlyBudgets(_month);
  }

  Future<void> _pickMonth() async {
    // Simple month switcher (minus/plus). You can swap for a month picker later.
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
                    title: Text('${_monthName(m.month)} ${m.year}'),
                    onTap: () => Navigator.pop(ctx, m),
                  ))
              .toList(),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _month = picked;
        _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: () {}),
        title: InkWell(
          onTap: _pickMonth,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${_monthName(_month.month)} ${_month.year}'),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.person_add_alt), onPressed: () {}),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          /* open add budget or add transaction */
        },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_load);
          await Future.wait([_summaryFut, _budgetsFut]).catchError((_) {});
        },
        child: FutureBuilder(
          future: Future.wait([_summaryFut, _budgetsFut]),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: const [
                  SizedBox(height: 100),
                  Center(child: Text('Could not load budgets')),
                ],
              );
            }
            final summary = (snap.data as List)[0] as MonthlyBudgetSummary;
            final budgets = (snap.data as List)[1] as List<Budget>;

            return ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                _Header(summary: summary),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _LegendRow(summary: summary),
                ),
                const SizedBox(height: 12),
                const _SectionTitle('Budgets'),
                const SizedBox(height: 8),
                ...budgets.map((b) => _BudgetRow(budget: b)).toList(),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  String _monthName(int m) {
    const names = [
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
    return names[(m - 1) % 12];
  }
}

class _Header extends StatelessWidget {
  final MonthlyBudgetSummary summary;
  const _Header({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = summary.pctSpent;
    return Container(
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
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyMedium!,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Left Over',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(
                        '${summary.remaining.toStringAsFixed(2)} ${summary.currency}',
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
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _StatRow(
            leftLabel: 'Total Budgeted',
            leftValue:
                '${summary.totalBudgeted.toStringAsFixed(2)} ${summary.currency}',
            midLabel: 'Provisional Balance',
            midValue: '0.00 ${summary.currency}',
            rightLabel: 'Remaining to Spend',
            rightValue:
                '${summary.remaining.toStringAsFixed(2)} ${summary.currency}',
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final MonthlyBudgetSummary summary;
  const _LegendRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        _LegendChip(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Budget Spent',
            color: cs.primary),
        const Spacer(),
        Text('${(summary.pctSpent * 100).toStringAsFixed(2)}%',
            style: Theme.of(context).textTheme.labelLarge),
      ],
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
          CircularProgressIndicator(
            value: 1,
            strokeWidth: 10,
            color: cs.surfaceVariant,
          ),
          CircularProgressIndicator(
            value: value,
            strokeWidth: 10,
            color: cs.primary,
          ),
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

class _StatRow extends StatelessWidget {
  final String leftLabel, leftValue, midLabel, midValue, rightLabel, rightValue;
  const _StatRow({
    required this.leftLabel,
    required this.leftValue,
    required this.midLabel,
    required this.midValue,
    required this.rightLabel,
    required this.rightValue,
  });

  Widget _cell(BuildContext c, String label, String value) {
    final t = Theme.of(c).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: t.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _cell(context, leftLabel, leftValue),
      _cell(context, midLabel, midValue),
      _cell(context, rightLabel, rightValue),
    ]);
  }
}

class _BudgetRow extends StatelessWidget {
  final Budget budget;
  const _BudgetRow({required this.budget});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = [
      cs.primary,
      cs.tertiary,
      cs.secondary,
      cs.error,
      cs.primaryContainer,
      cs.secondaryContainer,
    ];
    final color = colors[budget.colorIndex % colors.length];
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
              _Circle(
                  color: color,
                  label: budget.name.isNotEmpty
                      ? budget.name[0].toUpperCase()
                      : '?'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(budget.name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      'Spending  ${budget.spent.toStringAsFixed(2)} ${budget.currency}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  /* Quick add to this budget */
                },
                tooltip: 'Add',
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: budget.pct,
              minHeight: 10,
              color: color,
              backgroundColor: cs.surfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                  child: Text(
                'Actual Budgeted  ${budget.planned.toStringAsFixed(2)} ${budget.currency}',
                style: Theme.of(context).textTheme.labelSmall,
              )),
              Expanded(
                  child: Text(
                'Remaining to spend  ${(budget.planned - budget.spent).clamp(0, double.infinity).toStringAsFixed(2)} ${budget.currency}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall,
              )),
            ],
          ),
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
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withOpacity(.15),
      child: Text(label,
          style:
              TextStyle(color: color, fontWeight: FontWeight.w900)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleMedium!
              .copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _LegendChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: t.labelSmall!.copyWith(fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

