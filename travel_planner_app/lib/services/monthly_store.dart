import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
// monthly_store imports start
import 'package:hive/hive.dart';
import '../models/monthly_txn.dart';
// monthly_store imports end
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

  // txn box fields start
  static const _txnBoxName = 'monthly_txns';
  Box<MonthlyTxn> get _txn => Hive.box<MonthlyTxn>(_txnBoxName);
  // txn box fields end

  // Storage keys
  static String _txKey(String monthKey)   => 'monthly_txns_v1_\$monthKey';
  static String _catKey(String monthKey)  => 'monthly_cats_v1_\$monthKey';

  /// Initialize local Hive storage boxes for monthly data.
  Future<void> init() async {
    await Hive.openBox('monthly_budgets');
    await Hive.openBox('monthly_categories');
    // init setup start
    // Register adapters if not already
    if (!Hive.isAdapterRegistered(42)) {
      Hive.registerAdapter(MonthlyTxnAdapter()); // typeId must match your model
    }

    // Open the txns box (id -> MonthlyTxn)
    if (!Hive.isBoxOpen(_txnBoxName)) {
      await Hive.openBox<MonthlyTxn>(_txnBoxName);
    }

    // ⚠️ If you also keep categories in this store, keep your existing opens here too.
    // init setup end
  }

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
    required String currency,
    required double amount,
    String? categoryId,
    String? subCategoryId,
    String? note,
    DateTime? date,
    required String kind, // 'income' | 'expense'
  }) async {
    final now = date ?? DateTime.now();
    final list = await MonthlyStore.all(monthKey);
    final kindEnum = (kind.toLowerCase() == 'income')
        ? MonthlyTxnKind.income
        : MonthlyTxnKind.expense;

    final item = MonthlyTxn(
      id: 'txn-\${now.microsecondsSinceEpoch}',
      kind: kindEnum,
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

  // deleteTxn helper start
  Future<void> deleteTxn(String id) async {
    // Remove from in-memory cache
    for (final entry in _txCache.entries) {
      final list = entry.value;
      final next = list.where((t) => t.id != id).toList();
      if (next.length != list.length) {
        _txCache[entry.key] = next;
        final p = await SharedPreferences.getInstance();
        await p.setString(
          _txKey(entry.key),
          jsonEncode(next.map((e) => e.toJson()).toList()),
        );
        break;
      }
    }

    // Also remove from Hive box if present
    if (_txn.containsKey(id)) {
      await _txn.delete(id);
    }
  }
  // deleteTxn helper end

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
              subs: [
            ...c.subs,
            MonthlySubCategory(
              id: 'sub-\${DateTime.now().microsecondsSinceEpoch}',
              name: name.trim(),
              planned: 0.0,
            )
          ]);
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

  // cloneMonth start
  Future<void> cloneMonth({
    required String fromMonthKey,
    required String toMonthKey,
  }) async {
    final existingRoots =
        categoriesFor(toMonthKey, parentId: null).map((c) => c.name.trim().toLowerCase()).toSet();

    // Copy Income roots
    final incomeRoots =
        categoriesFor(fromMonthKey, type: 'income', parentId: null);
    for (final r in incomeRoots) {
      final key = r.name.trim().toLowerCase();
      if (existingRoots.contains(key)) continue;
      await addCategory(name: r.name, monthKey: toMonthKey, type: 'income');
      existingRoots.add(key);
      final newRoot = categoriesFor(toMonthKey, type: 'income', parentId: null)
          .firstWhere((c) => c.name.trim().toLowerCase() == key);
      final subs =
          categoriesFor(fromMonthKey, type: 'income', parentId: r.id);
      for (final s in subs) {
        await addCategory(
          name: s.name,
          monthKey: toMonthKey,
          type: 'income',
          parentId: newRoot.id,
        );
      }
    }

    // Copy Expense roots
    final expenseRoots =
        categoriesFor(fromMonthKey, type: 'expense', parentId: null);
    for (final r in expenseRoots) {
      final key = r.name.trim().toLowerCase();
      if (existingRoots.contains(key)) continue;
      await addCategory(name: r.name, monthKey: toMonthKey, type: 'expense');
      existingRoots.add(key);
      final newRoot = categoriesFor(toMonthKey, type: 'expense', parentId: null)
          .firstWhere((c) => c.name.trim().toLowerCase() == key);
      final subs =
          categoriesFor(fromMonthKey, type: 'expense', parentId: r.id);
      for (final s in subs) {
        await addCategory(
          name: s.name,
          monthKey: toMonthKey,
          type: 'expense',
          parentId: newRoot.id,
        );
      }
    }
  }
  // cloneMonth end
}
