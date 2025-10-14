import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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

  Future<void> _persistCategories(String monthKey, List<MonthlyCategory> list) async {
    _catCache[monthKey] = list;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _catKey(monthKey),
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _removeTxnsMatching(
      String monthKey, bool Function(MonthlyTxn txn) predicate) async {
    final list = await MonthlyStore.all(monthKey);
    final kept = <MonthlyTxn>[];
    final removed = <MonthlyTxn>[];
    for (final txn in list) {
      if (predicate(txn)) {
        removed.add(txn);
      } else {
        kept.add(txn);
      }
    }
    _txCache[monthKey] = kept;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _txKey(monthKey),
      jsonEncode(kept.map((e) => e.toJson()).toList()),
    );
    for (final txn in removed) {
      if (_txn.containsKey(txn.id)) {
        await _txn.delete(txn.id);
      }
    }
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
      MonthlyCategory? parent;
      for (final c in list) {
        if (c.id == parentId) {
          parent = c;
          break;
        }
      }
      final parentCat = parent;
      if (parentCat == null) return <MonthlyCategory>[];
      return parentCat.subs
          .map((s) => MonthlyCategory(
                id: s.id,
                name: s.name,
                kind: parentCat.kind,
                subs: const [],
                parentId: parentId,
                planned: s.planned,
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
    double planned = 0,
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
              planned: planned,
            )
          ]);
        }
        return c;
      }).toList();
      await _persistCategories(monthKey, next);
      return;
    }

    final cat = MonthlyCategory(
      id: 'cat-\${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      kind: MonthlyKind.values.firstWhere((k) => k.name == type,
          orElse: () => MonthlyKind.expense),
      subs: const [],
      planned: planned,
    );
    final next = [...list, cat];
    await _persistCategories(monthKey, next);
  }

  Future<void> deleteCategory({
    required String monthKey,
    required String categoryId,
    String? parentId,
  }) async {
    final list = await categories(monthKey);
    if (parentId == null) {
      MonthlyCategory? target;
      for (final c in list) {
        if (c.id == categoryId) {
          target = c;
          break;
        }
      }
      if (target == null) return;
      final subIds = target.subs.map((s) => s.id).toSet();
      await _removeTxnsMatching(monthKey, (txn) {
        if (txn.categoryId == categoryId) return true;
        final subId = txn.subCategoryId;
        return subId != null && subIds.contains(subId);
      });
      final next = list.where((c) => c.id != categoryId).toList();
      await _persistCategories(monthKey, next);
    } else {
      MonthlyCategory? parent;
      for (final c in list) {
        if (c.id == parentId) {
          parent = c;
          break;
        }
      }
      if (parent == null) return;
      final next = list.map((c) {
        if (c.id == parentId) {
          final subs = c.subs.where((s) => s.id != categoryId).toList();
          return c.copyWith(subs: subs);
        }
        return c;
      }).toList();
      await _removeTxnsMatching(
          monthKey, (txn) => txn.subCategoryId == categoryId);
      await _persistCategories(monthKey, next);
    }
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
