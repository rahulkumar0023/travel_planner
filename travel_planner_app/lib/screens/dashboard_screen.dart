import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../models/expense.dart';

class DashboardScreen extends StatelessWidget {
  DashboardScreen({super.key});

  final Trip trip = Trip(
    id: 't1',
    name: 'Italy Trip',
    startDate: DateTime(2025, 9, 1),
    endDate: DateTime(2025, 9, 10),
    initialBudget: 1500.0,
    currency: 'EUR',
  );

  final List<Expense> expenses = [
    Expense(id: 'e1', tripId: 't1', title: 'Flight', amount: 300, category: 'Transport', date: DateTime.now()),
    Expense(id: 'e2', tripId: 't1', title: 'Pizza Dinner', amount: 40, category: 'Food', date: DateTime.now()),
  ];

  @override
  Widget build(BuildContext context) {
    double totalSpent = expenses.fold(0, (sum, e) => sum + e.amount);
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
                itemCount: expenses.length,
                itemBuilder: (ctx, i) {
                  final e = expenses[i];
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
    );
  }
}
