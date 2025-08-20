import 'dart:math';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/monthly_service.dart';
import '../services/envelope_store.dart';
import '../services/envelope_links_store.dart';
import '../models/envelope.dart';
import '../models/budget.dart';
// 👇 NEW
import 'category_manager_screen.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  final ApiService api;
  const MonthlyBudgetScreen({super.key, required this.api});
  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen> {
  late DateTime _month; // normalized to 1st day
  late MonthlyService _svc;
  late Future<({MonthlyBudgetSummary summary, List<EnvelopeSpend> envelopes})> _future;

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
    _svc = MonthlyService(widget.api);
    _future = _svc.load(_month);
  }

  Future<void> _reload() async {
    final fut = _svc.load(_month);
    if (!mounted) return;
    setState(() => _future = fut);
    await fut;
  }

  Future<void> _pickMonth() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final base = _month;
        final months = List.generate(13, (i) {
          final d = DateTime(base.year, base.month - 6 + i, 1);
          return d;
        });
        return ListView(
          children: months
              .map((m) => ListTile(
                    title: Text('${_name(m.month)} ${m.year}'),
                    onTap: () => Navigator.pop(ctx, m),
                  ))
              .toList(),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _month = DateTime(picked.year, picked.month, 1);
      });
      await _reload();
    }
  }

  String _name(int m) => const [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
  ][(m - 1) % 12];

  Future<void> _addEnvelope({String? parentId}) async {
    EnvelopeType type = parentId == null ? EnvelopeType.expense : EnvelopeType.expense;
    final name = TextEditingController();
    final planned = TextEditingController(text: '0');
    final isIncome = ValueNotifier<bool>(false);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(parentId == null ? 'New Category' : 'New Sub‑category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(
              controller: planned,
              decoration: const InputDecoration(labelText: 'Planned (Home currency)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            if (parentId == null) ...[
              const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: isIncome,
                builder: (_, v, __) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('This is Income (e.g., Salary)'),
                  value: v,
                  onChanged: (x) => isIncome.value = x ?? false,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final id = 'env_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final env = EnvelopeDef(
      id: id,
      name: name.text.trim(),
      type: parentId == null
          ? (isIncome.value ? EnvelopeType.income : EnvelopeType.expense)
          : EnvelopeType.expense,
      planned: double.tryParse(planned.text.trim()) ?? 0,
      currency: (await _svc.api.convert(amount: 0, from: 'EUR', to: 'EUR')) != 0 ? 'EUR' : 'EUR', // kept as Home; MonthlyService normalizes
      parentId: parentId,
    );
    await EnvelopeStore.upsert(_month, env);
    await _reload();
  }

  Future<void> _editEnvelope(EnvelopeDef def) async {
    final name = TextEditingController(text: def.name);
    final planned = TextEditingController(text: def.planned.toStringAsFixed(2));
    EnvelopeType type = def.type;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Envelope'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(
              controller: planned,
              decoration: const InputDecoration(labelText: 'Planned'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            if (def.parentId == null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<EnvelopeType>(
                value: type,
                items: const [
                  DropdownMenuItem(value: EnvelopeType.expense, child: Text('Expense')),
                  DropdownMenuItem(value: EnvelopeType.income,  child: Text('Income')),
                ],
                onChanged: (v) => type = v ?? type,
                decoration: const InputDecoration(labelText: 'Type'),
              ),
            ]
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await EnvelopeStore.upsert(_month, def.copyWith(
      name: name.text.trim(),
      type: def.parentId == null ? type : EnvelopeType.expense,
      planned: double.tryParse(planned.text.trim()) ?? def.planned,
    ));
    await _reload();
  }

  Future<void> _deleteEnvelope(EnvelopeDef def) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: const Text('This will remove the category and any sub‑categories.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    // Load all, drop def and its children
    final list = await EnvelopeStore.load(_month);
    final next = list.where((e) => e.id != def.id && e.parentId != def.id).toList();
    await EnvelopeStore.save(_month, next);
    await _reload();
  }

  Future<void> _linkTripBudgetToEnvelope(EnvelopeDef env) async {
    // Load budgets for month, pick one Trip budget that's linked to this month’s Monthly budget
    final all = await widget.api.fetchBudgetsOrCache();
    final monthly = all.where((b) => b.kind == BudgetKind.monthly && b.year == _month.year && b.month == _month.month).toList();
    final monthIds = monthly.map((b) => b.id).toSet();
    final trips = all.where((b) => b.kind == BudgetKind.trip && b.linkedMonthlyBudgetId != null && monthIds.contains(b.linkedMonthlyBudgetId!)).toList();

    if (trips.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No linked trip budgets for this month. Link a trip budget to this month in Budgets first.')));
      return;
    }

    final picked = await showDialog<Budget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Link Trip Budget → ${env.name}'),
        children: [
          for (final t in trips)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text('${t.name ?? 'Trip'} • ${t.amount.toStringAsFixed(0)} ${t.currency}'),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await EnvelopeLinksStore.setLink(_month, tripBudgetId: picked.id, envelopeId: env.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _pickMonth,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${_name(_month.month)} ${_month.year}'),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 18),
          ]),
        ),
        actions: [
          IconButton(onPressed: () { _reload(); }, icon: const Icon(Icons.refresh)),
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Manage categories',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryManagerScreen()));
              if (!mounted) return;
              // Optionally: refresh monthly data if you later aggregate by category.
              setState(() { /* keep as-is; your _load() already refreshes on pull */ });
            },
          ),
        ],
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEnvelope(),
        label: const Text('Add Category'),
        icon: const Icon(Icons.add),
      ),
      body: FutureBuilder<({MonthlyBudgetSummary summary, List<EnvelopeSpend> envelopes})>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load: ${snap.error}'));
          }
          final data = snap.data!;
          final summary = data.summary;
          final envs = data.envelopes;

          // group to parent -> children
          final parents = envs.where((e) => e.def.parentId == null).toList();
          final childrenByParent = <String, List<EnvelopeSpend>>{};
          for (final e in envs.where((e) => e.def.parentId != null)) {
            childrenByParent.putIfAbsent(e.def.parentId!, () => []).add(e);
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              _HeaderCard(summary: summary),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _LegendRow(pct: summary.pctSpent),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Categories', style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
              ),
              ...parents.map((p) {
                final kids = childrenByParent[p.def.id] ?? const <EnvelopeSpend>[];
                return _EnvelopeCard(
                  env: p,
                  children: kids,
                  onAddSub: () => _addEnvelope(parentId: p.def.id),
                  onEdit: () => _editEnvelope(p.def),
                  onDelete: () => _deleteEnvelope(p.def),
                  onLinkTripBudget: () => _linkTripBudgetToEnvelope(p.def),
                );
              }),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final MonthlyBudgetSummary summary;
  const _HeaderCard({required this.summary});

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
                      Text('Left Over', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(
                        '${summary.remaining.toStringAsFixed(2)} ${summary.currency}',
                        style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(pct * 100).toStringAsFixed(2)}% of income spent',
                        style: Theme.of(context).textTheme.labelMedium!.copyWith(color: cs.secondary),
                      ),
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
            leftValue: '${summary.totalExpensePlanned.toStringAsFixed(2)} ${summary.currency}',
            midLabel: 'Spent',
            midValue:  '${summary.totalSpent.toStringAsFixed(2)} ${summary.currency}',
            rightLabel: 'Remaining',
            rightValue: '${summary.remaining.toStringAsFixed(2)} ${summary.currency}',
          ),
        ],
      ),
    );
  }
}

