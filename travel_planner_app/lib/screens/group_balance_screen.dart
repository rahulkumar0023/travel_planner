import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/balance_row.dart'; // <-- make sure BalanceRow is in models, or import from where you defined it

class GroupBalanceScreen extends StatefulWidget {
  final String tripId;
  final String currency; // show amounts in trip currency
  final ApiService api; // pass the instance if your fetch method is not static
  final List<String> participants;
  final List<String>? spendCurrencies;

  const GroupBalanceScreen({
    super.key,
    required this.tripId,
    required this.currency,
    required this.api,
    required this.participants,
    this.spendCurrencies,
  });

  @override
  State<GroupBalanceScreen> createState() => _GroupBalanceScreenState();
}

class _GroupBalanceScreenState extends State<GroupBalanceScreen> {
  late Future<List<BalanceRow>> _future;
  List<BalanceRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<BalanceRow>> _load() async {
    final rows = await widget.api.fetchGroupBalances(widget.tripId);
    _rows = rows;
    return rows;
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openSettleDialog() async {
    final tripId = widget.tripId;
    final people = <String>{...widget.participants};
    for (final r in _rows) {
      people.add(r.from);
      people.add(r.to);
    }
    final who = people.toList()..sort();

    String? from = who.isNotEmpty ? who.first : null;
    String? to   = (who.length > 1) ? who[1] : null;
    final amount = TextEditingController();
    String ccy = widget.currency; // default to trip currency
    final note = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settle up'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: from, hint: const Text('From'),
            items: who.map((p)=>DropdownMenuItem(value:p, child: Text(p))).toList(),
            onChanged: (v)=> from = v,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: to, hint: const Text('To'),
            items: who.where((p)=>p!=from).map((p)=>DropdownMenuItem(value:p, child: Text(p))).toList(),
            onChanged: (v)=> to = v,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: ccy,
            items: {widget.currency, ...?widget.spendCurrencies}.whereType<String>()
                .map((c)=>DropdownMenuItem(value:c, child: Text(c))).toList(),
            onChanged: (v)=> ccy = v ?? ccy,
            decoration: const InputDecoration(labelText: 'Currency'),
          ),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
        ]),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Cancel')),
          FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Record')),
        ],
      ),
    );

    if (ok != true || from == null || to == null) return;
    final v = double.tryParse(amount.text.trim()) ?? 0;
    if (v <= 0) return;

    try {
      await widget.api.createSettlement(
        tripId: tripId, from: from!, to: to!, amount: v, currency: ccy, note: note.text.trim().isEmpty ? null : note.text.trim(),
      );
      await _refresh(); // reload balances/rows
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settlement recorded')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Balances')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-settle',
        onPressed: _openSettleDialog,
        icon: const Icon(Icons.handshake),
        label: const Text('Settle up'),
      ),
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
