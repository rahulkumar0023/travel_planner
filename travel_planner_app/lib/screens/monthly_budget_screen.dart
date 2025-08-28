import 'package:flutter/material.dart';
import '../services/api_service.dart';
// 👇 NEW: Monthly view-models for this screen
import '../models/monthly.dart';
import '../models/budget.dart'; // for BudgetKind
// 👇 NEW: categories & monthly txns
import '../models/monthly_category.dart';
import '../models/monthly_txn.dart';
import '../services/monthly_store.dart';
import 'monthly/category_editor_sheet.dart';
import 'monthly/txn_editor_sheet.dart';
import 'category_manager_screen.dart';
import 'sign_in_screen.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  final ApiService api;
  const MonthlyBudgetScreen({super.key, required this.api});

  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen> {
  late DateTime _month;
  // 👇 NEW: change budgets list to EnvelopeVM
  Future<MonthlyBudgetSummary> _summaryFut =
      Future.value(MonthlyBudgetSummary(currency: '', totalBudgeted: 0, totalSpent: 0));
  Future<List<EnvelopeVM>> _budgetsFut = Future.value(<EnvelopeVM>[]);

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
    () async {
      try {
        await widget.api.waitForToken();
        if (mounted) setState(_load);
      } catch (_) {}
    }();
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

  String _monthName(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  // 👇 NEW: monthKey helper — place near other helpers
  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  Future<void> _openAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: const Text('Add salary / income'),
              onTap: () => Navigator.pop(context, 'add_income'),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Add expense'),
              onTap: () => Navigator.pop(context, 'add_expense'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('New income category'),
              onTap: () => Navigator.pop(context, 'add_income_cat'),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('New expense category'),
              onTap: () => Navigator.pop(context, 'add_expense_cat'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Add monthly envelope'),
              subtitle: Text('${_monthName(_month.month)} ${_month.year}'),
              onTap: () => Navigator.pop(context, 'envelope'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'envelope') {
      await _createEnvelopeDialog();
      if (!mounted) return;
      setState(_load);
    } else if (choice == 'add_income') {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => TxnEditorSheet(monthKey: _monthKey, type: 'income'),
      );
      if (mounted) setState(() {});
    } else if (choice == 'add_expense') {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => TxnEditorSheet(monthKey: _monthKey, type: 'expense'),
      );
      if (mounted) setState(() {});
    } else if (choice == 'add_income_cat') {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) =>
            CategoryEditorSheet(monthKey: _monthKey, type: 'income'),
      );
      if (mounted) setState(() {});
    } else if (choice == 'add_expense_cat') {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) =>
            CategoryEditorSheet(monthKey: _monthKey, type: 'expense'),
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _createEnvelopeDialog() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final currency = TextEditingController(text: 'EUR');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Monthly Envelope'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Budgeted amount'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: currency,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Currency (e.g. EUR)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    if (ok != true) return;

    // Perform async work OUTSIDE setState
    try {
      await widget.api.createBudget(
        kind: BudgetKind.monthly,
        currency: currency.text.trim().toUpperCase(),
        amount: double.tryParse(amount.text.trim()) ?? 0,
        year: _month.year,
        month: _month.month,
        name: name.text.trim().isEmpty ? null : name.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Envelope created')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      // If unauthorized, route user to Sign In and retry is manual.
      if (msg.contains('Unauthorized') || msg.contains('401') || msg.contains('missing api_jwt')) {
        final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => SignInScreen(api: widget.api)),
        );
        if (ok == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Signed in. Please try again.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in required to create.')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Monthly Budget'),
          actions: [
            // 👇 NEW: Manage categories action start
            IconButton(
              tooltip: 'Manage categories',
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CategoryManagerScreen()),
                );
              },
            ),
            // 👆 Manage categories action end
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: 'Pick month',
              onPressed: _pickMonth,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
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

            // 👉 NEW: fetch categories & transactions for this month
            final incomeCats = MonthlyStore.instance.categoriesFor(_monthKey, type: 'income', parentId: null);
            final expenseCats = MonthlyStore.instance.categoriesFor(_monthKey, type: 'expense', parentId: null);
            final txns = MonthlyStore.instance.txnsFor(_monthKey);

          return ListView(
            children: [
              _SummaryCard(summary: summary),
              const SizedBox(height: 8),
              // 👇 NEW: show envelopes
              ...envelopes.map((e) => _BudgetRow(env: e)).toList(),
                // ===== MonthlyScreen: Categories & Txns — START =====
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text('Categories', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (incomeCats.isNotEmpty)
                        Text('Income', style: Theme.of(context).textTheme.labelLarge),
                      for (final c in incomeCats)
                        _CategoryTile(
                            category: c,
                            monthKey: _monthKey,
                            sectionType: 'income'),
                      const SizedBox(height: 8),
                      if (expenseCats.isNotEmpty)
                        Text('Expenses', style: Theme.of(context).textTheme.labelLarge),
                      for (final c in expenseCats)
                        _CategoryTile(
                            category: c,
                            monthKey: _monthKey,
                            sectionType: 'expense'),
                      const SizedBox(height: 16),
                      Text('Recent transactions', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      for (final t in txns.take(8))
                        ListTile(
                          dense: true,
                          title: Text('${t.type == "income" ? "+" : "-"} ${t.amount.toStringAsFixed(2)} ${t.currency} • ${t.note.isEmpty ? "(no note)" : t.note}'),
                          subtitle: Text('${t.date.toLocal()}'.split(' ').first),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await MonthlyStore.instance.deleteTxn(t.id);
                              setState(() {});
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                // ===== MonthlyScreen: Categories & Txns — END =====
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
          Text('Income (this month): ${summary.totalIncome.toStringAsFixed(2)} ${summary.currency}',
              style: Theme.of(context).textTheme.bodySmall),
          Text('Monthly expenses (manual): ${summary.totalMonthExpenses.toStringAsFixed(2)} ${summary.currency}',
              style: Theme.of(context).textTheme.bodySmall),
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

class _CategoryTile extends StatelessWidget {
  final MonthlyCategory category;
  final String monthKey;
  final String sectionType;

  const _CategoryTile({
    required this.category,
    required this.monthKey,
    required this.sectionType,
  });

  @override
  Widget build(BuildContext context) {
    final subs = MonthlyStore.instance
        .categoriesFor(monthKey, type: sectionType, parentId: category.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          title: Text(category.name),
          leading: const Icon(Icons.folder_open),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add sub-category',
            onPressed: () async {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => CategoryEditorSheet(
                    monthKey: monthKey, type: sectionType, parent: category),
              );
              (context as Element).markNeedsBuild();
            },
          ),
        ),
        if (subs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              children: [
                for (final s in subs)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.subdirectory_arrow_right),
                    title: Text(s.name),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
