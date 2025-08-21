import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/expense.dart';
import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import '../services/fx_service.dart';

class ExpensesScreen extends StatefulWidget {
  final ApiService api;

  const ExpensesScreen({super.key, required this.api});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  Trip? _trip;
  Future<List<Expense>> _future = Future.value(<Expense>[]);

  // --- Filters state ---
  String? _fCategory;
  String? _fCurrency;
  DateTimeRange? _fRange;

  // cache last-loaded list to filter on it without refetch
  List<Expense> _all = [];

  // convenience: detect “any filter active”
  bool get _hasFilters => _fCategory != null || _fCurrency != null || _fRange != null;

  // quick access to active trip currency (safe)
  String get _tripCcy => _trip?.currency.toUpperCase() ?? 'EUR';

  @override
  void initState() {
    super.initState();
    _trip = TripStorageService.loadLightweight();
    () async {
      try {
        await widget.api.waitForToken();
        if (!mounted) return;
        if (_trip == null) {
          setState(() {
            _future = Future.value(<Expense>[]);
          });
        } else {
          final fut = widget.api.fetchExpenses(_trip!.id);
          setState(() {
            _future = fut;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _future = Future.error(e);
          });
        }
      }
    }();
  }

  // refresh by re-fetching
  Future<void> _refresh() async {
    if (_trip == null) return;
    final list = await widget.api.fetchExpenses(_trip!.id);
    setState(() {
      _future = Future.value(list);
    });
  }

  List<Expense> _applyFilters(List<Expense> list) {
    Iterable<Expense> it = list;

    if (_fCategory != null) {
      it = it.where((e) => e.category.toLowerCase() == _fCategory!.toLowerCase());
    }
    if (_fCurrency != null) {
      it = it.where((e) => (e.currency.isEmpty ? _tripCcy : e.currency.toUpperCase()) == _fCurrency!.toUpperCase());
    }
    if (_fRange != null) {
      final start = DateTime(_fRange!.start.year, _fRange!.start.month, _fRange!.start.day);
      final end = DateTime(_fRange!.end.year, _fRange!.end.month, _fRange!.end.day, 23, 59, 59);
      it = it.where((e) => e.date.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
                           e.date.isBefore(end.add(const Duration(milliseconds: 1))));
    }
    final res = it.toList()..sort((a, b) => b.date.compareTo(a.date));
    return res;
  }

  Set<String> _categoriesOf(List<Expense> list) =>
      list.map((e) => e.category).where((s) => s.trim().isNotEmpty).toSet();

  Set<String> _currenciesOf(List<Expense> list) =>
      list.map((e) => (e.currency.isEmpty ? _tripCcy : e.currency.toUpperCase())).toSet();

  // --- Currency bucket + conversion helpers (filtered totals) ---

  Map<String, double> _bucketByCcy(List<Expense> rows, String base) {
    final m = <String, double>{};
    for (final e in rows) {
      final c = (e.currency.isEmpty ? base : e.currency).toUpperCase();
      m[c] = (m[c] ?? 0) + e.amount;
    }
    return m;
  }

  /// Returns raw bucket sums, ≈ bucket sums in base, and grand total in base.
  Future<({
    Map<String, double> raw,
    Map<String, double> approx,
    double totalBase,
  })> _computeFilteredTotals(List<Expense> rows) async {
    final base = (_trip?.currency ?? 'EUR').toUpperCase();
    final raw = _bucketByCcy(rows, base);

    final approx = <String, double>{};
    double total = 0.0;

    Map<String, double>? rates;
    try {
      rates = await FxService.loadRates(base);
    } catch (_) {}

    for (final entry in raw.entries) {
      final c = entry.key;
      final amt = entry.value;
      double conv;

      if (c == base) {
        conv = amt;
      } else {
        // Prefer server convert; fall back to local FX; last resort: identity.
        try {
          conv = await widget.api.convert(amount: amt, from: c, to: base);
        } catch (_) {
          conv = (rates != null)
              ? FxService.convert(amount: amt, from: c, to: base, ratesForBaseTo: rates)
              : amt;
        }
      }

      approx[c] = conv;
      total += conv;
    }

    return (raw: raw, approx: approx, totalBase: total);
  }

  Future<double> _convertToTrip(String from, double amount) async {
    if (from.toUpperCase() == _tripCcy) return amount;
    try {
      return await widget.api.convert(amount: amount, from: from.toUpperCase(), to: _tripCcy);
    } catch (_) {
      return amount; // fallback
    }
  }

  Future<void> _exportCsv(List<Expense> list) async {
    if (_trip == null || list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to export')));
      return;
    }

    bool convert = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export CSV'),
        content: StatefulBuilder(
          builder: (ctx, setS) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Convert to trip currency'),
              const SizedBox(width: 12),
              Switch(value: convert, onChanged: (v) => setS(() => convert = v)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Export')),
        ],
      ),
    );
    if (ok != true) return;

    final sb = StringBuffer();
    // header
    sb.writeln([
      'Date',
      'Title',
      'Category',
      'PaidBy',
      'Currency',
      'Amount',
      if (convert) 'Amount_${_tripCcy}',
      'SharedWith'
    ].join(','));

