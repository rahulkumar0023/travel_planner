import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category.dart';

class CategoryStore {
  static const _k = 'categories_v1';

  // 👇 DEFAULT SEED: tweak anytime
  static List<CategoryItem> _seed() => [
        // Income roots
        CategoryItem(id: 'inc-salary', name: 'Salary', type: CategoryType.income, colorIndex: 0),
        CategoryItem(id: 'inc-bonus',  name: 'Bonus',  type: CategoryType.income, colorIndex: 1),

        // Expense roots
        CategoryItem(id: 'exp-food',       name: 'Food',       type: CategoryType.expense, colorIndex: 0),
        CategoryItem(id: 'exp-transport',  name: 'Transport',  type: CategoryType.expense, colorIndex: 1),
        CategoryItem(id: 'exp-lodging',    name: 'Lodging',    type: CategoryType.expense, colorIndex: 2),
        CategoryItem(id: 'exp-activities', name: 'Activities', type: CategoryType.expense, colorIndex: 3),
        CategoryItem(id: 'exp-other',      name: 'Other',      type: CategoryType.expense, colorIndex: 4),

        // 👇 NEW: example subcategories
        CategoryItem(id: 'exp-food-coffee', name: 'Coffee', type: CategoryType.expense, parentId: 'exp-food', colorIndex: 0),
        CategoryItem(id: 'exp-food-dinner', name: 'Dinner', type: CategoryType.expense, parentId: 'exp-food', colorIndex: 0),
      ];

  static Future<List<CategoryItem>> _loadAll() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_k);
    if (s == null || s.isEmpty) {
      final seed = _seed();
      await _saveAll(seed);
      return seed;
    }
    try {
      final raw = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return raw.map(CategoryItem.fromJson).toList();
    } catch (_) {
      final seed = _seed();
      await _saveAll(seed);
      return seed;
    }
  }

  static Future<void> _saveAll(List<CategoryItem> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  // Public APIs
  static Future<List<CategoryItem>> roots(CategoryType type) async {
    final all = await _loadAll();
    return all.where((c) => c.type == type && c.parentId == null).toList();
  }

  static Future<List<CategoryItem>> subsOf(String parentId) async {
    final all = await _loadAll();
    return all.where((c) => c.parentId == parentId).toList();
  }

  static Future<List<CategoryItem>> all() => _loadAll();

  static Future<void> upsert(CategoryItem item) async {
    final all = await _loadAll();
    final next = [
      for (final c in all) if (c.id != item.id) c,
      item,
    ];
    await _saveAll(next);
  }

  static Future<void> delete(String id) async {
    final all = await _loadAll();
    // also remove subs
    final toDelete = {id, ...all.where((c) => c.parentId == id).map((c) => c.id)};
    final next = all.where((c) => !toDelete.contains(c.id)).toList();
    await _saveAll(next);
  }
}
