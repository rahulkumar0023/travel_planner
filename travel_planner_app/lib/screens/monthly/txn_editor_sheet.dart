// ===== txn_editor_sheet.dart — START =====
// Description: Modal to add monthly transactions (salary/expense).

import 'package:flutter/material.dart';
import '../../services/monthly_store.dart';

class TxnEditorSheet extends StatefulWidget {
  final String monthKey;
  final String type; // 'income' | 'expense'
  const TxnEditorSheet({super.key, required this.monthKey, required this.type});

  @override
  State<TxnEditorSheet> createState() => _TxnEditorSheetState();
}

class _TxnEditorSheetState extends State<TxnEditorSheet> {
  _CategoryChoice? _selected;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _currency = 'EUR';
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (_selected == null || amount <= 0) return;
    setState(() => _saving = true);
    await MonthlyStore.instance.addTxn(
      monthKey: widget.monthKey,
      categoryId: _selected!.categoryId,
      subCategoryId: _selected!.subCategoryId,
      amount: amount,
      currency: _currency,
      note: _noteCtrl.text.trim(),
      date: _date,
      kind: widget.type,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cats = MonthlyStore.instance
        .categoriesFor(widget.monthKey, type: widget.type, parentId: null);
    final choices = <_CategoryChoice>[];
    void addChoice(_CategoryChoice choice) {
      if (!choices.contains(choice)) {
        choices.add(choice);
      }
    }
    for (final c in cats) {
      addChoice(_CategoryChoice(
        label: c.name,
        categoryId: c.id,
        subCategoryId: null,
      ));
      final subs = MonthlyStore.instance
          .categoriesFor(widget.monthKey,
              type: widget.type, parentId: c.id);
      for (final s in subs) {
        addChoice(_CategoryChoice(
          label: '↳ ${s.name}',
          categoryId: c.id,
          subCategoryId: s.id,
        ));
      }
    }
    final dropdownValue =
        choices.contains(_selected) ? _selected : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: SingleChildScrollView(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add ${widget.type}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<_CategoryChoice>(
                value: dropdownValue,
                items: choices
                    .map((choice) => DropdownMenuItem(
                          value: choice,
                          child: Text(choice.label),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selected = v),
                decoration: const InputDecoration(
                    labelText: 'Category / Sub-category'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                decoration:
                    const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _currency,
                    items: const [
                      DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      DropdownMenuItem(value: 'INR', child: Text('INR')),
                      DropdownMenuItem(value: 'PLN', child: Text('PLN')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (v) => setState(() => _currency = v ?? 'EUR'),
                    decoration: const InputDecoration(labelText: 'Currency'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(now.year - 3),
                        lastDate: DateTime(now.year + 3),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date'),
                      child: Text(
                          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                          ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ]),
      ),
    );
  }
}

class _CategoryChoice {
  const _CategoryChoice({
    required this.label,
    required this.categoryId,
    required this.subCategoryId,
  });

  final String label;
  final String categoryId;
  final String? subCategoryId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _CategoryChoice &&
        other.categoryId == categoryId &&
        other.subCategoryId == subCategoryId;
  }

  @override
  int get hashCode => Object.hash(categoryId, subCategoryId);
}
// ===== txn_editor_sheet.dart — END =====