    for (final e in list) {
      final ccy = (e.currency.isEmpty ? _tripCcy : e.currency.toUpperCase());
      final amt = e.amount;
      final amtTrip = convert ? await _convertToTrip(ccy, amt) : null;

      // simple CSV escaping
      String q(String s) => '"${s.replaceAll('"', '""')}"';

      sb.writeln([
        q(e.date.toIso8601String().split('T').first),
        q(e.title),
        q(e.category),
        q(e.paidBy),
        q(ccy),
        amt.toStringAsFixed(2),
        if (convert) (amtTrip ?? amt).toStringAsFixed(2),
        q(e.sharedWith.join('; '))
      ].join(','));
    }

    final dir = await getTemporaryDirectory();
    final safeName = _trip!.name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    final file = File('${dir.path}/trip_${safeName}_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(sb.toString());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: 'trip_${safeName}.csv')],
      text: 'Trip "${_trip!.name}" — expenses export',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.ios_share),
            onPressed: () {
              final list = _applyFilters(_all);
              _exportCsv(list);
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
            return Center(child: Text('Failed to load expenses:\n${snap.error}'));
          }

          final loaded = snap.data ?? <Expense>[];
          _all = loaded;

          // apply filters
          final filtered = _applyFilters(_all);

          // --- FILTER BAR ---
          final cats = _categoriesOf(_all).toList()..sort();
          final ccys = _currenciesOf(_all).toList()..sort();

          Widget chipsWrap({
            required String label,
            required List<String> values,
            required String? selected,
            required void Function(String?) onSelect,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: -6,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: selected == null,
                      onSelected: (_) => setState(() => onSelect(null)),
                    ),
                    for (final v in values)
                      ChoiceChip(
                        label: Text(v),
                        selected: selected == v,
                        onSelected: (_) => setState(() => onSelect(selected == v ? null : v)),
                      ),
                  ],
                ),
              ],
            );
          }

          // date button label
          String _dateLabel() {
            if (_fRange == null) return 'Any date';
            final s = _fRange!.start;
            final e = _fRange!.end;
            String two(int x) => x.toString().padLeft(2, '0');
            return '${s.year}-${two(s.month)}-${two(s.day)} → ${e.year}-${two(e.month)}-${two(e.day)}';
          }

          final filtersAndTotals = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filters
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      chipsWrap(
                        label: 'Category',
                        values: cats,
                        selected: _fCategory,
                        onSelect: (v) => _fCategory = v,
                      ),
                      const SizedBox(height: 12),
                      chipsWrap(
                        label: 'Currency',
                        values: ccys,
                        selected: _fCurrency,
                        onSelect: (v) => _fCurrency = v,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.date_range),
                            label: Text(_dateLabel()),
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(now.year - 5),
                                lastDate: DateTime(now.year + 5),
                                initialDateRange: _fRange,
                              );
                              if (picked != null) setState(() => _fRange = picked);
                            },
                          ),
                          const Spacer(),
                          if (_hasFilters)
                            TextButton.icon(
                              icon: const Icon(Icons.clear),
                              label: const Text('Clear'),
                              onPressed: () => setState(() {
                                _fCategory = null;
                                _fCurrency = null;
                                _fRange = null;
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Filtered totals
              if (filtered.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FutureBuilder<({
                      Map<String, double> raw,
                      Map<String, double> approx,
                      double totalBase,
                    })>(
                      future: _computeFilteredTotals(filtered),
                      builder: (ctx, snap) {
                        if (!snap.hasData) {
                          return const SizedBox(height: 8);
                        }
                        final data = snap.data!;
                        final base = (_trip?.currency ?? 'EUR').toUpperCase();
                        final codes = data.raw.keys.toList()..sort();

                        final rows = <Widget>[
                          Text('Filtered totals', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                        ];

                        for (final c in codes) {
                          final raw = data.raw[c] ?? 0.0;
                          if (c == base) {
                            rows.add(Text('${raw.toStringAsFixed(2)} $c'));
                          } else {
                            final approx = data.approx[c] ?? raw;
                            rows.add(Text('${raw.toStringAsFixed(2)} $c (≈ ${approx.toStringAsFixed(2)} $base)'));
                          }
                        }

                        rows.add(const SizedBox(height: 6));
                        rows.add(Text('≈ ${data.totalBase.toStringAsFixed(2)} $base',
                            style: Theme.of(context).textTheme.bodySmall));

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: rows,
                        );
                      },
                    ),
                  ),
                ),
            ],
          );

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 1 + filtered.length,
              separatorBuilder: (_, i) => (i == 0) ? const SizedBox(height: 12) : const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i == 0) return filtersAndTotals; // top block
                final e = filtered[i - 1];
                return ListTile(
                  title: Text(e.title),
                  subtitle: Text('${e.category} • ${e.paidBy} • ${e.date.toLocal().toString().split(' ').first}'),
                  trailing: Text('${e.amount.toStringAsFixed(2)} ${e.currency.isEmpty ? _tripCcy : e.currency}'),
                  onTap: () {}, // (optional) open detail/edit
                );
              },
            ),
          );
        },
      ),
    );
  }
}

