import 'package:flutter/material.dart';
import 'package:travel_planner_app/models/currencies.dart';
import '../services/prefs_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _home = 'EUR';

  @override
  void initState() {
    super.initState();
    PrefsService.getHomeCurrency().then((v) => setState(() => _home = v));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Home currency'),
            subtitle: Text(_home),
            trailing: DropdownButton<String>(
              value: _home,
              items: kCurrencyCodes
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (val) async {
                if (val == null) return;
                setState(() => _home = val);
                await PrefsService.setHomeCurrency(val);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Home currency updated')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
