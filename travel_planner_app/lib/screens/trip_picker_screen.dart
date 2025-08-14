import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/api_service.dart';

class TripPickerScreen extends StatefulWidget {
  final void Function(Trip) onPick;
  const TripPickerScreen({super.key, required this.onPick});

  @override
  State<TripPickerScreen> createState() => _TripPickerScreenState();
}

class _TripPickerScreenState extends State<TripPickerScreen> {
  late Future<List<Trip>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchTrips();
  }

  Future<void> _refresh() async {
    setState(() => _future = ApiService.fetchTrips());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Trip>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 100),
                const Center(child: Text('Could not load trips')),
                Center(
                    child: Text('${snap.error}',
                        style: Theme.of(context).textTheme.bodySmall)),
                const SizedBox(height: 12),
                Center(
                  child:
                      ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
                ),
              ],
            );
          }

          final trips = snap.data ?? [];
          if (trips.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 100),
                Center(child: Text('No trips yet — create one!')),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: trips.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final t = trips[i];
              final d1 = t.startDate.toString().split(' ').first;
              final d2 = t.endDate.toString().split(' ').first;
              return Card(
                child: ListTile(
                  title: Text(t.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('$d1 → $d2 • ${t.currency}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onPick(t),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

