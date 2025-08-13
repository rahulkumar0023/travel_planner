import 'package:flutter/material.dart';
import '../models/trip.dart';

class TripPickerScreen extends StatelessWidget {
  final Trip current;
  final void Function(Trip) onPick;
  const TripPickerScreen({super.key, required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    // TODO: fetch from API; for now demo two trips
    final demo = [
      current,
      Trip(
        id: 't2',
        name: 'Spain Escape',
        startDate: DateTime(2025, 10, 5),
        endDate: DateTime(2025, 10, 12),
        initialBudget: 1200,
        currency: 'EUR',
        participants: const ['Rahul', 'Alex'],
      ),
    ];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: demo.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final t = demo[i];
        final isActive = t.id == current.id;
        return Card(
          child: ListTile(
            title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${t.startDate.toString().split(' ').first} → ${t.endDate.toString().split(' ').first} • ${t.currency}'),
            trailing: isActive ? const Icon(Icons.check_circle, color: Colors.green) : null,
            onTap: () => onPick(t),
          ),
        );
      },
    );
  }
}

