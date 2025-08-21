// ===== budget_detail_screen.dart — START =====
// Description: Drill-in for a Monthly budget: header summary, category tree, txns list,
// plus quick actions to add category/sub-category/txn. Uses your MonthlyStore + sheets.

import 'package:flutter/material.dart';
import '../../services/api_service.dart'; // ignore: unused_import
import '../../services/monthly_store.dart';
import '../../models/monthly_category.dart';
import '../../models/monthly_txn.dart';
// 👇 re-use your editors already in the repo
import 'category_editor_sheet.dart';
import 'txn_editor_sheet.dart';

// If ApiService instance is available from higher level, you can thread it in later.
// For now this screen uses local MonthlyStore (Hive) and your existing FX-free totals.

class BudgetDetailScreen extends StatefulWidget {
  final String budgetId;
  final String budgetName;
  final String currency;       // month currency
  final DateTime month;

  const BudgetDetailScreen({
    super.key,
    required this.budgetId,
    required this.budgetName,
    required this.currency,
    required this.month,
  });

  @override
  State<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends State<BudgetDetailScreen> {
  late final String _monthKey;

  // 👇 NEW: local caches
  List<MonthlyCategory> _incomeCats = [];
  List<MonthlyCategory> _expenseCats = [];
  List<MonthlyTxn> _txns = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _monthKey = '${widget.month.year}-${widget.month.month.toString().padLeft(2, '0')}';
    _reload(); // no awaits inside setState
  }

  // 👇 NEW: load categories/txns — ensure no async work inside setState
  Future<void> _reload() async {
    final income = MonthlyStore.instance.categoriesFor(_monthKey, type: 'income', parentId: null);
    final expense = MonthlyStore.instance.categoriesFor(_monthKey, type: 'expense', parentId: null);
    final txns = MonthlyStore.instance.txnsFor(_monthKey);

    if (!mounted) return;
    setState(() {
      _incomeCats = income;
      _expenseCats = expense;
      _txns = txns;
      _loading = false;
    });
  }

  // 👇 NEW: quick add actions — open your existing sheets
  Future<void> _addCategory(String type, {MonthlyCategory? parent}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryEditorSheet(monthKey: _monthKey, type: type, parent: parent),
    );
    await _reload();
  }

  Future<void> _addTxn(String type) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TxnEditorSheet(monthKey: _monthKey, type: type),
    );
    await _reload();
  }

  Future<void> _cloneToNextMonth() async {
    // Clone: create next month budget (server), then copy local categories (Hive)
    final next = DateTime(widget.month.year, widget.month.month + 1, 1);
    final nextKey = '${next.year}-${next.month.toString().padLeft(2, '0')}';

    // 1) Copy category tree locally now (fast UX). Server budget clone is optional and can be done later.
    await MonthlyStore.instance.cloneMonth(fromMonthKey: _monthKey, toMonthKey: nextKey);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cloned categories to ${nextKey}. Open next month to start planning.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.budgetName.isEmpty ? 'Monthly Budget' : widget.budgetName;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          // 👇 NEW: clone & overflow
          IconButton(
            tooltip: 'Clone to next month',
            onPressed: _cloneToNextMonth,
            icon: const Icon(Icons.copy_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'add_income') _addTxn('income');
              if (v == 'add_expense') _addTxn('expense');
              if (v == 'add_income_cat') _addCategory('income');
              if (v == 'add_expense_cat') _addCategory('expense');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'add_income', child: Text('Add salary / income')),
              PopupMenuItem(value: 'add_expense', child: Text('Add expense')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'add_income_cat', child: Text('New income category')),
              PopupMenuItem(value: 'add_expense_cat', child: Text('New expense category')),
            ],
          ),
        ],
      ),
      floatingActionButton: _fab(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _HeaderSummary(monthKey: _monthKey, currency: widget.currency),
                const SizedBox(height: 12),
                _CategorySection(
                  label: 'Income',
                  monthKey: _monthKey,
                  categories: _incomeCats,
                  onAddSub: (parent) => _addCategory('income', parent: parent),
                ),
                const SizedBox(height: 12),
                _CategorySection(
                  label: 'Expenses',
                  monthKey: _monthKey,
                  categories: _expenseCats,
                  onAddSub: (parent) => _addCategory('expense', parent: parent),
                ),
                const SizedBox(height: 12),
                _TxnList(txns: _txns),
              ],
            ),
    );
  }

  // 👇 NEW: FAB menu (mirrors AppBar actions)
  Widget _fab() => PopupMenuButton<String>(
        icon: const Icon(Icons.add),
        onSelected: (v) {
          if (v == 'cat_i') _addCategory('income');
          if (v == 'cat_e') _addCategory('expense');
          if (v == 'txn_i') _addTxn('income');
          if (v == 'txn_e') _addTxn('expense');
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'txn_i', child: Text('Add income')),
          PopupMenuItem(value: 'txn_e', child: Text('Add expense')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'cat_i', child: Text('New income category')),
          PopupMenuItem(value: 'cat_e', child: Text('New expense category')),
        ],
      );
}

