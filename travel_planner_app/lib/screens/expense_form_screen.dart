import 'package:flutter/material.dart';

class ExpenseFormScreen extends StatefulWidget {
  final void Function(
    String title,
    double amount,
    String category,
    String paidBy,
    List<String> sharedWith,
  )
  onAddExpense;

  const ExpenseFormScreen({super.key, required this.onAddExpense});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  List<String> participants = ['Rahul', 'Nammu'];
  String paidBy = 'Rahul';
  List<String> sharedWith = ['Rahul', 'Nammu'];
  String selectedCategory = 'Food';

  void _submitForm() {
    final title = _titleController.text;
    final amount = double.tryParse(_amountController.text) ?? 0;

    if (title.isEmpty || amount <= 0) return;

    widget.onAddExpense(title, amount, selectedCategory, paidBy, sharedWith);

    Navigator.of(context).pop(); // go back to dashboard
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add Expense')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
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
              DropdownButtonFormField<String>(
                value: selectedCategory,
                items: ['Food', 'Transport', 'Lodging', 'Other']
                    .map(
                      (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => selectedCategory = val);
                },
                decoration: InputDecoration(labelText: 'Category'),
              ),
              DropdownButtonFormField<String>(
                value: paidBy,
                items: participants
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (val) => setState(() => paidBy = val!),
                decoration: InputDecoration(labelText: 'Paid By'),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: participants.map((person) {
                  return CheckboxListTile(
                    title: Text(person),
                    value: sharedWith.contains(person),
                    onChanged: (val) {
                      setState(() {
                        val!
                            ? sharedWith.add(person)
                            : sharedWith.remove(person);
                      });
                    },
                  );
                }).toList(),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submitForm,
                child: Text('Save Expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
