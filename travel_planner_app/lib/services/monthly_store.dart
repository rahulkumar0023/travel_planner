import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../models/monthly_txn.dart';
import '../models/monthly_category.dart';

/// Format helper used by ApiService.fetchMonthlySummary(...)
String monthKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

class MonthlyStore {
  MonthlyStore._();
  static final MonthlyStore instance = MonthlyStore._();

  // Caches for sync access
  static final Map<String, List<MonthlyTxn>> _txCache = {};
  static final Map<String, List<MonthlyCategory>> _catCache = {};

  // Storage keys
  static String _txKey(String monthKey)   => 'monthly_txns_v1_\$monthKey';
  static String _catKey(String monthKey)  => 'monthly_cats_v1_\$monthKey';

  // ---------- Transactions ----------
  /// STATIC: used by ApiService.fetchMonthlySummary(...)
  static Future<List<MonthlyTxn>> all(String monthKey) async {
    if (_txCache.containsKey(monthKey)) return _txCache[monthKey]!;
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_txKey(monthKey));
    if (s == null || s.isEmpty) {
      _txCache[monthKey] = <MonthlyTxn>[];
      return _txCache[monthKey]!;
    }
    try {
      final raw = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      final list = raw.map(MonthlyTxn.fromJson).toList();
      _txCache[monthKey] = list;
      return list;
    } catch (_) {
      _txCache[monthKey] = <MonthlyTxn>[];
      return _txCache[monthKey]!;
    }
  }

  /// Add/Upsert a monthly transaction (income or expense)
  Future<void> addTxn({
    required String monthKey,
    required MonthlyTxnKind kind, // income | expense
    required String currency,
    required double amount,
    String? categoryId,
    String? subCategoryId,
    String? note,
    DateTime? date,
  }) async {
    final now = date ?? DateTime.now();
    final list = await MonthlyStore.all(monthKey);
    final item = MonthlyTxn(
      id: 'txn-\${now.microsecondsSinceEpoch}',
      kind: kind,
      currency: currency.toUpperCase(),
      amount: amount,
      categoryId: categoryId,
      subCategoryId: subCategoryId,
      note: note ?? '',
      date: now,
    );
    final next = [...list, item];
    _txCache[monthKey] = next;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _txKey(monthKey),
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
  }

  /// Synchronous access to cached transactions (falls back to empty list).
  List<MonthlyTxn> txnsFor(String monthKey) => _txCache[monthKey] ?? <MonthlyTxn>[];

  // ---------- Categories (for monthly envelopes) ----------
  Future<List<MonthlyCategory>> categories(String monthKey) async {
    if (_catCache.containsKey(monthKey)) return _catCache[monthKey]!;
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_catKey(monthKey));
    if (s == null || s.isEmpty) {
      _catCache[monthKey] = <MonthlyCategory>[];
      return _catCache[monthKey]!;
    }
    try {
      final raw = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      final list = raw.map(MonthlyCategory.fromJson).toList();
      _catCache[monthKey] = list;
      return list;
    } catch (_) {
      _catCache[monthKey] = <MonthlyCategory>[];
      return _catCache[monthKey]!;
    }
  }

  /// Synchronous access with optional filtering similar to old API.
  List<MonthlyCategory> categoriesFor(String monthKey,
      {String? type, String? parentId}) {
    final list = _catCache[monthKey] ?? <MonthlyCategory>[];
    if (parentId != null) {
      final parent = list.firstWhereOrNull((c) => c.id == parentId);
      if (parent == null) return <MonthlyCategory>[];
      return parent.subs
          .map((s) => MonthlyCategory(
                id: s.id,
                name: s.name,
                kind: parent.kind,
                subs: const [],
                parentId: parentId,
              ))
          .toList();
    }
    return list
        .where((c) => type == null || c.kind.name == type)
        .toList();
  }

  Future<void> addCategory({
    required String monthKey,
    required String name,
    required String type, // 'income' | 'expense'
    String? parentId,
  }) async {
    final list = await categories(monthKey);
    if (parentId != null) {
      final next = list.map((c) {
        if (c.id == parentId) {
          return c.copyWith(
              subs: [...c.subs, MonthlySubCategory(
                id: 'sub-\${DateTime.now().microsecondsSinceEpoch}',
                name: name.trim(),
              )]);
        }
        return c;
      }).toList();
      _catCache[monthKey] = next;
      final p = await SharedPreferences.getInstance();
      await p.setString(_catKey(monthKey),
          jsonEncode(next.map((e) => e.toJson()).toList()));
      return;
    }

    final cat = MonthlyCategory(
      id: 'cat-\${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      kind: MonthlyKind.values.firstWhere((k) => k.name == type,
          orElse: () => MonthlyKind.expense),
      subs: const [],
    );
    final next = [...list, cat];
    _catCache[monthKey] = next;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _catKey(monthKey),
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
  }
}
