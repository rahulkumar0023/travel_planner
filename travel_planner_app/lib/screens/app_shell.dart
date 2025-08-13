import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'expense_form_screen.dart'; // your existing form

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [
      DashboardScreen(),
      Placeholder(), // Trips screen (coming soon)
      Placeholder(), // Settings (coming soon)
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel Planner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: pages[_index],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExpenseFormScreen(
                onAddExpense: (title, amount, category, paidBy, sharedWith) {
                  // you already handle adding/saving; keep this wiring
                },
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Trips',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
