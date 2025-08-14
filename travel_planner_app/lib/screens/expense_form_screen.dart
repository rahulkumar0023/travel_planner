import 'package:flutter/material.dart';

class ExpenseFormFields extends StatefulWidget {
  final void Function(
    String title,
    double amount,
    String category,
    String paidBy,
    List<String> sharedWith,
  ) onSubmit;
  const ExpenseFormFields({super.key, required this.onSubmit});

  @override
  State<ExpenseFormFields> createState() => _ExpenseFormFieldsState();
}

class _ExpenseFormFieldsState extends State<ExpenseFormFields> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _category = 'Food';
  String _paidBy = 'Me';
  final _shared = <String>{'Me'};

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixIcon: Icon(Icons.euro_outlined),
            ),
            validator: (v) => (double.tryParse(v ?? '') == null)
                ? 'Enter a valid number'
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _category,
            items: const ['Food', 'Transport', 'Lodging', 'Activity', 'Other']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? 'Food'),
            decoration: const InputDecoration(
              labelText: 'Category',
              prefixIcon: Icon(Icons.category_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _paidBy,
            items: _shared
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _paidBy = v ?? 'Me'),
            decoration: const InputDecoration(
              labelText: 'Paid by',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children:
                  _shared.map((p) => Chip(label: Text(p))).toList(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              if (_form.currentState!.validate()) {
                widget.onSubmit(
                  _title.text.trim(),
                  double.parse(_amount.text.trim()),
                  _category,
                  _paidBy,
                  _shared.toList(),
                );
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

