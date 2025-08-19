import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/expense.dart';
import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import '../models/budget.dart'; // for BudgetKind
import 'receipt_viewer_screen.dart';
import '../services/fx_service.dart';
import '../services/outbox_service.dart';

class ExpensesScreen extends StatefulWidget {
  final ApiService api;
  const ExpensesScreen({super.key, required this.api});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<List<Expense>> _future;
  Trip? _trip;
  List<Expense> _expenses = [];

  // Filters
  String? _fCategory;
  String? _fCurrency;
  DateTimeRange? _fRange;

  // Cache last filters per trip
  String get _filterKey {
    final id = _trip?.id ?? 'no_trip';
    return 'filters_$id';
  }

  List<Expense> _applyFilters(List<Expense> list) {
    return list.where((e) {
      if (_fCategory != null && _fCategory!.isNotEmpty && e.category != _fCategory) return false;
      if (_fCurrency != null && _fCurrency!.isNotEmpty && (e.currency.toUpperCase() != _fCurrency)) return false;
      if (_fRange != null) {
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        if (d.isBefore(_fRange!.start) || d.isAfter(_fRange!.end)) return false;
      }
      return true;
    }).toList();
  }

  Map<String, double> _sumPerCurrency(List<Expense> list) {
    final m = <String, double>{};
    for (final e in list) {
      final c = e.currency.toUpperCase();
      m[c] = (m[c] ?? 0) + e.amount;
    }
    return m;
  }

  Future<double> _filteredTotalInTripCcy(List<Expense> list) async {
    final t = _trip;
    if (t == null || list.isEmpty) return 0.0;
    final rates = await FxService.loadRates(t.currency);
    var sum = 0.0;
    for (final e in list) {
      sum += FxService.convert(
        amount: e.amount,
        from: e.currency.toUpperCase(),
        to: t.currency.toUpperCase(),
        ratesForBaseTo: rates,
      );
    }
    return sum;
  }

  String _money(String ccy, num v) => '${v.toStringAsFixed(2)} $ccy';

  Future<void> _openFilters() async {
    final categories = _expenses.map((e) => e.category).toSet().toList()..sort();
    final currencies = _expenses.map((e) => e.currency.toUpperCase()).toSet().toList()..sort();

    String? selCat = _fCategory;
    String? selCcy = _fCurrency;
    DateTimeRange? selRange = _fRange;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      selCat = null;
                      selCcy = null;
                      selRange = null;
                      Navigator.pop(ctx);
                      setState(() {
                        _fCategory = null;
                        _fCurrency = null;
                        _fRange = null;
                      });
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selCat,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (v) => selCat = v,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selCcy,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (v) => selCcy = v,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        selRange == null
                            ? 'Date range'
                            : '${selRange!.start.toString().split(' ').first} → ${selRange!.end.toString().split(' ').first}',
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: ctx,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 5),
                          initialDateRange: selRange,
                        );
                        if (picked != null) {
                          selRange = DateTimeRange(
                            start: DateTime(picked.start.year, picked.start.month, picked.start.day),
                            end: DateTime(picked.end.year, picked.end.month, picked.end.day),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _fCategory = selCat;
                    _fCurrency = selCcy;
                    _fRange = selRange;
                  });
                },
                child: const Text('Apply'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

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
      try {
        await widget.api.updateExpense(updated);
      } catch (_) {
        await OutboxService.enqueue(OutboxOp(
          method: 'PUT',
          path: '/expenses/${e.id}',
          jsonBody: jsonEncode(updated.toJson()),
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved offline — will sync automatically')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: 'Filters',
            icon: const Icon(Icons.filter_list),
            onPressed: _openFilters,
          ),
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
          _expenses = expenses;
          final filtered = _applyFilters(expenses);
          final perCcy = _sumPerCurrency(filtered);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
              if (_fCategory != null || _fCurrency != null || _fRange != null) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_fCategory != null) Chip(label: Text('Cat: $_fCategory')),
                    if (_fCurrency != null) Chip(label: Text('Ccy: $_fCurrency')),
                    if (_fRange != null)
                      Chip(label: Text('${_fRange!.start.toString().split(" ").first} → ${_fRange!.end.toString().split(" ").first}')),
                    ActionChip(
                      avatar: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear'),
                      onPressed: () => setState(() { _fCategory = null; _fCurrency = null; _fRange = null; }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              FutureBuilder<double>(
                future: _filteredTotalInTripCcy(filtered),
                builder: (_, total) {
                  final t = _trip;
                  final lines = <Widget>[
                    Text('Filtered totals', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    ...perCcy.entries.map((e) => Text('${e.value.toStringAsFixed(2)} ${e.key}')),
                  ];
                  if (t != null && total.hasData) {
                    lines.add(const SizedBox(height: 6));
                    lines.add(Text('≈ ${total.data!.toStringAsFixed(2)} ${t.currency}',
                        style: Theme.of(context).textTheme.bodyMedium));
                  }
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              if (filtered.isEmpty)
                const Center(child: Padding(
                  padding: EdgeInsets.all(24), child: Text('No expenses match filters'),
                ))
              else
                ...filtered.map((e) => ListTile(
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
                            try {
                              await widget.api.deleteExpense(e.id);
                            } catch (_) {
                              await OutboxService.enqueue(OutboxOp(
                                method: 'DELETE',
                                path: '/expenses/${e.id}',
                              ));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Queued deletion — will sync when online')),
                                );
                              }
                            }
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
                  onTap: () {
                    if (e.receiptPath == null || e.receiptPath!.isEmpty) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReceiptViewerScreen(path: e.receiptPath!),
                      ),
                    );
                  },
                )),
              const SizedBox(height: 80),
            ],
          ),
          );
        },
      ),
    );
  }
}
