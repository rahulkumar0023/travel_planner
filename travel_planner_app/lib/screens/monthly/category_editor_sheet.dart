// ===== category_editor_sheet.dart — START =====
// Description: Modal to create category or sub-category for a given month.

import 'package:flutter/material.dart';
import '../../services/monthly_store.dart';
import '../../models/monthly_category.dart';

class CategoryEditorSheet extends StatefulWidget {
  final String monthKey;
  final String type; // 'income' | 'expense'
  final MonthlyCategory? parent; // if provided -> creating a sub-category

  const CategoryEditorSheet({
    super.key,
    required this.monthKey,
    required this.type,
    this.parent,
  });

  @override
  State<CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<CategoryEditorSheet> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await MonthlyStore.instance.addCategory(
      name: _ctrl.text,
      monthKey: widget.monthKey,
      type: widget.type,
      parentId: widget.parent?.id,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.parent == null
        ? 'New ${widget.type} category'
        : 'New sub-category of "${widget.parent!.name}"';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
              onSubmitted: (_) => _save(),
            ),
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
    );
  }
}
// ===== category_editor_sheet.dart — END =====
