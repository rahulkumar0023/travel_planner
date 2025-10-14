import 'package:flutter/material.dart';

import '../models/monthly.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import 'monthly/monthly_budget_detail_screen.dart';
import 'monthly/new_monthly_budget_screen.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  const MonthlyBudgetScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late DateTime _month;
  Future<MonthlyBudgetSummary> _summaryFut =
      Future.value(MonthlyBudgetSummary(currency: '', totalBudgeted: 0, totalSpent: 0));
  Future<List<EnvelopeVM>> _budgetsFut = Future.value(<EnvelopeVM>[]);
  MonthlyBudgetSummary? _cachedSummary;
  List<EnvelopeVM> _cachedBudgets = const [];

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
    () async {
      try {
        await widget.api.waitForToken();
        if (mounted) _load();
      } catch (_) {}
    }();
  }

  void _load() {
    setState(() {
      _summaryFut = widget.api.fetchMonthlySummary(_month);
      _budgetsFut = widget.api.fetchMonthlyEnvelopes(_month);
    });
    _summaryFut.then((value) {
      if (!mounted) return;
      setState(() => _cachedSummary = value);
    });
    _budgetsFut.then((value) {
      if (!mounted) return;
      setState(() => _cachedBudgets = value);
    });
  }

  String get _monthLabel =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

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

  Future<void> _openCreateBudget() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewMonthlyBudgetScreen(
          api: widget.api,
          initialMonth: _month,
        ),
      ),
    );
    if (created == true) {
      _load();
    }
  }

  void _openDetail(EnvelopeVM env, MonthlyBudgetSummary summary) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MonthlyBudgetDetailScreen(
          month: _month,
          envelope: env,
          summary: summary,
          api: widget.api,
        ),
      ),
    );
  }

  Drawer _buildDrawer() {
    final summary = _cachedSummary;
    final budgets = _cachedBudgets;
    final currency = summary?.currency.isNotEmpty == true
        ? summary!.currency
        : TripStorageService.getHomeCurrency();

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly planner',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('Month $_monthLabel',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openCreateBudget();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create monthly budget'),
                  ),
                ],
              ),
            ),
            const ListTile(
              leading: Icon(Icons.history),
              title: Text('Recents'),
            ),
            if (budgets.isEmpty)
              const ListTile(
                title: Text('No budgets yet'),
                dense: true,
              )
            else
              ...budgets.take(5).map(
                (b) => ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(b.name),
                  subtitle: Text('${b.planned.toStringAsFixed(2)} ${b.currency}'),
                  onTap: () {
                    Navigator.pop(context);
                    _openDetail(b, summary ??
                        MonthlyBudgetSummary(
                          currency: currency,
                          totalBudgeted: 0,
                          totalSpent: 0,
                        ));
                  },
                ),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Recurring transactions'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Analytics & reports'),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: Text('Monthly Budgets ($_monthLabel)'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Pick month',
            onPressed: _pickMonth,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateBudget,
        icon: const Icon(Icons.account_balance_wallet_outlined),
        label: const Text('New Monthly Budget'),
      ),
      body: FutureBuilder(
        future: Future.wait([_summaryFut, _budgetsFut]),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load: ${snapshot.error}'));
          }

          final data = snapshot.data as List;
          final summary = data[0] as MonthlyBudgetSummary;
          final budgets = data[1] as List<EnvelopeVM>;

          if (budgets.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.account_balance_wallet_outlined, size: 48),
                  SizedBox(height: 12),
                  Text('No monthly budgets yet.'),
                  SizedBox(height: 4),
                  Text('Tap “New Monthly Budget” to create one.'),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _SummaryCard(summary: summary),
              const SizedBox(height: 12),
              for (final env in budgets)
                _BudgetRow(
                  env: env,
                  onTap: () => _openDetail(env, summary),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final MonthlyBudgetSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currency = summary.currency.isEmpty
        ? TripStorageService.getHomeCurrency()
        : summary.currency;
    final pct = summary.pctSpent;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Left over  ${summary.remaining.toStringAsFixed(2)} $currency',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: pct, minHeight: 8),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Budgeted'),
              Text('${summary.totalBudgeted.toStringAsFixed(2)} $currency'),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Spent'),
              Text('${summary.totalSpent.toStringAsFixed(2)} $currency'),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Income'),
              Text('${summary.totalIncome.toStringAsFixed(2)} $currency'),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Expenses'),
              Text('${summary.totalMonthExpenses.toStringAsFixed(2)} $currency'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.env, required this.onTap});

  final EnvelopeVM env;
  final VoidCallback onTap;

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Theme.of(context).cardColor,
        elevation: 1,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                          Text(env.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('Spent ${env.spent.toStringAsFixed(2)} ${env.currency}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: env.pct,
                    minHeight: 10,
                    color: color,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Budget ${env.planned.toStringAsFixed(2)} ${env.currency}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Remaining ${(env.planned - env.spent).clamp(0, double.infinity).toStringAsFixed(2)} ${env.currency}',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: color,
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
