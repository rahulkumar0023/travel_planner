import 'package:flutter/material.dart';
import '../services/api_service.dart';

class GroupBalanceScreen extends StatefulWidget {
  final String tripId;

  const GroupBalanceScreen({super.key, required this.tripId});

  @override
  State<GroupBalanceScreen> createState() => _GroupBalanceScreenState();
}

class _GroupBalanceScreenState extends State<GroupBalanceScreen> {
  List<Map<String, dynamic>> _balances = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBalances();
  }

  Future<void> _loadBalances() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final balances = await ApiService.fetchGroupBalances(widget.tripId);
      setState(() {
        _balances = balances;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Balances'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBalances,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _balances.isEmpty
                  ? _buildEmptyState()
                  : _buildBalancesList(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text('Error loading balances'),
          Text(_error ?? '', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadBalances,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.balance, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No balances to show',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Add some shared expenses first'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Add Expenses'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalancesList() {
    return RefreshIndicator(
      onRefresh: _loadBalances,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _balances.length,
        itemBuilder: (context, index) {
          final balance = _balances[index];
          final amount = (balance['amount'] as num).toDouble();
          final isPositive = amount > 0;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isPositive ? Colors.green : Colors.red,
                child: Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  color: Colors.white,
                ),
              ),
              title: Text(
                isPositive
                    ? '${balance['owedTo']} owes you'
                    : 'You owe ${balance['owedBy']}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              trailing: Text(
                '€${amount.abs().toStringAsFixed(2)}',
                style: TextStyle(
                  color: isPositive ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

