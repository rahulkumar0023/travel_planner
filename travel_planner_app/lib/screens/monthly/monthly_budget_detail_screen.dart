import 'package:flutter/material.dart';

import '../../models/monthly.dart';
import '../../models/monthly_category.dart';
import '../../models/monthly_txn.dart';
import '../../services/api_service.dart';
import '../../services/monthly_store.dart';
import '../../services/trip_storage_service.dart';
import 'category_editor_sheet.dart';
import 'txn_editor_sheet.dart';

class MonthlyBudgetDetailScreen extends StatefulWidget {
  const MonthlyBudgetDetailScreen({
    super.key,
    required this.month,
    required this.envelope,
    required this.summary,
    required this.api,
  });

  final DateTime month;
  final EnvelopeVM envelope;
  final MonthlyBudgetSummary summary;
  final ApiService api;

  @override
  State<MonthlyBudgetDetailScreen> createState() => _MonthlyBudgetDetailScreenState();
}

class _MonthlyBudgetDetailScreenState extends State<MonthlyBudgetDetailScreen> {
  late Future<void> _loadFuture;
  List<MonthlyCategory> _categories = const [];
  List<MonthlyTxn> _txns = const [];
  late MonthlyBudgetSummary _summary;

  String get _monthKey => '${widget.month.year}-${widget.month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _summary = widget.summary;
    _loadFuture = _refresh();
  }

  Future<void> _refresh() async {
    final summary = await widget.api.fetchMonthlySummary(widget.month);
    final cats = await MonthlyStore.instance.categories(_monthKey);
    final txns = await MonthlyStore.all(_monthKey);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _categories = cats;
      _txns = txns;
    });
  }

  List<MonthlyCategory> _roots(String type) => _categories
      .where((c) => c.parentId == null && c.kind.name == type)
      .toList();

  _CategorySectionData _computeSection({
    required String label,
    required List<MonthlyCategory> categories,
    required MonthlyTxnKind kind,
  }) {
    final catActual = <String, double>{};
    final subActual = <String, double>{};

    for (final txn in _txns) {
      if (txn.kind != kind) continue;
      if (txn.categoryId != null && txn.categoryId!.isNotEmpty) {
        catActual.update(txn.categoryId!, (value) => value + txn.amount,
            ifAbsent: () => txn.amount);
      }
      if (txn.subCategoryId != null && txn.subCategoryId!.isNotEmpty) {
        subActual.update(txn.subCategoryId!, (value) => value + txn.amount,
            ifAbsent: () => txn.amount);
      }
    }

    final groups = <_CategoryGroupData>[];
    double totalPlanned = 0;
    double totalActual = 0;

    for (final category in categories) {
      final subs = <_SubCategoryRow>[];
      double subsPlanned = 0;
      double subsActualTotal = 0;

      for (final sub in category.subs) {
        final actual = subActual[sub.id] ?? 0;
        subsActualTotal += actual;
        subsPlanned += sub.planned;
        subs.add(
          _SubCategoryRow(subCategory: sub, planned: sub.planned, actual: actual),
        );
      }

      final directActual = catActual[category.id] ?? 0;
      final catActualTotal = directActual + subsActualTotal;
      final catPlanned = subsPlanned + category.planned;

      totalPlanned += catPlanned;
      totalActual += catActualTotal;

      groups.add(_CategoryGroupData(
        category: category,
        planned: catPlanned,
        actual: catActualTotal,
        subs: subs,
      ));
    }

    return _CategorySectionData(
      label: label,
      groups: groups,
      totalPlanned: totalPlanned,
      totalActual: totalActual,
    );
  }

  Future<void> _addCategory() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.trending_up_outlined),
              title: const Text('Income category'),
              onTap: () => Navigator.pop(context, 'income'),
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined),
              title: const Text('Expense category'),
              onTap: () => Navigator.pop(context, 'expense'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted || type == null) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryEditorSheet(monthKey: _monthKey, type: type),
    );
    if (!mounted) return;
    if (saved == true) {
      _loadFuture = _refresh();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _addSubcategory() async {
    final incomeCats = _roots('income');
    final expenseCats = _roots('expense');

    if (incomeCats.isEmpty && expenseCats.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a category first.')),
      );
      return;
    }

    final pick = await showModalBottomSheet<MonthlyCategory>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Add sub-category to…',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final c in incomeCats)
              ListTile(
                leading: const Icon(Icons.trending_up_outlined),
                title: Text(c.name),
                subtitle: const Text('Income'),
                onTap: () => Navigator.pop(ctx, c),
              ),
            for (final c in expenseCats)
              ListTile(
                leading: const Icon(Icons.shopping_cart_outlined),
                title: Text(c.name),
                subtitle: const Text('Expense'),
                onTap: () => Navigator.pop(ctx, c),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (!mounted || pick == null) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryEditorSheet(
        monthKey: _monthKey,
        type: pick.kind.name,
        parent: pick,
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      _loadFuture = _refresh();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _addSubcategoryFor(MonthlyCategory parent) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryEditorSheet(
        monthKey: _monthKey,
        type: parent.kind.name,
        parent: parent,
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      _loadFuture = _refresh();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _deleteCategory(MonthlyCategory category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category'),
        content:
            Text('Delete "${category.name}" and all transactions assigned to it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await MonthlyStore.instance.deleteCategory(
      monthKey: _monthKey,
      categoryId: category.id,
    );
    if (!mounted) return;
    _loadFuture = _refresh();
    setState(() {});
  }

  Future<void> _deleteSubcategory(
      MonthlyCategory parent, MonthlySubCategory sub) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete subcategory'),
        content: Text('Delete "${sub.name}" from ${parent.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await MonthlyStore.instance.deleteCategory(
      monthKey: _monthKey,
      categoryId: sub.id,
      parentId: parent.id,
    );
    if (!mounted) return;
    _loadFuture = _refresh();
    setState(() {});
  }

  Future<void> _deleteTxn(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry'),
        content: const Text('Remove this income/expense entry?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await MonthlyStore.instance.deleteTxn(id);
    if (!mounted) return;
    _loadFuture = _refresh();
    setState(() {});
  }

  Future<void> _addTxn(String type) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TxnEditorSheet(monthKey: _monthKey, type: type),
    );
    if (!mounted) return;
    if (saved == true) {
      _loadFuture = _refresh();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _openCreateMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Create',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('New Expense'),
              onTap: () => Navigator.pop(context, 'expense'),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('New Income'),
              onTap: () => Navigator.pop(context, 'income'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('New Category'),
              onTap: () => Navigator.pop(context, 'category'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'expense' || choice == 'income') {
      await _addTxn(choice);
    } else if (choice == 'category') {
      await _addCategory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = _summary.currency.isEmpty
        ? TripStorageService.getHomeCurrency()
        : _summary.currency;
    final incomeSection = _computeSection(
      label: 'Income overview',
      categories: _roots('income'),
      kind: MonthlyTxnKind.income,
    );
    final expenseSection = _computeSection(
      label: 'Expense overview',
      categories: _roots('expense'),
      kind: MonthlyTxnKind.expense,
    );

    final titleText = widget.envelope.name.isEmpty
        ? '${widget.month.month}/${widget.month.year}'
        : widget.envelope.name;
    final subText = '${widget.month.year}-${widget.month.month.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titleText),
            Text(subText, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateMenu,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Add category',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: _addCategory,
              ),
              IconButton(
                tooltip: 'Add subcategory',
                icon: const Icon(Icons.playlist_add_outlined),
                onPressed: _addSubcategory,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Log income',
                icon: const Icon(Icons.payments_outlined),
                onPressed: () => _addTxn('income'),
              ),
              IconButton(
                tooltip: 'Log expense',
                icon: const Icon(Icons.receipt_long_outlined),
                onPressed: () => _addTxn('expense'),
              ),
            ],
          ),
        ),
      ),
      body: FutureBuilder(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              _HeaderCard(
                summary: _summary,
                currency: currency,
                envelope: widget.envelope,
              ),
              const SizedBox(height: 16),
              if (incomeSection.groups.isNotEmpty) ...[
                _SectionHeader(title: incomeSection.label),
                ...incomeSection.groups.map(
                  (g) => _CategoryExpansion(
                    data: g,
                    currency: currency,
                    isIncome: true,
                    onAddSubcategory: _addSubcategoryFor,
                    onDeleteCategory: _deleteCategory,
                    onDeleteSubcategory: _deleteSubcategory,
                  ),
                ),
                _SectionTotal(
                  label: 'Total income',
                  actual: incomeSection.totalActual,
                  planned: incomeSection.totalPlanned,
                  currency: currency,
                  isIncome: true,
                ),
                const SizedBox(height: 24),
              ],
              if (expenseSection.groups.isNotEmpty) ...[
                _SectionHeader(title: expenseSection.label),
                ...expenseSection.groups.map(
                  (g) => _CategoryExpansion(
                    data: g,
                    currency: currency,
                    isIncome: false,
                    onAddSubcategory: _addSubcategoryFor,
                    onDeleteCategory: _deleteCategory,
                    onDeleteSubcategory: _deleteSubcategory,
                  ),
                ),
                _SectionTotal(
                  label: 'Total expenses',
                  actual: expenseSection.totalActual,
                  planned: expenseSection.totalPlanned,
                  currency: currency,
                  isIncome: false,
                ),
                const SizedBox(height: 24),
              ],
              _SavingsCallout(
                currency: currency,
                income: _summary.totalIncome,
                expenses: _summary.totalMonthExpenses,
              ),
              if (_txns.isNotEmpty) ...[
                const SizedBox(height: 24),
                _SectionHeader(title: 'Transactions'),
                ..._buildTransactions(_txns, _categories, _deleteTxn),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.summary,
    required this.currency,
    required this.envelope,
  });

  final MonthlyBudgetSummary summary;
  final String currency;
  final EnvelopeVM envelope;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
            envelope.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('Savings ${(summary.totalIncome - summary.totalMonthExpenses).toStringAsFixed(2)} $currency'),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Monthly budget'),
              Text('${envelope.planned.toStringAsFixed(2)} ${envelope.currency}'),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Spent so far'),
              Text('${envelope.spent.toStringAsFixed(2)} ${envelope.currency}'),
            ],
          ),
          const Divider(height: 24),
          const SizedBox(height: 8),
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
              const Text('Spent (trips + manual)'),
              Text('${summary.totalSpent.toStringAsFixed(2)} $currency'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _SectionTotal extends StatelessWidget {
  const _SectionTotal({
    required this.label,
    required this.actual,
    required this.planned,
    required this.currency,
    required this.isIncome,
  });

  final String label;
  final double actual;
  final double planned;
  final String currency;
  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final color = isIncome
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          Text(
            '${actual.toStringAsFixed(2)} / ${planned.toStringAsFixed(2)} $currency',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SavingsCallout extends StatelessWidget {
  const _SavingsCallout({
    required this.currency,
    required this.income,
    required this.expenses,
  });

  final String currency;
  final double income;
  final double expenses;

  @override
  Widget build(BuildContext context) {
    final net = income - expenses;
    final positive = net >= 0;
    final cs = Theme.of(context).colorScheme;
    final bg = positive ? cs.secondaryContainer : cs.errorContainer;
    final fg = positive ? cs.onSecondaryContainer : cs.onErrorContainer;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly balance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '${net.toStringAsFixed(2)} $currency',
            style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Income ${income.toStringAsFixed(2)} $currency · Expenses ${expenses.toStringAsFixed(2)} $currency',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: fg.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

List<Widget> _buildTransactions(
    List<MonthlyTxn> txns,
    List<MonthlyCategory> categories,
    void Function(String id) onDelete) {
  final sorted = [...txns]..sort((a, b) => b.date.compareTo(a.date));
  return sorted.map((txn) {
    final label = _labelForTxn(txn, categories);
    final isIncome = txn.kind == MonthlyTxnKind.income;
    final amountText =
        '${isIncome ? '+' : '-'} ${txn.amount.toStringAsFixed(2)} ${txn.currency}';
    final color = isIncome
        ? Colors.green.shade600
        : Colors.red.shade600;
    final dateText =
        '${txn.date.year}-${txn.date.month.toString().padLeft(2, '0')}-${txn.date.day.toString().padLeft(2, '0')}';
    return ListTile(
      leading:
          Icon(isIncome ? Icons.payments_outlined : Icons.receipt_long_outlined),
      title: Text(amountText,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      subtitle: Text('$label • $dateText'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => onDelete(txn.id),
      ),
    );
  }).toList();
}

String _labelForTxn(MonthlyTxn txn, List<MonthlyCategory> categories) {
  MonthlyCategory? parent;
  for (final c in categories) {
    if (c.id == txn.categoryId) {
      parent = c;
      break;
    }
  }
  final subId = txn.subCategoryId;
  if (subId != null && parent != null) {
    for (final sub in parent.subs) {
      if (sub.id == subId) {
        return '${parent.name} › ${sub.name}';
      }
    }
  }
  return parent?.name ?? 'Uncategorised';
}

class _CategoryExpansion extends StatelessWidget {
  const _CategoryExpansion({
    required this.data,
    required this.currency,
    required this.isIncome,
    required this.onAddSubcategory,
    required this.onDeleteCategory,
    required this.onDeleteSubcategory,
  });

  final _CategoryGroupData data;
  final String currency;
  final bool isIncome;
  final void Function(MonthlyCategory category) onAddSubcategory;
  final void Function(MonthlyCategory category) onDeleteCategory;
  final void Function(MonthlyCategory parent, MonthlySubCategory sub)
      onDeleteSubcategory;

  @override
  Widget build(BuildContext context) {
    final difference = data.actual - data.planned;
    final diffText = difference == 0
        ? 'On track'
        : '${difference > 0 ? '+' : ''}${difference.toStringAsFixed(2)} $currency';
    final diffColor = difference == 0
        ? Theme.of(context).textTheme.bodySmall?.color
        : (difference > 0
            ? (isIncome
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error)
            : Theme.of(context).colorScheme.tertiary);

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      leading: Icon(isIncome ? Icons.trending_up : Icons.shopping_cart_outlined),
      title: Text(data.category.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${data.actual.toStringAsFixed(2)} / ${data.planned.toStringAsFixed(2)} $currency',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(diffText, style: TextStyle(color: diffColor, fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: 'Add subcategory',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onAddSubcategory(data.category),
          ),
          IconButton(
            tooltip: 'Delete category',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onDeleteCategory(data.category),
          ),
        ],
      ),
      children: [
        if (data.subs.isEmpty)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('No subcategories yet'),
            trailing: IconButton(
              icon: const Icon(Icons.playlist_add_outlined),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Use “Add Subcategory” below.')),
                );
              },
            ),
          )
        else
          ...data.subs.map((sub) {
            final over = sub.actual - sub.planned;
            final overColor = over > 0 && !isIncome
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).textTheme.bodyMedium?.color;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(sub.subCategory.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${sub.actual.toStringAsFixed(2)} / ${sub.planned.toStringAsFixed(2)} $currency',
                    style: TextStyle(color: overColor),
                  ),
                  IconButton(
                    tooltip: 'Delete subcategory',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        onDeleteSubcategory(data.category, sub.subCategory),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _CategoryGroupData {
  _CategoryGroupData({
    required this.category,
    required this.planned,
    required this.actual,
    required this.subs,
  });

  final MonthlyCategory category;
  final double planned;
  final double actual;
  final List<_SubCategoryRow> subs;
}

class _SubCategoryRow {
  _SubCategoryRow({
    required this.subCategory,
    required this.planned,
    required this.actual,
  });

  final MonthlySubCategory subCategory;
  final double planned;
  final double actual;
}

class _CategorySectionData {
  _CategorySectionData({
    required this.label,
    required this.groups,
    required this.totalPlanned,
    required this.totalActual,
  });

  final String label;
  final List<_CategoryGroupData> groups;
  final double totalPlanned;
  final double totalActual;
}
