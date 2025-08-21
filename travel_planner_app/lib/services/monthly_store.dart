// services/monthly_store.dart
// ▷ MonthlyStore start
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/monthly_txn.dart';

String monthKeyOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

class MonthlyStore {
  static String _k(String monthKey) => 'monthly_txns_$monthKey';

  static Future<List<MonthlyTxn>> all(String monthKey) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_k(monthKey));
    if (s == null || s.isEmpty) return <MonthlyTxn>[];
    final list = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    return list.map(MonthlyTxn.fromJson).toList();
  }

  static Future<void> _save(String monthKey, List<MonthlyTxn> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k(monthKey), jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<void> add(String monthKey, MonthlyTxn txn) async {
    final list = await all(monthKey);
    final next = [...list.where((t) => t.id != txn.id), txn];
    await _save(monthKey, next);
  }

  static Future<void> delete(String monthKey, String id) async {
    final list = await all(monthKey);
    await _save(monthKey, list.where((t) => t.id != id).toList());
  }
}
// ◀ MonthlyStore end
