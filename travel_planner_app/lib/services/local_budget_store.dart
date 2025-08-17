import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/budget.dart';

class LocalBudgetStore {
  static const _k = 'cached_budgets_v1';

  static Future<void> save(List<Budget> budgets) async {
    final p = await SharedPreferences.getInstance();
    final list = budgets.map((b) => b.toJson()).toList();
    await p.setString(_k, jsonEncode(list));
  }

  static Future<List<Budget>> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_k);
    if (s == null || s.isEmpty) return <Budget>[];
    try {
      final raw = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return raw.map(Budget.fromJson).toList();
    } catch (_) {
      return <Budget>[];
    }
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_k);
  }
}