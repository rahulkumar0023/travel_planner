import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../models/expense.dart';
import 'expense_form_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Trip trip = Trip(
    id: 't1',
    name: 'Italy Trip',
    startDate: DateTime(2025, 9, 1),
    endDate: DateTime(2025, 9, 10),
    initialBudget: 1500.0,
    currency: 'EUR',
  );

  final List<Expense> _expenses = [];

  void _addExpense(String title, double amount, String category) {
    setState(() {
      _expenses.add(
        Expense(
          id: DateTime.now().toString(),
          tripId: 't1',
          title: title,
          amount: amount,
          category: category,
          date: DateTime.now(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    double totalSpent = _expenses.fold(0, (sum, e) => sum + e.amount);
    double remaining = trip.initialBudget - totalSpent;

    return Scaffold(
      appBar: AppBar(title: const Text('Trip Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Trip: ${trip.name}', style: const TextStyle(fontSize: 20)),
            Text('Budget: ${trip.initialBudget} ${trip.currency}'),
            Text('Spent: $totalSpent'),
            Text('Remaining: $remaining'),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _expenses.length,
                itemBuilder: (ctx, i) {
                  final e = _expenses[i];
                  return ListTile(
                    title: Text(e.title),
                    subtitle: Text('${e.category} • ${e.amount} ${trip.currency}'),
                    trailing: Text(e.date.toLocal().toString().split(' ')[0]),
                  );
                },
              ),
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExpenseFormScreen(onAddExpense: _addExpense),
            ),
          );
        },
      ),
    );
  }
}
