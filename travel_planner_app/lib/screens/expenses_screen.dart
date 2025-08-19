import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/expense.dart';
import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import '../models/budget.dart'; // for BudgetKind
import 'receipt_viewer_screen.dart';

class ExpensesScreen extends StatefulWidget {
  final ApiService api;
  const ExpensesScreen({super.key, required this.api});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<List<Expense>> _future;
  Trip? _trip;

  // Filters
  String? _filterCategory;
  String? _filterCurrency;
  DateTimeRange? _filterRange;

  // Helpers
  List<Expense> _applyFilters(List<Expense> all) {
    Iterable<Expense> cur = all;

    if (_filterCategory != null) {
      cur = cur.where((e) => (e.category).toLowerCase() == _filterCategory!.toLowerCase());
    }
    if (_filterCurrency != null) {
      cur = cur.where((e) => (e.currency).toUpperCase() == _filterCurrency!.toUpperCase());
    }
    if (_filterRange != null) {
      final from = DateTime(_filterRange!.start.year, _filterRange!.start.month, _filterRange!.start.day);
      final to = DateTime(_filterRange!.end.year, _filterRange!.end.month, _filterRange!.end.day, 23, 59, 59);
      cur = cur.where((e) => e.date.isAfter(from.subtract(const Duration(milliseconds: 1))) && e.date.isBefore(to.add(const Duration(milliseconds: 1))));
    }
    final list = cur.toList()..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Map<String, double> _sumByCurrency(List<Expense> list) {
    final map = <String, double>{};
    for (final e in list) {
      final c = (e.currency).toUpperCase();
      map[c] = (map[c] ?? 0) + e.amount;
    }
    return map;
  }

  String _money(String ccy, num v) => '${v.toStringAsFixed(2)} $ccy';

  @override
  void initState() {
    super.initState();
    _trip = TripStorageService.loadLightweight();
    // 1) show local instantly (if dashboard saved anything to Hive)
    _future = _trip == null ? Future.value(<Expense>[]) : widget.api.fetchExpenses(_trip!.id);
  }

  Future<void> _refresh() async {
    _trip = TripStorageService.loadLightweight();
    setState(() {
      _future = _trip == null ? Future.value(<Expense>[]) : widget.api.fetchExpenses(_trip!.id);
    });
    await _future;
  }

  Future<List<String>> _currencyChoicesForTrip() async {
    final t = _trip;
    if (t == null) return <String>['EUR'];
    final budgets = await widget.api.fetchBudgetsOrCache();
    final set = <String>{t.currency.toUpperCase()};
    for (final b in budgets) {
      if (b.kind == BudgetKind.trip && b.tripId == t.id) {
        set.add(b.currency.toUpperCase());
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _pickCategory(List<Expense> source) async {
    final cats = <String>{for (final e in source) e.category}.toList()..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('All categories')),
            ...cats.map((c) => ListTile(
                  title: Text(c),
                  onTap: () => Navigator.pop(ctx, c),
                )),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _filterCategory = picked);
  }

  Future<void> _pickCurrency(List<Expense> source) async {
    final ccys = <String>{for (final e in source) e.currency.toUpperCase()}.toList()..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('All currencies')),
            ...ccys.map((c) => ListTile(
                  title: Text(c),
                  onTap: () => Navigator.pop(ctx, c),
                )),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _filterCurrency = picked);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final init = _filterRange ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 0));
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDateRange: init);
    if (r == null) return;
    setState(() => _filterRange = r);
  }

  String _csvEscape(String s) {
    final needs = s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r');
    if (!needs) return s;
    return '"${s.replaceAll('"', '""')}"';
  }

  Future<void> _exportCsv({required bool includeApprox}) async {
    final t = _trip;
    if (t == null) return;

    // freshest data
    final expenses = await widget.api.fetchExpenses(t.id);

    final sb = StringBuffer();
    final headers = [
      'id',
      'date',
      'title',
      'category',
      'paidBy',
      'sharedWith',
      'amount',
      'currency',
      if (includeApprox) 'approx_${t.currency}'
    ];
    sb.writeln(headers.join(','));

    for (final e in expenses) {
      final approx = includeApprox
          ? await widget.api.convert(amount: e.amount, from: e.currency, to: t.currency)
          : null;

      final row = [
        _csvEscape(e.id),
        _csvEscape(e.date.toIso8601String().split('T').first),
        _csvEscape(e.title),
        _csvEscape(e.category),
        _csvEscape(e.paidBy),
        _csvEscape(e.sharedWith.join('|')),
        e.amount.toStringAsFixed(2),
        e.currency.toUpperCase(),
        if (includeApprox) (approx ?? e.amount).toStringAsFixed(2),
      ];
      sb.writeln(row.join(','));
    }

    final dir = await getTemporaryDirectory();
    final fname = 'trip_${(t.name).replaceAll(' ', '_')}_${DateTime.now().toIso8601String().split('T').first}.csv';
    final file = File('${dir.path}/$fname');
    await file.writeAsString(sb.toString());

    await Share.shareXFiles([XFile(file.path)], subject: 'Trip expenses • ${t.name}');
  }

  Future<void> _editExpenseDialog(Expense e) async {
    final title = TextEditingController(text: e.title);
    final amount = TextEditingController(text: e.amount.toString());
    final category = TextEditingController(text: e.category);
    final paidBy = TextEditingController(text: e.paidBy);

    final choices = await _currencyChoicesForTrip();
    String currency = choices.contains(e.currency.toUpperCase())
        ? e.currency.toUpperCase()
        : (_trip?.currency.toUpperCase() ?? 'EUR');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 8),
            TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
            const SizedBox(height: 8),
            TextField(controller: paidBy, decoration: const InputDecoration(labelText: 'Paid by')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              onChanged: (v) => currency = (v ?? currency),
              items: choices.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      final updated = Expense(
        id: e.id,
        tripId: e.tripId,
        title: title.text.trim(),
        amount: double.tryParse(amount.text.trim()) ?? e.amount,
        category: category.text.trim(),
        date: e.date,
        paidBy: paidBy.text.trim(),
        sharedWith: e.sharedWith,
        currency: currency,
        receiptPath: e.receiptPath,
      );
      await widget.api.updateExpense(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () async {
              final choice = await showModalBottomSheet<bool>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.table_rows_outlined),
                        title: const Text('Export CSV'),
                        subtitle: const Text('Original currencies only'),
                        onTap: () => Navigator.pop(ctx, false),
                      ),
                      ListTile(
                        leading: const Icon(Icons.currency_exchange_outlined),
                        title: const Text('Export CSV (with ≈ trip currency)'),
                        subtitle: const Text('Adds converted column'),
                        onTap: () => Navigator.pop(ctx, true),
                      ),
                    ],
                  ),
                ),
              );
              if (choice == null) return;
              await _exportCsv(includeApprox: choice);
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Expense>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(child: Text('Failed to load expenses:\n${snap.error}')),
              ],
            );
          }
          final expenses = snap.data ?? <Expense>[];
          final filtered = _applyFilters(expenses);

          final sums = _sumByCurrency(filtered);
          final trip = _trip;

          return Column(
            children: [
              // Filters row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text(_filterCategory ?? 'All categories'),
                      selected: _filterCategory != null,
                      onSelected: (_) => _pickCategory(expenses),
                    ),
                    FilterChip(
                      label: Text(_filterCurrency ?? 'All currencies'),
                      selected: _filterCurrency != null,
                      onSelected: (_) => _pickCurrency(expenses),
                    ),
                    FilterChip(
                      label: Text(_filterRange == null
                          ? 'All dates'
                          : '${_filterRange!.start.year}-${_filterRange!.start.month.toString().padLeft(2, '0')}-${_filterRange!.start.day.toString().padLeft(2, '0')}'
                            ' → '
                            '${_filterRange!.end.year}-${_filterRange!.end.month.toString().padLeft(2, '0')}-${_filterRange!.end.day.toString().padLeft(2, '0')}'),
                      selected: _filterRange != null,
                      onSelected: (_) => _pickDateRange(),
                    ),
                    if (_filterCategory != null || _filterCurrency != null || _filterRange != null)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _filterCategory = null;
                          _filterCurrency = null;
                          _filterRange = null;
                        }),
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                      ),
                  ],
                ),
              ),

              // Quick totals card
              if (filtered.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Filtered totals', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          ...sums.entries.map((e) {
                            final c = e.key;
                            final v = e.value;
                            if (trip != null && c.toUpperCase() != trip.currency.toUpperCase()) {
                              return FutureBuilder<double>(
                                future: widget.api.convert(amount: v, from: c, to: trip.currency),
                                builder: (_, fx) => Text(
                                  fx.hasData
                                      ? '${_money(c, v)}  (≈ ${_money(trip.currency, fx.data!)})'
                                      : _money(c, v),
                                ),
                              );
                            }
                            return Text(_money(c, v));
                          }),
                          const SizedBox(height: 4),
                          if (trip != null)
                            FutureBuilder<double>(
                              future: () async {
                                double total = 0;
                                for (final e in sums.entries) {
                                  final vv = await widget.api.convert(amount: e.value, from: e.key, to: trip.currency);
                                  total += vv;
                                }
                                return total;
                              }(),
                              builder: (_, tot) => Text(
                                'Total (≈ ${trip.currency}): ${tot.hasData ? tot.data!.toStringAsFixed(2) : '…'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

              // List
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: filtered.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          Center(child: Text('No expenses match the filters')),
                        ])
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            return ListTile(
                              leading: (e.receiptPath != null && e.receiptPath!.isNotEmpty)
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.file(
                                        File(e.receiptPath!),
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const Icon(Icons.receipt_long_outlined),
                              title: Text(e.title),
                              subtitle: Text('${e.category} • ${e.paidBy} • ${e.date.toLocal().toString().split(' ').first}'),
                              onTap: () {
                                if (e.receiptPath == null || e.receiptPath!.isEmpty) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ReceiptViewerScreen(path: e.receiptPath!),
                                  ),
                                );
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_money(e.currency, e.amount)),
                                  PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'edit') {
                                        await _editExpenseDialog(e);
                                        await _refresh();
                                      } else if (v == 'delete') {
                                        await widget.api.deleteExpense(e.id);
                                        await _refresh();
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
