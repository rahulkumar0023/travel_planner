import 'package:flutter/material.dart';
import '../services/participants_service.dart';

class ParticipantsScreen extends StatefulWidget {
  final String tripId;
  const ParticipantsScreen({super.key, required this.tripId});

  @override
  State<ParticipantsScreen> createState() => _ParticipantsScreenState();
}

class _ParticipantsScreenState extends State<ParticipantsScreen> {
  final _ctrl = TextEditingController();
  List<String> _names = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ParticipantsService.get(widget.tripId);
    if (!mounted) return;
    setState(() {
      _names = list;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    await ParticipantsService.add(widget.tripId, v);
    _ctrl.clear();
    await _load();
  }

  Future<void> _remove(String name) async {
    await ParticipantsService.remove(widget.tripId, name);
    await _load();
  }

  Future<void> _saveOrder() async {
    await ParticipantsService.save(widget.tripId, _names);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Participants saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Participants'),
        actions: [
          IconButton(
              onPressed: _saveOrder, icon: const Icon(Icons.save_outlined)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          decoration: const InputDecoration(
                            labelText: 'Add participant',
                            hintText: 'e.g. Alice',
                          ),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 0),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _names.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _names.removeAt(oldIndex);
                        _names.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (_, i) {
                      final n = _names[i];
                      return Dismissible(
                        key: ValueKey(n),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.delete,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer),
                        ),
                        onDismissed: (_) => _remove(n),
                        child: ListTile(
                          title: Text(n),
                          leading: const Icon(Icons.drag_handle),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => _remove(n),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
