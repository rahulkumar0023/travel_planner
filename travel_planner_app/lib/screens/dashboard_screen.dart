import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:travel_planner_app/services/api_service.dart';
import '../models/expense.dart';
import '../models/trip.dart';
import 'expense_form_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.activeTrip});
  final Trip activeTrip;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Trip trip;

  late Box<Expense> _expensesBox;
  List<Expense> _expenses = []; // start empty to avoid first-build nulls
  bool _loading = true;
  double? eurTotal;

  @override
  void initState() {
    super.initState();
    trip = widget.activeTrip;
    _expensesBox = Hive.box<Expense>('expensesBox');
    // load cached first for instant UI, then try API
    _expenses = _expensesBox.values.toList();
    _loading = false;
    _convert();
    _loadFromApi(); // fire-and-forget refresh
  }

  Future<void> _loadFromApi() async {
    try {
      final remote = await ApiService.fetchExpenses(trip.id); // use real tripId
      if (!mounted) return;
      setState(() {
        _expenses = remote;
      });
      _convert();
      // cache latest
      await _replaceBox(remote);
    } catch (e) {
      // keep cached values; optionally show a snackbar
      debugPrint('API error: $e');
    }
  }

  Future<void> _replaceBox(List<Expense> items) async {
    await _expensesBox.clear();
    for (final e in items) {
      await _expensesBox.add(e);
    }
  }

  void _convert() async {
    final total = _expenses.fold<double>(0, (s, e) => s + e.amount);
    try {
      final converted = await ApiService.convert(
        amount: total,
        from: trip.currency,
        to: 'EUR',
      );
      if (!mounted) return;
      setState(() => eurTotal = converted);
    } catch (_) {}
  }

  void _addExpense(
    String title,
    double amount,
    String category,
    String paidBy,
    List<String> sharedWith,
  ) {
    final expense = Expense(
      id: DateTime.now().toIso8601String(),
      tripId: trip.id,
      title: title,
      amount: amount,
      category: category,
      date: DateTime.now(),
      paidBy: paidBy,
      sharedWith: sharedWith,
    );

    if (!mounted) return;
    setState(() => _expenses = [..._expenses, expense]);
    _expensesBox.add(expense);
    _convert();
    // TODO: optionally sync to backend:
    // ApiService.addExpense(expense).catchError((_) { /* mark unsynced */ });
  }

  @override
  Widget build(BuildContext context) {
    final totalSpent = _expenses.fold<double>(0, (s, e) => s + (e.amount));
    final remaining = (trip.initialBudget - totalSpent)
        .clamp(0, trip.initialBudget)
        .toDouble();

    final pct = trip.initialBudget == 0
        ? 0.0
        : (totalSpent / trip.initialBudget).clamp(0, 1).toDouble();

    final categories = _categorySummaries(_expenses);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          HapticFeedback.lightImpact();
          final added = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (ctx) => Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: ExpenseFormSheet(onAddExpense: _addExpense),
            ),
          );
          if (added == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Expense added')),
            );
          }
        },
        label: const Text('Add expense'),
        icon: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: RefreshIndicator(
        onRefresh: _loadFromApi,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _HeaderCard(
                currency: trip.currency,
                budget: trip.initialBudget,
                spent: totalSpent,
                remaining: remaining,
                pct: pct,
                altSpent: eurTotal,
                altCurrency: 'EUR',
              ),
            ),
            // horizontal categories strip
            if (categories.isNotEmpty)
              SliverToBoxAdapter(
                child: _CategoryStrip(
                  summaries: categories,
                  currency: trip.currency,
                ),
              ),
            // expenses list
            if (_loading && _expenses.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_expenses.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList.separated(
                  itemCount: _expenses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final e = _expenses[i];
                    return _ExpenseTile(
                      title: e.title,
                      subtitle: '${e.category} • ${_fmtDate(e.date)}',
                      amount: e.amount,
                      currency: trip.currency,
                      icon: _iconForCategory(e.category),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- helpers ----------

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  IconData _iconForCategory(String c) {
    switch (c.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'transport':
        return Icons.directions_bus;
      case 'lodging':
        return Icons.hotel;
      case 'activity':
        return Icons.local_activity;
      default:
        return Icons.category;
    }
  }

  List<_CategorySummary> _categorySummaries(List<Expense> items) {
    final map = <String, double>{};
    for (final e in items) {
      map.update(e.category, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    // give each category a "virtual" budget portion: equal split across seen categories
    final parts = map.length == 0 ? 1 : map.length;
    final perCatBudget = trip.initialBudget / parts;
    return map.entries
        .map(
          (e) => _CategorySummary(
            label: e.key,
            spent: e.value,
            budget: perCatBudget,
            icon: _iconForCategory(e.key),
          ),
        )
        .toList()
      ..sort((a, b) => b.spent.compareTo(a.spent));
  }
}

// ======= UI bits =======

class _HeaderCard extends StatelessWidget {
  final String currency;
  final double budget, spent, remaining, pct;
  final double? altSpent;
  final String? altCurrency;
  const _HeaderCard({
    required this.currency,
    required this.budget,
    required this.spent,
    required this.remaining,
    required this.pct,
    this.altSpent,
    this.altCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary.withOpacity(.95), cs.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          _AnimatedDonut(
            progress: pct,
            size: 110,
            bg: cs.onPrimary.withOpacity(.2),
            fg: cs.onPrimary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DefaultTextStyle(
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: cs.onPrimary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trip budget',
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                      color: cs.onPrimary.withOpacity(.9),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$budget $currency',
                    style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(
                        'Spent',
                        '$spent $currency',
                        cs.onPrimary,
                        cs.onPrimary.withOpacity(.08),
                      ),
                      _pill(
                        'Left',
                        '$remaining $currency',
                        cs.primary,
                        cs.onPrimary,
                      ),
                    ],
                  ),
                  if (altSpent != null && altCurrency != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '≈ ${altSpent!.toStringAsFixed(2)} $altCurrency',
                        style: TextStyle(
                          color: cs.onPrimary.withOpacity(.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, String value, Color text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: text.withOpacity(.9),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w800, color: text),
          ),
        ],
      ),
    );
  }
}

class _AnimatedDonut extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final Color bg, fg;
  const _AnimatedDonut({
    required this.progress,
    required this.size,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(value: 1.0, strokeWidth: 10, color: bg),
            CircularProgressIndicator(value: value, strokeWidth: 10, color: fg),
            Text(
              '${(value * 100).round()}%',
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySummary {
  final String label;
  final double spent;
  final double budget;
  final IconData icon;
  _CategorySummary({
    required this.label,
    required this.spent,
    required this.budget,
    required this.icon,
  });
}

class _CategoryStrip extends StatelessWidget {
  final List<_CategorySummary> summaries;
  final String currency;
  const _CategoryStrip({required this.summaries, required this.currency});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: summaries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = summaries[i];
          final pct = c.budget == 0
              ? 1.0
              : (c.spent / c.budget).clamp(0, 1).toDouble();
          final cs = Theme.of(context).colorScheme;
          return Container(
            width: 220,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(c.icon, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${c.spent.toStringAsFixed(0)} $currency',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: pct, minHeight: 10),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(pct * 100).round()}% of ${c.budget.toStringAsFixed(0)} $currency',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final String title, subtitle, currency;
  final double amount;
  final IconData icon;
  const _ExpenseTile({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '+ ${amount.toStringAsFixed(2)} $currency',
            style: TextStyle(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flight_takeoff, size: 56, color: cs.primary),
          const SizedBox(height: 12),
          const Text(
            'No expenses yet',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text('Tap “Add expense” to get started.'),
        ],
      ),
    );
  }
}
