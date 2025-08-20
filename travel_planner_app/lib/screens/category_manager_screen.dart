import 'package:flutter/material.dart';
import '../models/category.dart';
import '../services/category_store.dart';

class CategoryManagerScreen extends StatefulWidget {
  const CategoryManagerScreen({super.key});
  @override
  State<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends State<CategoryManagerScreen> {
  List<CategoryItem> _all = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    final all = await CategoryStore.all();
    if (!mounted) return;
    setState(() { _all = all; _busy = false; });
  }

  Future<void> _addRoot(CategoryType type) async {
    final name = await _nameDialog('New ${type == CategoryType.income ? 'Income' : 'Expense'} category');
    if (name == null) return;
    final id = '${type == CategoryType.income ? 'inc' : 'exp'}-${name.toLowerCase().replaceAll(' ', '-')}-${DateTime.now().millisecondsSinceEpoch}';
    await CategoryStore.upsert(CategoryItem(id: id, name: name, type: type, colorIndex: 0));
    await _reload();
  }

  Future<void> _addSub(String parentId) async {
    final name = await _nameDialog('New subcategory');
    if (name == null) return;
    final parent = _all.firstWhere((c) => c.id == parentId);
    final id = '${parent.id}-${name.toLowerCase().replaceAll(' ', '-')}-${DateTime.now().millisecondsSinceEpoch}';
    await CategoryStore.upsert(CategoryItem(id: id, name: name, type: parent.type, parentId: parentId, colorIndex: parent.colorIndex));
    await _reload();
  }

  Future<void> _delete(String id) async {
    await CategoryStore.delete(id);
    await _reload();
  }

  Future<String?> _nameDialog(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: ()=>Navigator.pop(ctx, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final incomeRoots = _all.where((c) => c.type == CategoryType.income && c.parentId == null).toList();
    final expenseRoots = _all.where((c) => c.type == CategoryType.expense && c.parentId == null).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Categories')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _Section(
                  title: 'Income',
                  roots: incomeRoots,
                  all: _all,
                  onAddRoot: () => _addRoot(CategoryType.income),
                  onAddSub: _addSub,
                  onDelete: _delete,
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Expenses',
                  roots: expenseRoots,
                  all: _all,
                  onAddRoot: () => _addRoot(CategoryType.expense),
                  onAddSub: _addSub,
                  onDelete: _delete,
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<CategoryItem> roots;
  final List<CategoryItem> all;
  final VoidCallback onAddRoot;
  final void Function(String parentId) onAddSub;
  final void Function(String id) onDelete;

  const _Section({
    required this.title,
    required this.roots,
    required this.all,
    required this.onAddRoot,
    required this.onAddSub,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          trailing: FilledButton.icon(
            onPressed: onAddRoot,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ),
        for (final r in roots) ...[
          ListTile(
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'add_sub') onAddSub(r.id);
                if (v == 'delete') onDelete(r.id);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add_sub', child: Text('Add subcategory')),
                PopupMenuItem(value: 'delete', child: Text('Delete category')),
              ],
            ),
          ),
          ...all.where((c) => c.parentId == r.id).map((s) => Padding(
                padding: const EdgeInsets.only(left: 24),
                child: ListTile(
                  dense: true,
                  title: Text('• ${s.name}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => onDelete(s.id),
                  ),
                ),
              )),
          const Divider(height: 1),
        ],
      ],
    );
  }
}