class _EnvelopeCard extends StatelessWidget {
  final EnvelopeSpend env;
  final List<EnvelopeSpend> children;
  final VoidCallback onAddSub;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLinkTripBudget;

  const _EnvelopeCard({
    required this.env,
    required this.children,
    required this.onAddSub,
    required this.onEdit,
    required this.onDelete,
    required this.onLinkTripBudget,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isIncome = env.def.type == EnvelopeType.income;
    final barColor = isIncome ? cs.tertiary : cs.primary;
    final pct = env.pct;

    Widget row(EnvelopeSpend e, {bool isChild = false}) {
      return Padding(
        padding: EdgeInsets.fromLTRB(isChild ? 40 : 0, 6, 0, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!isChild)
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: barColor.withOpacity(.15),
                    child: Text(e.def.name.isNotEmpty ? e.def.name[0].toUpperCase() : '?',
                        style: TextStyle(color: barColor, fontWeight: FontWeight.w900)),
                  ),
                if (!isChild) const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.def.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: e.pct,
                          minHeight: 10,
                          color: barColor,
                          backgroundColor: cs.surfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(child: Text('Spending  ${e.spent.toStringAsFixed(2)} ${e.def.currency}', style: Theme.of(context).textTheme.labelSmall)),
                          Expanded(child: Text('Planned  ${e.def.planned.toStringAsFixed(2)} ${e.def.currency}', textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelSmall)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isChild)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'add_sub') onAddSub();
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                      if (v == 'link_trip') onLinkTripBudget();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'add_sub', child: Text('Add sub‑category')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'link_trip', child: Text('Link Trip Budget')),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
    }

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
          row(env),
          for (final c in children) row(c, isChild: true),
        ],
      ),
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
          CircularProgressIndicator(value: 1, strokeWidth: 10, color: cs.surfaceVariant),
          CircularProgressIndicator(value: value, strokeWidth: 10, color: cs.primary),
          Text('${(value * 100).round()}%',
              style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
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

class _LegendRow extends StatelessWidget {
  final double pct;
  const _LegendRow({required this.pct});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        _LegendChip(icon: Icons.account_balance_wallet_outlined, label: 'Budget Spent', color: cs.primary),
        const Spacer(),
        Text('${(pct * 100).toStringAsFixed(2)}%', style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _LegendChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: t.labelSmall!.copyWith(fontWeight: FontWeight.w500, color: color)),
      ]),
    );
  }
}

