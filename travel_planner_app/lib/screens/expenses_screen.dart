import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../models/trip.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';

class ExpensesScreen extends StatefulWidget {
  final ApiService api;
  const ExpensesScreen({super.key, required this.api});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<List<Expense>> _future;
  Trip? _trip;

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

  Future<void> _editExpenseDialog(Expense e) async {
    final title = TextEditingController(text: e.title);
    final amount = TextEditingController(text: e.amount.toString());
    final category = TextEditingController(text: e.category);
    final paidBy = TextEditingController(text: e.paidBy);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit expense'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 8),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
          const SizedBox(height: 8),
          TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
          const SizedBox(height: 8),
          TextField(controller: paidBy, decoration: const InputDecoration(labelText: 'Paid by')),
        ]),
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
      );
      await widget.api.updateExpense(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Expense>>(
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
            final expenses = snap.data ?? [];
            if (expenses.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No expenses yet')),
                ],
              );
            }
            return ListView.separated(
              itemCount: expenses.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = expenses[i];
                return ListTile(
                  title: Text(e.title),
                  subtitle: Text('${e.category} • ${e.paidBy}'),
                  trailing: PopupMenuButton<String>(
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
                );
              },
            );
          },
        ),
      ),
    );
  }
}
