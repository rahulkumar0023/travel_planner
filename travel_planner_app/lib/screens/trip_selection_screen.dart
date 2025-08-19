import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/trip.dart';
import 'dart:math';
import '../services/local_trip_store.dart';
import '../services/trip_storage_service.dart';
import '../models/currencies.dart'; // wherever kCurrencyCodes is defined
// imports patch start
import '../models/budget.dart'; // for BudgetKind.trip
// 👇 NEW import start
import '../services/budgets_sync.dart';
// 👇 NEW: to update budgets cache immediately
import '../services/local_budget_store.dart';
// 👇 NEW import end
// imports patch end

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
    _future = widget.api.fetchTripsOrCache();
  }

// _refresh method start
  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _future = widget.api.fetchTripsOrCache();
    });
    await _future; // no setState AFTER this await
  }
// _refresh method end

// 👇 NEW: ensure a Trip Budget exists for a created Trip (duplicate-guard)
// _ensureTripBudgetForTrip method start
Future<void> _ensureTripBudgetForTrip({
  required Trip trip,
}) async {
  try {
    // 1) See if a Trip budget already exists for this tripId
    final budgets = await widget.api.fetchBudgetsOrCache();
    final already = budgets.any((b) =>
        b.kind == BudgetKind.trip && b.tripId == trip.id);

    if (!already && trip.initialBudget > 0) {
      // 2) Create & cache the Trip Budget so Home sees it right away
      final newBudget = await widget.api.createBudget(
        kind: BudgetKind.trip,
        currency: trip.currency,
        amount: trip.initialBudget,
        tripId: trip.id,
        name: trip.name,
      );

      // 👇 NEW: push it into the local cache
      final existing = await LocalBudgetStore.load();
      existing.add(newBudget);
      await LocalBudgetStore.save(existing);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip budget created')),
        );
      }
    }

    // 3) Fire-and-forget: refresh budgets cache so Budgets tab shows the new row
    // ignore: unawaited_futures
    widget.api.fetchBudgetsOrCache();
  } catch (e) {
    if (!mounted) return;
    // Trip stays created even if budget fails — just inform the user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not create trip budget: $e')),
    );
  }
}
// _ensureTripBudgetForTrip method end

  Future<void> _createTripDialog() async {
    final nameCtrl = TextEditingController();
    final extraCcyCtrl = TextEditingController(text: 'TRY,INR'); // example default
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
            const SizedBox(height: 8),
            TextField(
              controller: extraCcyCtrl,
              decoration: const InputDecoration(
                labelText: 'Extra currencies (comma separated)',
                hintText: 'e.g. TRY, INR',
              ),
              textCapitalization: TextCapitalization.characters,
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
              // collect extras from the text field: "TRY,INR" -> ["TRY","INR"]
              final extras = extraCcyCtrl.text
                  .split(',')
                  .map((s) => s.trim().toUpperCase())
                  .where((s) => s.isNotEmpty)
                  .toSet()
                  .toList();

              // ensure base currency is included
              final spendCurrencies = <String>{ selectedCcy, ...extras }.toList();
              final trip = Trip(
                id: id,
                name: nameCtrl.text.trim(),
                startDate: DateTime.now(),
                endDate: DateTime.now().add(const Duration(days: 3)),
                initialBudget: double.tryParse(budgetCtrl.text.trim()) ?? 0,
                currency: selectedCcy,          // base/home currency
                participants: const [],
                spendCurrencies: spendCurrencies, // <-- NEW: attach choices
              );
              Navigator.pop(ctx, trip);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

// _createTripDialog auto-budget start
    if (created != null) {
      final saved = await widget.api.createTrip(created);

      // 👇 NEW: auto-create the Trip Budget for this Trip
      // auto-create trip budget call start
      await _ensureTripBudgetForTrip(trip: saved);
      // auto-create trip budget call end

      // 👇 NEW: signal budgets changed (home card will refresh) start
      BudgetsSync.instance.bump();
      // 👇 NEW: signal budgets changed (home card will refresh) end

      await TripStorageService.save(saved);
      if (mounted) {
        setState(() {
          _future = widget.api.fetchTripsOrCache(); // refresh list after creation
        });
        Navigator.of(context).pop<Trip>(saved);
      }
    }
// _createTripDialog auto-budget end

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

          final usingCache = widget.api.lastTripsFromCache;
          return Column(
            children: [
              if (usingCache)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Showing cached trips (offline or server unavailable). Pull to refresh.'),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (_, i) {
                      final t = trips[i];
                      return ListTile(
                        title: Text(t.name),
                        subtitle: Text('${t.currency} • Budget ${t.initialBudget.toStringAsFixed(0)}'),
                        // actions menu replaces the chevron
                        trailing: PopupMenuButton<String>(
                          // Replace your current onSelected with this guarded version
                          // Trip row actions (guarded) start
                          onSelected: (v) async {
                            if (v == 'edit') {
                              // TODO: navigate to your edit flow if you have one
                              // await Navigator.push(context, MaterialPageRoute(builder: (_) => TripFormScreen(trip: t)));
                              if (!mounted) return; // guard before setState after awaiting
                              setState(() {
                                _future = widget.api.fetchTripsOrCache();
                              });
                            // delete feedback start
                            } else if (v == 'delete') {
                              try {
                                await widget.api.deleteTrip(t.id);

                                // 1) clear the active/saved trip if it's the one we deleted
                                await TripStorageService.clearIf(t.id);

                                // 2) (optional) prune cached trips list so UI never shows this trip offline
                                try {
                                  final trips = await LocalTripStore.load();
                                  final pruned = trips.where((x) => x.id != t.id).toList();
                                  await LocalTripStore.save(pruned);
                                } catch (_) {}

                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Trip deleted')),
                                );

                                // 3) refresh the list from server or cache
                                setState(() { _future = widget.api.fetchTripsOrCache(); });
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Delete failed: $e')),
                                );
                              }
                            }
                            else if (v == 'create_budget') {
                              // trip row menu handler add-budget start
                              try {
                                await widget.api.createBudget(
                                  kind: BudgetKind.trip,
                                  currency: t.currency,
                                  amount: t.initialBudget,
                                  tripId: t.id,
                                  name: t.name,
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Trip budget created')),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not create budget: $e')),
                                );
                              }
                              if (!mounted) return;
                              setState(() { _future = widget.api.fetchTripsOrCache(); });
                            }// trip row menu handler add-budget end
                          // delete feedback end

                          },
                          // Trip row actions (guarded) end
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                            // trip row menu items add-budget start
                            PopupMenuItem(value: 'create_budget', child: Text('Create budget from trip')),
                            // trip row menu items add-budget end
                          ],
                        ),
                        // tap still selects and returns the trip
                        onTap: () => Navigator.of(context).pop<Trip>(t),
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: trips.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-trip-selection', // <-- add this line
        onPressed: _createTripDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Trip'),
      ),
    );
  }
}
