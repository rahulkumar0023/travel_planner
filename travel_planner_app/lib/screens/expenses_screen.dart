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
    _future = _trip == null
        ? Future.value(<Expense>[])
        : widget.api.fetchExpenses(_trip!.id);
  }

  Future<void> _refresh() async {
    _trip = TripStorageService.loadLightweight();
    setState(() {
      _future = _trip == null
          ? Future.value(<Expense>[])
          : widget.api.fetchExpenses(_trip!.id);
    });
    await _future;
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
                  trailing: Text(
                    '${e.amount.toStringAsFixed(2)} ${_trip?.currency ?? ''}',
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
