import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/monthly_category.dart';
import '../services/monthly_store.dart';
import '../services/monthly_calc.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  final ApiService api;
  const MonthlyBudgetScreen({super.key, required this.api});
  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen>
    with TickerProviderStateMixin {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<MonthlyCategory>> _envFut;
  String _ccy = 'EUR'; // monthly base currency (can add a setting later)
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  void _load() {
    _envFut = MonthlyStore.load(_month);
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final months = List.generate(15, (i) {
      final d = DateTime(now.year, now.month - 7 + i);
      return DateTime(d.year, d.month);
    });
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        children: months
            .map((m) => ListTile(
                  title: Text('${_m(m.month)} ${m.year}'),
                  onTap: () => Navigator.pop(ctx, m),
                ))
            .toList(),
      ),
    );
    if (picked != null) setState(() {
      _month = picked;
      _load();
    });
  }

  // Add/Edit dialogs
  Future<void> _addCategory(MonthlyKind kind) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New ${kind == MonthlyKind.income ? "Income" : "Expense"} Category'),
        content: TextField(
            controller: name, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final list = await _envFut;
    final next = [
      ...list,
      MonthlyCategory(
        id: 'cat_${DateTime.now().millisecondsSinceEpoch}',
        kind: kind,
        name: name.text.trim(),
        currency: _ccy,
        subs: const [],
      ),
    ];
    await MonthlyStore.save(_month, next);
    if (mounted) setState(_load);
  }

  Future<void> _addSub(MonthlyCategory cat) async {
    final name = TextEditingController();
    final planned = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add subcategory to ${cat.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          TextField(
              controller: planned,
              decoration: const InputDecoration(labelText: 'Planned'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final list = await _envFut;
    final idx = list.indexWhere((c) => c.id == cat.id);
    if (idx < 0) return;
    final sub = MonthlySubcategory(
      id: 'sub_${DateTime.now().millisecondsSinceEpoch}',
      name: name.text.trim(),
      planned: double.tryParse(planned.text.trim()) ?? 0,
    );
    final updated = list[idx].copyWith(subs: [...list[idx].subs, sub]);
    final next = [...list]..[idx] = updated;
    await MonthlyStore.save(_month, next);
    if (mounted) setState(_load);
  }

  Future<void> _editSub(MonthlyCategory cat, MonthlySubcategory sub) async {
    final name = TextEditingController(text: sub.name);
    final planned = TextEditingController(text: sub.planned.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${cat.name} ▸ ${sub.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          TextField(
              controller: planned,
              decoration: const InputDecoration(labelText: 'Planned'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final list = await _envFut;
    final ci = list.indexWhere((c) => c.id == cat.id);
    if (ci < 0) return;
    final si = list[ci].subs.indexWhere((s) => s.id == sub.id);
    if (si < 0) return;
    final updSub = sub.copyWith(
      name: name.text.trim().isEmpty ? sub.name : name.text.trim(),
      planned: double.tryParse(planned.text.trim()) ?? sub.planned,
    );
    final nextSubs = [...list[ci].subs]..[si] = updSub;
    final updCat = list[ci].copyWith(subs: nextSubs);
    final next = [...list]..[ci] = updCat;
    await MonthlyStore.save(_month, next);
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _pickMonth,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${_m(_month.month)} ${_month.year}'),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 18),
          ]),
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Categories')],
        ),
      ),
      floatingActionButton: _tabs.index == 1
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'fab-income',
                  onPressed: () => _addCategory(MonthlyKind.income),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Income'),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'fab-expense',
                  onPressed: () => _addCategory(MonthlyKind.expense),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Expense'),
                ),
              ],
            )
          : null,
      body: FutureBuilder<List<MonthlyCategory>>(
        future: _envFut,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final envs = snap.data!;
          return TabBarView(
            controller: _tabs,
            children: [
              _overview(envs),
              _categories(envs),
            ],
          );
        },
      ),
    );
  }

  Widget _overview(List<MonthlyCategory> envs) {
    return FutureBuilder<MonthlyTotals>(
      future: computeTotals(
          month: _month,
          envelopes: envs,
          monthlyCurrency: _ccy,
          api: widget.api),
      builder: (context, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final t = s.data!;
        final left = (t.planned - t.spent);
        final pctSpent = (t.planned <= 0) ? 0 : (t.spent / t.planned).clamp(0, 1.0);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _OverviewCard(
              leftOver: left,
              pctSpent: pctSpent,
              totalBudgeted: t.planned,
              remaining: left < 0 ? 0 : left,
              currency: t.currency,
            ),
            const SizedBox(height: 12),
            Text('Quick month picker',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(6, (i) {
                final d = DateTime(_month.year, _month.month - 2 + i);
                return ActionChip(
                  label: Text('${_m(d.month)} ${d.year}'),
                  onPressed: () => setState(() {
                    _month = DateTime(d.year, d.month);
                    _load();
                  }),
                );
              }),
            ),
          ],
        );
      },
    );
  }

  Widget _categories(List<MonthlyCategory> envs) {
    final income = envs.where((c) => c.kind == MonthlyKind.income).toList();
    final expense = envs.where((c) => c.kind == MonthlyKind.expense).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        const SizedBox(height: 8),
        _section('Income', income, allowAddSub: true),
        const SizedBox(height: 12),
        _section('Expenses', expense, allowAddSub: true),
      ],
    );
  }

  Widget _section(String title, List<MonthlyCategory> cats,
      {required bool allowAddSub}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...cats.map((c) {
          final planned = c.subs.fold<double>(0, (p, s) => p + s.planned);
          return Card(
            child: ExpansionTile(
              title: Text('${c.name} • Planned ${planned.toStringAsFixed(2)} ${c.currency}'),
              children: [
                for (final s in c.subs)
                  ListTile(
                    title: Text(s.name),
                    subtitle: const LinearProgressIndicator(
                      value: 0, // (wire a per-sub spent if you want later)
                      minHeight: 8,
                    ),
                    trailing:
                        Text('${s.planned.toStringAsFixed(2)} ${c.currency}'),
                    onTap: () => _editSub(c, s),
                  ),
                if (allowAddSub)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _addSub(c),
                      icon: const Icon(Icons.add),
                      label: const Text('Add subcategory'),
                    ),
                  ),
              ],
            ),
          );
        }),
      ]),
    );
  }

  String _m(int m) =>
      const [
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
}

class _OverviewCard extends StatelessWidget {
  final double leftOver;
  final double pctSpent; // 0..1
  final double totalBudgeted;
  final double remaining;
  final String currency;
  const _OverviewCard({
    required this.leftOver,
    required this.pctSpent,
    required this.totalBudgeted,
    required this.remaining,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Left Over', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            '${leftOver.toStringAsFixed(2)} $currency',
            style: Theme.of(context)
                .textTheme
                .headlineSmall!
                .copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: pctSpent,
            minHeight: 10,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: Text('Budget Spent ${(pctSpent * 100).toStringAsFixed(1)}%')),
              Text('Total ${totalBudgeted.toStringAsFixed(2)} $currency'),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(child: Text('Remaining to spend')),
              Text('${remaining.toStringAsFixed(2)} $currency'),
            ],
          ),
        ],
      ),
    );
  }
}
