import 'package:flutter/material.dart';
import 'dart:io';
// add near the top
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/local_budget_store.dart';
import '../models/budget.dart';
import '../services/trip_storage_service.dart';
import '../models/currencies.dart';
// 👇 NEW: remember last-used currency per trip
import '../services/last_used_store.dart';
// 👇 NEW: categories store + model
import '../models/category.dart';
import '../services/category_store.dart';

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
    String? receiptPath,                 // NEW
  }) onSubmit;
  final String? defaultCurrency;


  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {

// 👇 NEW: dropdown data + selection
  String? _receiptPath;
  final _picker = ImagePicker();
  late List<String> _currencyChoices;
  late String _expenseCurrency;
  final _title = TextEditingController();
  final _amount = TextEditingController();
  late List<String> _participants; // safe list used across the form
  late String _paidBy;
  late Set<String> _shared;
  // 👇 NEW: category state
  CategoryType _type = CategoryType.expense; // we tag expenses for now
  List<CategoryItem> _roots = [];
  List<CategoryItem> _subs = [];
  String? _selectedRootId;
  String? _selectedSubId;

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

    // 👇 NEW: load categories for EXPENSE by default
    () async {
      final roots = await CategoryStore.roots(CategoryType.expense);
      if (!mounted) return;
      setState(() {
        _type = CategoryType.expense;
        _roots = roots;
        _selectedRootId = roots.isNotEmpty ? roots.first.id : null;
      });
      if (_selectedRootId != null) {
        final subs = await CategoryStore.subsOf(_selectedRootId!);
        if (!mounted) return;
        setState(() => _subs = subs);
      }
    }();
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

  // 👇 NEW: when root changes, refresh subs
  Future<void> _onRootChanged(String? id) async {
    setState(() {
      _selectedRootId = id;
      _subs = [];
      _selectedSubId = null;
    });
    if (id != null) {
      final subs = await CategoryStore.subsOf(id);
      if (!mounted) return;
      setState(() => _subs = subs);
    }
  }


  Future<void> _pickReceipt(ImageSource src) async {
    final x = await _picker.pickImage(
      source: src,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (x == null) return;

    // Copy into app documents for persistence
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'receipt_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = File('${dir.path}/$fileName');
    await File(x.path).copy(dest.path);

    if (!mounted) return;
    setState(() => _receiptPath = dest.path);
  }

  void _removeReceipt() => setState(() => _receiptPath = null);


  void _save() {
    final title = _title.text.trim();
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (title.isEmpty || amount <= 0 || _shared.isEmpty) return;
    // 👇 NEW: compose `Parent > Sub` (or just Parent)
    final rootName = _roots.firstWhere(
      (c) => c.id == _selectedRootId,
      orElse: () => CategoryItem(id: 'misc', name: 'Misc', type: CategoryType.expense),
    ).name;
    final subName = (_selectedSubId == null)
        ? null
        : _subs.firstWhere((s) => s.id == _selectedSubId, orElse: () => _subs.first).name;

    widget.onSubmit(
      title: title,
      amount: amount,
      category: subName == null ? rootName : '$rootName > $subName', // 👈 NEW
      paidBy: _paidBy,
      sharedWith: _shared.toList(),
      currency: _expenseCurrency, // <-- pass the chosen currency
      receiptPath: _receiptPath,               // NEW
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
          // Category pickers start
          DropdownButtonFormField<String>(
            value: _selectedRootId,
            decoration: const InputDecoration(labelText: 'Category'),
            onChanged: (v) => _onRootChanged(v),
            items: _roots
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedSubId,
            decoration: const InputDecoration(labelText: 'Subcategory (optional)'),
            onChanged: (v) => setState(() => _selectedSubId = v),
            items: [
              const DropdownMenuItem(value: null, child: Text('— None —')),
              ..._subs.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
            ],
          ),
          // Category pickers end
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

          const SizedBox(height: 12),
          Text('Receipt', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
                onPressed: () => _pickReceipt(ImageSource.camera),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
                onPressed: () => _pickReceipt(ImageSource.gallery),
              ),
              const SizedBox(width: 8),
              if (_receiptPath != null)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: _removeReceipt,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_receiptPath != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(_receiptPath!),
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
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
