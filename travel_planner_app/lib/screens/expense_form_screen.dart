import 'package:flutter/material.dart';
// add near the top
import '../services/local_budget_store.dart';
import '../models/budget.dart';
import '../services/trip_storage_service.dart';
import '../models/currencies.dart';
// 👇 NEW: remember last-used currency per trip
import '../services/last_used_store.dart';

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({
    super.key,
    required this.participants,
    required this.onSubmit,
    this.defaultCurrency,
    this.availableCurrencies, // 👈 NEW
  });

  final List<String> participants;
  final List<String>? availableCurrencies; // 👈 NEW
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

// 👇 NEW: dropdown data + selection
  late List<String> _currencyChoices;
  late String _expenseCurrency;
  final _title = TextEditingController();
  final _amount = TextEditingController();
  late List<String> _participants; // safe list used across the form
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

// decide initial (trip/default)
    final trip = TripStorageService.loadLightweight();
    final initial = (widget.defaultCurrency ?? trip?.currency ?? 'EUR').toUpperCase();

// shortlist to pin at top (trip base + any extras you keep on the Trip)
    final pinned = <String>{
      initial,
      ...((trip?.spendCurrencies ?? const <String>[]).map((e) => e.toUpperCase())),
    };

// build choices => pinned first, then everything else from kCurrencyCodes
    _currencyChoices = [
      ...pinned,
      ...kCurrencyCodes.where((c) => !pinned.contains(c.toUpperCase())),
    ];

    _expenseCurrency = initial;
    _loadSavedCurrency(); // 👈 NEW: apply last-used if available
  }
// expense form initState fix end

// 👇 NEW: load last-used currency for this trip
// _loadSavedCurrency method start
  Future<void> _loadSavedCurrency() async {
    final trip = TripStorageService.loadLightweight();
    final saved = await LastUsedStore.getExpenseCurrencyForTrip(trip?.id ?? '');
    if (!mounted) return;
    if (saved != null && _currencyChoices.contains(saved)) {
      setState(() => _expenseCurrency = saved);
    }
  }
// _loadSavedCurrency method end


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
            decoration: InputDecoration(labelText: 'Amount (${_expenseCurrency})'),
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
            value: _expenseCurrency,
            decoration: const InputDecoration(labelText: 'Currency'),
            // 👇 NEW: persist the choice per trip
            // currency onChanged start
            onChanged: (v) async {
              final newCcy = v ?? _expenseCurrency;
              if (!mounted) return;
              setState(() => _expenseCurrency = newCcy);

              final trip = TripStorageService.loadLightweight();
              if (trip != null) {
                await LastUsedStore.setExpenseCurrencyForTrip(trip.id, newCcy);
              }
            },
            // currency onChanged end
            items: _currencyChoices
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
