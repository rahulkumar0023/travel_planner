import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../models/expense.dart';
import '../services/api_service.dart';
import '../services/trip_storage_service.dart';
import 'expense_form_screen.dart';
import 'group_balance_screen.dart';
import 'trip_selection_screen.dart';
import 'package:hive/hive.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _currentTripId;
  String? _currentTripName;
  List<Expense> _expenses = [];
  bool _loading = true;
  String? _error;
  double _convertedTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCurrentTrip();
  }

  Future<void> _loadCurrentTrip() async {
    final tripId = await TripStorageService.getSelectedTripId();
    final tripName = await TripStorageService.getSelectedTripName();

    if (tripId == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TripSelectionScreen()),
      );
      return;
    }

    setState(() {
      _currentTripId = tripId;
      _currentTripName = tripName;
    });

    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    if (_currentTripId == null) return;

    setState(() => _loading = true);

    try {
      final apiExpenses = await ApiService.fetchExpenses(_currentTripId!);
      final box = Hive.box('expensesBox');
      final localExpenses = box.values
          .where((e) => e.tripId == _currentTripId)
          .cast<Expense>()
          .toList();

      final allExpenses = <String, Expense>{};
      for (final expense in [...localExpenses, ...apiExpenses]) {
        allExpenses[expense.id] = expense;
      }

      final expenses = allExpenses.values.toList();
      expenses.sort((a, b) => b.date.compareTo(a.date));

      final total = expenses.fold(0.0, (sum, e) => sum + e.amount);
      if (total > 0) {
        final converted = await ApiService.convert(total, 'EUR', 'USD');
        setState(() => _convertedTotal = converted);
      }

      setState(() {
        _expenses = expenses;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addExpense(
    String title,
    double amount,
    String category,
    String paidBy,
    List<String> sharedWith,
  ) async {
    if (_currentTripId == null) return;

    final expense = Expense(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      tripId: _currentTripId!,
      title: title,
      amount: amount,
      category: category,
      date: DateTime.now(),
      paidBy: paidBy,
      sharedWith: sharedWith,
    );

    final box = Hive.box('expensesBox');
    await box.add(expense);

    setState(() {
      _expenses.insert(0, expense);
    });

    try {
      await ApiService.addExpense(expense);
      _loadExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved offline - will sync when online')),
        );
      }
    }
  }

  void _switchTrip() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const TripSelectionScreen()),
    );
  }

  void _viewGroupBalances() {
    if (_currentTripId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupBalanceScreen(tripId: _currentTripId!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTripName ?? 'Travel Planner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _switchTrip,
            tooltip: 'Switch Trip',
          ),
          IconButton(
            icon: const Icon(Icons.group),
            onPressed: _viewGroupBalances,
            tooltip: 'Group Balances',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExpenseFormScreen(onAddExpense: _addExpense),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text('Error loading expenses'),
          Text(_error ?? '', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadExpenses,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final totalSpent = _expenses.fold(0.0, (sum, e) => sum + e.amount);

    return RefreshIndicator(
      onRefresh: _loadExpenses,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.blue.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Spent',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '€${totalSpent.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_convertedTotal > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '≈ \$${_convertedTotal.toStringAsFixed(2)} USD',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  '${_expenses.length} expenses',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _expenses.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _expenses.length,
                    itemBuilder: (context, index) {
                      final expense = _expenses[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getCategoryColor(expense.category),
                            child: Icon(
                              _getCategoryIcon(expense.category),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(expense.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${expense.category} • Paid by ${expense.paidBy}'),
                              if (expense.sharedWith.length > 1)
                                Text(
                                  'Shared with ${expense.sharedWith.join(', ')}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '€${expense.amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '${expense.date.day}/${expense.date.month}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No expenses yet',
            style: TextStyle(fontSize: 24),
          ),
          SizedBox(height: 8),
          Text('Add your first expense to get started'),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Colors.orange;
      case 'transport':
        return Colors.blue;
      case 'lodging':
        return Colors.green;
      case 'other':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'transport':
        return Icons.directions_car;
      case 'lodging':
        return Icons.hotel;
      case 'other':
        return Icons.shopping_bag;
      default:
        return Icons.receipt;
    }
  }
}

