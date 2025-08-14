import 'package:flutter/material.dart';

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({
    super.key,
    required this.participants,
    required this.onSubmit,
    this.defaultCurrency,
  });

  final List<String> participants;
  final void Function({
    required String title,
    required double amount,
    required String category,
    required String paidBy,
    required List<String> sharedWith,
  }) onSubmit;
  final String? defaultCurrency;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _category = 'Food';
  late String _paidBy;
  late Set<String> _shared;

  @override
  void initState() {
    super.initState();
    _paidBy = widget.participants.first;
    _shared = {...widget.participants};
  }

  void _save() {
    final title = _title.text.trim();
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (title.isEmpty || amount <= 0 || _shared.isEmpty) return;
    widget.onSubmit(
      title: title,
      amount: amount,
      category: _category,
      paidBy: _paidBy,
      sharedWith: _shared.toList(),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ccy = widget.defaultCurrency ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Add Expense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Title', hintText: 'e.g. Dinner'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            decoration: InputDecoration(
                labelText: 'Amount ${ccy.isEmpty ? '' : '($ccy)'}'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _category,
            items: const ['Food', 'Transport', 'Lodging', 'Activity', 'Other']
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? 'Food'),
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _paidBy,
            items: widget.participants
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() => _paidBy = v ?? _paidBy),
            decoration: const InputDecoration(labelText: 'Paid by'),
          ),
          const SizedBox(height: 8),
          const Text('Shared with'),
          const SizedBox(height: 4),
          ...widget.participants.map((p) => CheckboxListTile(
                title: Text(p),
                value: _shared.contains(p),
                onChanged: (v) => setState(() {
                  v == true ? _shared.add(p) : _shared.remove(p);
                }),
              )),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
