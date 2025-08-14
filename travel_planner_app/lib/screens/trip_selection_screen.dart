import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/trip.dart';
import 'dart:math';
import '../services/trip_storage_service.dart';
import '../models/currencies.dart'; // wherever kCurrencyCodes is defined

class TripSelectionScreen extends StatefulWidget {
  final ApiService api;
  const TripSelectionScreen({super.key, required this.api});

  @override
  State<TripSelectionScreen> createState() => _TripSelectionScreenState();
}

class _TripSelectionScreenState extends State<TripSelectionScreen> {
  late Future<List<Trip>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchTrips();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.api.fetchTrips();
    });
    await _future;
  }

  Future<void> _createTripDialog() async {
    final nameCtrl = TextEditingController();
    final budgetCtrl = TextEditingController(text: '1000');
    //final currencyCtrl = TextEditingController(text: 'EUR');

    String selectedCcy = 'EUR';

    final created = await showDialog<Trip>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a Trip'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Trip name')),
            TextField(
                controller: budgetCtrl,
                decoration: const InputDecoration(labelText: 'Initial budget'),
                keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedCcy,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: kCurrencyCodes
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => selectedCcy = (v ?? 'EUR'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              final id = 'trip_${Random().nextInt(999999)}';
              final trip = Trip(
                id: id,
                name: nameCtrl.text.trim(),
                startDate: DateTime.now(),
                endDate: DateTime.now().add(const Duration(days: 3)),
                initialBudget: double.tryParse(budgetCtrl.text.trim()) ?? 0,
                currency: selectedCcy, // <- from dropdown, guaranteed ISO code
                participants: const [],
              );
              Navigator.pop(ctx, trip);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created != null) {
      final saved = await widget.api.createTrip(created);
      await TripStorageService.save(saved);
      setState(() {
        _future = widget.api.fetchTrips(); // refresh list after creation
      });
      if (!mounted) return;
      Navigator.of(context).pop<Trip>(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Trip')),
      body: FutureBuilder<List<Trip>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error loading trips:\n${snap.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final trips = snap.data ?? [];
          if (trips.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No trips yet'),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _createTripDialog,
                      child: const Text('Create your first trip')),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (_, i) {
                final t = trips[i];
                return ListTile(
                  title: Text(t.name),
                  subtitle: Text(
                      '${t.currency} • Budget ${t.initialBudget.toStringAsFixed(0)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop<Trip>(t),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: trips.length,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTripDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Trip'),
      ),
    );
  }
}
