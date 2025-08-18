// lib/services/local_expense_store.dart

// ===== LocalExpenseStore class start =====
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/expense.dart';

class LocalExpenseStore {
  static const _kExpensesByTripKeyPrefix = 'expenses_by_trip_'; // key per trip

  // 👇 NEW: save expenses list per trip to SharedPreferences
  // saveExpensesForTrip start
  static Future<void> saveExpensesForTrip(String tripId, List<Expense> expenses) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = expenses.map((e) => e.toJson()).toList();
    await prefs.setString('$_kExpensesByTripKeyPrefix$tripId', jsonEncode(jsonList));
  }
  // saveExpensesForTrip end

  // 👇 NEW: load expenses list per trip from SharedPreferences
  // loadExpensesForTrip start
  static Future<List<Expense>> loadExpensesForTrip(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kExpensesByTripKeyPrefix$tripId');
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map((m) => Expense.fromJson(m)).toList();
  }
  // loadExpensesForTrip end
}
// ===== LocalExpenseStore class end =====
