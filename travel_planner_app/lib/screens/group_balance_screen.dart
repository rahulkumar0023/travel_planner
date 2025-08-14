import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../models/group_balance.dart';
import '../services/api_service.dart';

class GroupBalanceScreen extends StatefulWidget {
  final Trip activeTrip;
  const GroupBalanceScreen({super.key, required this.activeTrip});

  @override
  State<GroupBalanceScreen> createState() => _GroupBalanceScreenState();
}

class _GroupBalanceScreenState extends State<GroupBalanceScreen> {
  late Future<List<GroupBalance>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchGroupBalances(
      widget.activeTrip.id,
    ); // no setState here
  }

  Future<void> _refresh() async {
    final fut = ApiService.fetchGroupBalances(
      widget.activeTrip.id,
    ); // do async work OUTSIDE setState
    if (!mounted) return;
    setState(() {
      _future = fut;
    }); // set synchronously
    try {
      await fut;
    } catch (_) {} // await after setState (not inside it)
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<GroupBalance>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            // Show a friendly error with Retry that calls _refresh (NOT wrapped in setState)
            return ListView(
              children: [
                const SizedBox(height: 100),
                Icon(Icons.error_outline, size: 48, color: cs.error),
                const SizedBox(height: 12),
                Center(child: Text('Couldn’t load balances')),
                const SizedBox(height: 8),
                Center(
                  child: ElevatedButton.icon(
                    onPressed:
                        _refresh, // 👈 not inside setState, not async lambda
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              ],
            );
          }

          final items = snap.data ?? const <GroupBalance>[];
          if (items.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 100),
                Center(child: Text('No balances yet — add some expenses!')),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final b = items[i];
              final amt = b.amount.toStringAsFixed(2);
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.swap_horiz, color: cs.onPrimaryContainer),
                  ),
                  title: Text(
                    '${b.from} → ${b.to}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('settlement'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$amt ${b.currency}',
                      style: TextStyle(
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
