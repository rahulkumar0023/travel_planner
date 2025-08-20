import 'package:flutter/material.dart';
import '../services/api_service.dart';
// 👇 NEW: Monthly view-models for this screen
import '../models/monthly.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  final ApiService api;
  const MonthlyBudgetScreen({super.key, required this.api});

  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen> {
  late DateTime _month;
  // 👇 NEW: change budgets list to EnvelopeVM
  late Future<MonthlyBudgetSummary> _summaryFut;
  late Future<List<EnvelopeVM>> _budgetsFut;

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
    _load();
  }

  // 👇 NEW: wire to the new ApiService methods
  void _load() {
    _summaryFut = widget.api.fetchMonthlySummary(_month);
    _budgetsFut = widget.api.fetchMonthlyEnvelopes(_month);
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(_month.year - 1),
      lastDate: DateTime(_month.year + 1, 12, 31),
      selectableDayPredicate: (d) => d.day == 1,
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Budget'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Pick month',
            onPressed: _pickMonth,
          ),
        ],
      ),
      body: FutureBuilder(
        future: Future.wait([_summaryFut, _budgetsFut]),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load: ${snap.error}'));
          }
          // 👇 NEW: correct types
          final summary = (snap.data as List)[0] as MonthlyBudgetSummary;
          final envelopes = (snap.data as List)[1] as List<EnvelopeVM>;

          return ListView(
            children: [
              _SummaryCard(summary: summary),
              const SizedBox(height: 8),
              // 👇 NEW: show envelopes
              ...envelopes.map((e) => _BudgetRow(env: e)).toList(),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final MonthlyBudgetSummary summary;
  const _SummaryCard({required this.summary});
  @override
  Widget build(BuildContext context) {
    final pct = summary.pctSpent;
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Left Over  ${summary.remaining.toStringAsFixed(2)} ${summary.currency}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: pct, minHeight: 8),
          const SizedBox(height: 8),
          Text('Spent ${summary.totalSpent.toStringAsFixed(2)} / ${summary.totalBudgeted.toStringAsFixed(2)} ${summary.currency}'),
        ],
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  final EnvelopeVM env;
  const _BudgetRow({required this.env});
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
    final color = colors[env.colorIndex % colors.length];
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
              _Circle(color: color, label: env.name.isNotEmpty ? env.name[0].toUpperCase() : '?'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(env.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Spending  ${env.spent.toStringAsFixed(2)} ${env.currency}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {/* TODO: Quick add to this envelope */},
                tooltip: 'Add',
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: env.pct,
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
                  'Actual Budgeted  ${env.planned.toStringAsFixed(2)} ${env.currency}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Expanded(
                child: Text(
                  'Remaining to spend  ${(env.planned - env.spent).clamp(0, double.infinity).toStringAsFixed(2)} ${env.currency}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
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
    return CircleAvatar(
      radius: 16,
      backgroundColor: color,
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
