import 'package:flutter/material.dart';
import '../services/api_service.dart';
// 👇 NEW: Monthly view-models for this screen
import '../models/monthly.dart';
import '../models/budget.dart'; // for BudgetKind
// 👇 NEW: categories & monthly txns
import '../models/category.dart';
import '../models/monthly_txn.dart';
import '../services/category_store.dart';
import '../services/monthly_store.dart';
import 'category_manager_screen.dart';

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

  String _monthName(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  Future<void> _openAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
      await _createEnvelopeDialog(); // do the async work first…
      if (!mounted) return;
      setState(_load); // …then refresh synchronously
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create: $e')),
      );
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
                // ▶︎ Add income/expense menu start
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Add to this month',
                  onPressed: () => _addToMonth(context, env),
                ),
                // ◀︎ Add income/expense menu end
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

// ▶︎ Monthly add helpers start
Future<void> _addToMonth(BuildContext context, EnvelopeVM env) async {
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
              onTap: () => Navigator.pop(context, 'income'),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Add monthly expense'),
              onTap: () => Navigator.pop(context, 'expense'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null) return;
    if (choice == 'income') {
      await _createMonthlyTxnDialog(context, env, kind: MonthlyTxnKind.income);
    } else {
      await _createMonthlyTxnDialog(context, env, kind: MonthlyTxnKind.expense);
    }
    // After save → soft reload
    // NOTE: call into parent state via the nearest State using context.findAncestorStateOfType
    final st = context.findAncestorStateOfType<State>();
    if (st is _MonthlyBudgetScreenState) {
      st.setState(st._load); // sync refresh (no async in setState)
    }
  }

Future<void> _createMonthlyTxnDialog(
  BuildContext context,
  EnvelopeVM env, {
  required MonthlyTxnKind kind,
}) async {
    final monthKey = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    final isIncome = kind == MonthlyTxnKind.income;
    final roots = isIncome ? await CategoryStore.roots(CategoryType.income)
                           : await CategoryStore.roots(CategoryType.expense);
    String? rootId = roots.isNotEmpty ? roots.first.id : null;
    final subs = (rootId == null) ? <CategoryItem>[] : await CategoryStore.subsOf(rootId);
    String? subId = subs.isNotEmpty ? subs.first.id : null;

    final amountCtrl = TextEditingController();
    final currencyCtrl = TextEditingController(text: env.currency);
    final noteCtrl = TextEditingController();
    DateTime when = DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: Text(isIncome ? 'Add salary / income' : 'Add monthly expense'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Category pickers
                  DropdownButtonFormField<String>(
                    value: rootId,
                    items: roots.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                    decoration: const InputDecoration(labelText: 'Category'),
                    onChanged: (v) async {
                      rootId = v;
                      final nextSubs = (v == null) ? <CategoryItem>[] : await CategoryStore.subsOf(v);
                      setD(() {
                        subId = nextSubs.isNotEmpty ? nextSubs.first.id : null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: subId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— none —')),
                      ...((rootId == null) ? <CategoryItem>[] : (subs))
                          .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
                    ],
                    decoration: const InputDecoration(labelText: 'Subcategory (optional)'),
                    onChanged: (v) => setD(() => subId = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: isIncome ? 'Amount (salary)' : 'Amount'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: currencyCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Currency (ISO)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Note (optional)'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text('${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: when,
                      );
                      if (picked != null) setD(() => when = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final id = 'mtx-${DateTime.now().millisecondsSinceEpoch}';
                  final txn = MonthlyTxn(
                    id: id,
                    monthKey: monthKey,
                    kind: kind,
                    currency: currencyCtrl.text.trim().toUpperCase(),
                    amount: double.tryParse(amountCtrl.text.trim()) ?? 0,
                    date: when,
                    categoryId: rootId,
                    subcategoryId: subId,
                    note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  );
                  await MonthlyStore.add(monthKey, txn);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }
  // ◀︎ Monthly add helpers end

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