// --- Header summary (simple local compute from MonthlyStore) ---
class _HeaderSummary extends StatelessWidget {
  final String monthKey;
  final String currency;
  const _HeaderSummary({required this.monthKey, required this.currency});

  double _sum(Iterable<double> xs) => xs.fold(0.0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    // Spent = Σ expenses (type='expense'); Income = Σ income (type='income')
    final txns = MonthlyStore.instance.txnsFor(monthKey);
    final totalIncome  = _sum(txns.where((t) => t.type == 'income').map((t) => t.amount));
    final totalExpense = _sum(txns.where((t) => t.type == 'expense').map((t) => t.amount));
    final leftOver = totalIncome - totalExpense;
    final pct = totalIncome <= 0 ? 0.0 : (totalExpense / totalIncome).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Left Over', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Text('${leftOver.toStringAsFixed(2)} $currency',
              style: Theme.of(context).textTheme.titleMedium),
        ]),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: pct, minHeight: 10),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Spent ${totalExpense.toStringAsFixed(2)} $currency')),
          Expanded(
            child: Text('${(pct * 100).toStringAsFixed(2)}% of income spent',
                textAlign: TextAlign.end),
          ),
        ]),
      ]),
    );
  }
}

// --- Category section with inline sub-categories ---
class _CategorySection extends StatelessWidget {
  final String label;
  final String monthKey;
  final List<MonthlyCategory> categories;
  final void Function(MonthlyCategory parent) onAddSub;

  const _CategorySection({
    required this.label,
    required this.monthKey,
    required this.categories,
    required this.onAddSub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
        ]),
        const SizedBox(height: 8),
        for (final c in categories) _CategoryTile(monthKey: monthKey, category: c, onAddSub: onAddSub),
      ]),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String monthKey;
  final MonthlyCategory category;
  final void Function(MonthlyCategory parent) onAddSub;

  const _CategoryTile({required this.monthKey, required this.category, required this.onAddSub});

  @override
  Widget build(BuildContext context) {
    final subs = MonthlyStore.instance.categoriesFor(monthKey, type: category.type, parentId: category.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: const CircleAvatar(child: Icon(Icons.folder_open, size: 18)),
          title: Text(category.name),
          trailing: IconButton(
            tooltip: 'Add sub-category',
            icon: const Icon(Icons.add),
            onPressed: () => onAddSub(category),
          ),
        ),
        if (subs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 32),
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

class _TxnList extends StatelessWidget {
  final List<MonthlyTxn> txns;
  const _TxnList({required this.txns});

  @override
  Widget build(BuildContext context) {
    if (txns.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: const Text('No transactions yet'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transactions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final t in txns.take(30))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${t.type == 'income' ? '+' : '-'} ${t.amount.toStringAsFixed(2)} ${t.currency}'),
            subtitle: Text(t.note.isEmpty ? _fmt(t.date) : '${_fmt(t.date)} • ${t.note}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await MonthlyStore.instance.deleteTxn(t.id);
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
                (context as Element).markNeedsBuild();
              },
            ),
          ),
      ],
    );
  }

  static String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
}
// ===== budget_detail_screen.dart — END =====
