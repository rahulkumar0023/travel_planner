import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import '../models/budget.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> with TickerProviderStateMixin {
  late Future<List<Budget>> _future;
  String _home = TripStorageService.getHomeCurrency();

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchBudgets();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.fetchBudgets());
    await _future;
  }

  Future<void> _createMonthlyDialog() async {
    final yearCtrl = TextEditingController(text: DateTime.now().year.toString());
    final monthCtrl = TextEditingController(text: DateTime.now().month.toString());
    final amountCtrl = TextEditingController();
    final currencyCtrl = TextEditingController(text: _home);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Monthly Budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: 'Year')),
            const SizedBox(height: 8),
            TextField(controller: monthCtrl, decoration: const InputDecoration(labelText: 'Month (1-12)')),
            const SizedBox(height: 8),
            TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
            const SizedBox(height: 8),
            TextField(controller: currencyCtrl, decoration: const InputDecoration(labelText: 'Currency (ISO 4217)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.api.createBudget(
          kind: BudgetKind.monthly,
          currency: currencyCtrl.text.trim().toUpperCase(),
          amount: double.tryParse(amountCtrl.text.trim()) ?? 0,
          year: int.tryParse(yearCtrl.text.trim()),
          month: int.tryParse(monthCtrl.text.trim()),
        );
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Monthly budget created')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create budget: $e')),
          );
        }
      }
    }

  }

  Future<void> _createTripDialog() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final currencyCtrl = TextEditingController(text: _home);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Trip Budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Krakow Trip)')),
            const SizedBox(height: 8),
            TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
            const SizedBox(height: 8),
            TextField(controller: currencyCtrl, decoration: const InputDecoration(labelText: 'Currency (ISO 4217)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.api.createBudget(
          kind: BudgetKind.trip,
          currency: currencyCtrl.text.trim().toUpperCase(),
          amount: double.tryParse(amountCtrl.text.trim()) ?? 0,
          name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        );
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trip budget created')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create budget: $e')),
          );
        }
      }
    }

  }

  Future<void> _linkTripToMonthly(Budget trip, List<Budget> monthly) async {
    final selected = await showDialog<Budget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Link to monthly budget'),
        children: [
          for (final m in monthly)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text('${m.year}-${m.month?.toString().padLeft(2, '0')} • ${m.amount.toStringAsFixed(0)} ${m.currency}'),
            )
        ],
      ),
    );
    if (selected != null) {
      await widget.api.linkTripBudget(tripBudgetId: trip.id, monthlyBudgetId: selected.id);
      _refresh();
    }
  }

  Future<double> _approx(String fromCurrency, double amount) async {
    _home = TripStorageService.getHomeCurrency();
    return widget.api.convert(amount: amount, from: fromCurrency, to: _home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<List<Budget>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load budgets:\n${snap.error}'));
          }
          final all = snap.data ?? const <Budget>[];
          final monthly = all.where((b) => b.kind == BudgetKind.monthly).toList();
          final trips   = all.where((b) => b.kind == BudgetKind.trip).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Monthly', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (monthly.isEmpty)
                const Text('No monthly budgets yet.'),
              for (final m in monthly)
                FutureBuilder<double>(
                  future: _approx(m.currency, m.amount),
                  builder: (_, approx) => Card(
                    child: ListTile(
                      title: Text('${m.year}-${m.month?.toString().padLeft(2, '0')} • ${m.amount.toStringAsFixed(0)} ${m.currency}'),
                      subtitle: (approx.hasData && _home != m.currency)
                          ? Text('≈ ${approx.data!.toStringAsFixed(2)} $_home')
                          : null,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Trip', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (trips.isEmpty)
                const Text('No trip budgets yet.'),
              for (final t in trips)
                FutureBuilder<double>(
                  future: _approx(t.currency, t.amount),
                  builder: (_, approx) => Card(
                    child: ListTile(
                      title: Text('${t.name ?? 'Trip'} • ${t.amount.toStringAsFixed(0)} ${t.currency}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (approx.hasData && _home != t.currency)
                            Text('≈ ${approx.data!.toStringAsFixed(2)} $_home'),
                          Text(
                            t.linkedMonthlyBudgetId == null
                                ? 'Not linked'
                                : 'Linked → ${t.linkedMonthlyBudgetId}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      trailing: TextButton(
                        onPressed: monthly.isEmpty ? null : () => _linkTripToMonthly(t, monthly),
                        child: const Text('Link'),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: _createMonthlyDialog,
            label: const Text('New Monthly'),
            icon: const Icon(Icons.calendar_today),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            onPressed: _createTripDialog,
            label: const Text('New Trip'),
            icon: const Icon(Icons.flight),
          ),
        ],
      ),
    );
  }
}
