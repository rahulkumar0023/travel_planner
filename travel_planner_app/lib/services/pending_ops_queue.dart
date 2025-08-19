// lib/services/pending_ops_queue.dart

// ===== PendingOpsQueue class start =====
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PendingOpsQueue {
  static const _kKey = 'pending_expense_ops_v1';

  // enqueue start
  static Future<void> enqueue(Map<String, dynamic> op) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _load();
    list.add(op);
    await prefs.setString(_kKey, jsonEncode(list));
  }
  // enqueue end

  // drain start
  static Future<List<Map<String, dynamic>>> drain() async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _load();
    await prefs.remove(_kKey);
    return list;
  }
  // drain end

  // peekAll start
  static Future<List<Map<String, dynamic>>> peekAll() => _load();
  // peekAll end

  static Future<List<Map<String, dynamic>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return [];
    final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return decoded;
  }
}
// ===== PendingOpsQueue class end =====
