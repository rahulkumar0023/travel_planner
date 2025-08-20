import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/monthly_category.dart';

class MonthlyStore {
  static String _key(DateTime month) =>
      'monthly_envelopes_${month.year}_${month.month.toString().padLeft(2, '0')}';

  /// Load envelopes (Income + Expense) for a month.
  static Future<List<MonthlyCategory>> load(DateTime month) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key(month));
    if (s == null || s.isEmpty) return _seed(month);
    try {
      final raw = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return raw.map(MonthlyCategory.fromJson).toList();
    } catch (_) {
      return _seed(month);
    }
  }

  /// Save the full set for the month.
  static Future<void> save(DateTime month, List<MonthlyCategory> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key(month),
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  /// First‑time defaults (you can tweak freely)
  static List<MonthlyCategory> _seed(DateTime month) {
    return [
      MonthlyCategory(
        id: 'cat_income_salary',
        kind: MonthlyKind.income,
        name: 'Salary',
        currency: 'EUR',
        subs: [MonthlySubcategory(id: 'sub_base', name: 'Base', planned: 0)],
      ),
      MonthlyCategory(
        id: 'cat_exp_food',
        kind: MonthlyKind.expense,
        name: 'Food',
        currency: 'EUR',
        subs: [
          MonthlySubcategory(
              id: 'sub_groceries', name: 'Groceries', planned: 200),
          MonthlySubcategory(
              id: 'sub_eatingout', name: 'Eating out', planned: 150),
        ],
      ),
      MonthlyCategory(
        id: 'cat_exp_transport',
        kind: MonthlyKind.expense,
        name: 'Transport',
        currency: 'EUR',
        subs: [
          MonthlySubcategory(
              id: 'sub_public', name: 'Public', planned: 50),
          MonthlySubcategory(
              id: 'sub_ride', name: 'Ride-hailing', planned: 50),
        ],
      ),
    ];
  }
}
