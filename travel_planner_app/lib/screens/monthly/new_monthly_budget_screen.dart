import 'package:flutter/material.dart';

import '../../models/budget.dart';
import '../../services/api_service.dart';
import '../../services/trip_storage_service.dart';
import '../sign_in_screen.dart';

class NewMonthlyBudgetScreen extends StatefulWidget {
  const NewMonthlyBudgetScreen({
    super.key,
    required this.api,
    required this.initialMonth,
  });

  final ApiService api;
  final DateTime initialMonth;

  @override
  State<NewMonthlyBudgetScreen> createState() => _NewMonthlyBudgetScreenState();
}

class _NewMonthlyBudgetScreenState extends State<NewMonthlyBudgetScreen> {
  late DateTime _startDate;
  late DateTime _endDate;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _currencyCtrl =
      TextEditingController(text: TripStorageService.getHomeCurrency());
  final TextEditingController _initialBalanceCtrl = TextEditingController();
  bool _allowOutside = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
    _endDate = DateTime(widget.initialMonth.year, widget.initialMonth.month + 1, 0);
    _nameCtrl.text = '${_monthName(widget.initialMonth.month)} ${widget.initialMonth.year}';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _currencyCtrl.dispose();
    _initialBalanceCtrl.dispose();
    super.dispose();
  }

  String _monthName(int month) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 3),
      lastDate: DateTime(current.year + 3),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = DateTime(picked.year, picked.month + 1, 0);
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a positive amount.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.createBudget(
        kind: BudgetKind.monthly,
        currency: _currencyCtrl.text.trim().toUpperCase(),
        amount: amount,
        year: _startDate.year,
        month: _startDate.month,
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('Unauthorized') || msg.contains('401')) {
        final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => SignInScreen(api: widget.api)),
        );
        if (ok == true) {
          _save();
        } else {
          setState(() => _saving = false);
        }
      } else {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = const SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Monthly Budget'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Planning', style: Theme.of(context).textTheme.titleMedium),
          spacing,
          Row(
            children: [
              Expanded(
                child: _DateTile(
                  label: 'Start date',
                  value: _startDate,
                  onTap: () => _pickDate(start: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateTile(
                  label: 'End date',
                  value: _endDate,
                  onTap: () => _pickDate(start: false),
                ),
              ),
            ],
          ),
          spacing,
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Budget name'),
          ),
          spacing,
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Budgeted amount'),
          ),
          spacing,
          TextField(
            controller: _currencyCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Currency'),
          ),
          spacing,
          TextField(
            controller: _initialBalanceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Initial balance (optional)'),
          ),
          spacing,
          SwitchListTile(
            title: const Text('Allow transactions outside the budget period'),
            value: _allowOutside,
            onChanged: (v) => setState(() => _allowOutside = v),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Create monthly budget'),
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(
              '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
