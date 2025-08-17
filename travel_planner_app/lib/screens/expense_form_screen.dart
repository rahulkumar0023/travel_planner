import 'package:flutter/material.dart';

import '../services/trip_storage_service.dart';

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
    required String currency,        // <-- add this line
  }) onSubmit;
  final String? defaultCurrency;


  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  late List<String> _participants; // safe list used across the form
  late String _expenseCurrency;
  String _category = 'Food';
  late String _paidBy;
  late Set<String> _shared;

// expense form initState fix start
  @override
  void initState() {
    super.initState();
    _participants = widget.participants.isNotEmpty
        ? List<String>.from(widget.participants)
        : <String>['You'];

    // was: _paidBy = widget.participants.first;
    // was: _shared = {...widget.participants};
    _paidBy = _participants.first;    // safe: never empty due to fallback
    _shared = {..._participants};     // default share with all shown

    final trip = TripStorageService.loadLightweight();
    _expenseCurrency = (widget.defaultCurrency ?? trip?.currency ?? 'EUR').toUpperCase();

  }
// expense form initState fix end


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
      currency: _expenseCurrency, // <-- pass the chosen currency
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ccy = widget.defaultCurrency ?? '';
    final trip = TripStorageService.loadLightweight();
    final extras = (trip?.spendCurrencies ?? const <String>[]);
    final currencyChoices = <String>{ if (trip != null) trip.currency, ...extras }.toList()..sort();
    // Do NOT mutate state here. Derive a safe selected value:
    final selectedCurrency = currencyChoices.contains(_expenseCurrency)
        ? _expenseCurrency
        : ((widget.defaultCurrency ?? trip?.currency ?? 'EUR').toUpperCase());
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
                labelText: 'Amount ${selectedCurrency}'),
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
          // paid-by items from _participants start
          DropdownButtonFormField<String>(
            value: _paidBy,
            items: _participants
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() => _paidBy = v ?? _paidBy),
            decoration: const InputDecoration(labelText: 'Paid by'),
          ),
            // paid-by items from _participants end

          // Currency field start
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedCurrency, // make sure you have: late String _expenseCurrency; in State
            decoration: const InputDecoration(labelText: 'Currency'),
            onChanged: (v) => setState(() => _expenseCurrency = (v ?? _expenseCurrency)),
            // <-- THIS is the line you replace with the items patch above
            items: currencyChoices
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
          ),
          // Currency field end

          const SizedBox(height: 8),
          const Text('Shared with'),
          const SizedBox(height: 4),
          // shared-with list from _participants start
          ..._participants.map((p) => CheckboxListTile(
            title: Text(p),
            value: _shared.contains(p),
            onChanged: (v) => setState(() {
              v == true ? _shared.add(p) : _shared.remove(p);
            }),
          )),
          // shared-with list from _participants end
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
