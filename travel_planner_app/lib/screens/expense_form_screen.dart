import 'package:flutter/material.dart';

class ExpenseFormScreen extends StatefulWidget {
  final Function(String, double, String) onAddExpense;

  const ExpenseFormScreen({super.key, required this.onAddExpense});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedCategory = 'Food';

  void _submitForm() {
    final title = _titleController.text;
    final amount = double.tryParse(_amountController.text) ?? 0;

    if (title.isEmpty || amount <= 0) return;

    widget.onAddExpense(title, amount, _selectedCategory);
    Navigator.of(context).pop(); // go back to dashboard
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add Expense')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: 'Expense Title'),
            ),
            TextField(
              controller: _amountController,
              decoration: InputDecoration(labelText: 'Amount (€)'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            DropdownButton<String>(
              value: _selectedCategory,
              items: ['Food', 'Transport', 'Lodging', 'Other']
                  .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
            ),
            SizedBox(height: 20),
            ElevatedButton(onPressed: _submitForm, child: Text('Save Expense')),
          ],
        ),
      ),
    );
  }
}
