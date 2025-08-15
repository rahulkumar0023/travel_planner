import 'package:flutter/material.dart';
import '../services/participants_service.dart';

class ParticipantsScreen extends StatefulWidget {
  final String tripId; // kept for future use
  const ParticipantsScreen({super.key, required this.tripId});

  @override
  State<ParticipantsScreen> createState() => _ParticipantsScreenState();
}

class _ParticipantsScreenState extends State<ParticipantsScreen> {
  final _ctrl = TextEditingController();
  final ParticipantsService _service = participantsService;

  Future<void> _add() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    await _service.add(v);
    _ctrl.clear();
  }

  Future<void> _remove(String name) async {
    await _service.remove(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Participants')),
      body: AnimatedBuilder(
        animation: _service,
        builder: (context, _) {
          final names = _service.participants;
          return Column(
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
                child: ListView.builder(
                  itemCount: names.length,
                  itemBuilder: (_, i) {
                    final n = names[i];
                    return Dismissible(
                      key: ValueKey(n),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Theme.of(context).colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Icon(
                          Icons.delete,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      onDismissed: (_) => _remove(n),
                      child: ListTile(
                        title: Text(n),
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
          );
        },
      ),
    );
  }
}
