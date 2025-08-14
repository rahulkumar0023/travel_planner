import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/balance_row.dart'; // <-- make sure BalanceRow is in models, or import from where you defined it

class GroupBalanceScreen extends StatefulWidget {
  final String tripId;
  final String currency; // show amounts in trip currency
  final ApiService api; // pass the instance if your fetch method is not static

  const GroupBalanceScreen({
    super.key,
    required this.tripId,
    required this.currency,
    required this.api,
  });

  @override
  State<GroupBalanceScreen> createState() => _GroupBalanceScreenState();
}

class _GroupBalanceScreenState extends State<GroupBalanceScreen> {
  late Future<List<BalanceRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchGroupBalances(widget.tripId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.api.fetchGroupBalances(widget.tripId);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Balances')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<BalanceRow>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load balances:\n${snap.error}',
                      textAlign: TextAlign.center),
                ),
              ]);
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('All settled 🎉', textAlign: TextAlign.center),
                ),
              ]);
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                return ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text('${r.from} → ${r.to}'),
                  trailing:
                      Text('${r.amount.toStringAsFixed(2)} ${widget.currency}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
