import 'package:flutter/material.dart';
import 'expense_form_screen.dart';

class ExpenseFormSheet extends StatelessWidget {
  final void Function(
    String title,
    double amount,
    String category,
    String paidBy,
    List<String> sharedWith,
  ) onAddExpense;
  const ExpenseFormSheet({super.key, required this.onAddExpense});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Add expense',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge!
                  .copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ExpenseFormFields(onSubmit: (t, a, c, p, s) {
              onAddExpense(t, a, c, p, s);
              Navigator.pop(context, true);
            }),
          ],
        ),
      ),
    );
  }
}

