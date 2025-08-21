// ===== monthly_store.dart — START =====
// Description: Local store for monthly categories & transactions (Hive).
// Usage: MonthlyStore.instance.*

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/monthly_category.dart';
import '../models/monthly_txn.dart';

class MonthlyStore {
  MonthlyStore._();
  static final MonthlyStore instance = MonthlyStore._();

  static const _catBoxName = 'monthly_categories';
  static const _txnBoxName = 'monthly_txns';

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(41)) {
      Hive.registerAdapter(MonthlyCategoryAdapter());
    }
    if (!Hive.isAdapterRegistered(42)) {
      Hive.registerAdapter(MonthlyTxnAdapter());
    }
    await Hive.openBox<MonthlyCategory>(_catBoxName);
    await Hive.openBox<MonthlyTxn>(_txnBoxName);
  }

  Box<MonthlyCategory> get _catBox => Hive.box<MonthlyCategory>(_catBoxName);
  Box<MonthlyTxn> get _txnBox => Hive.box<MonthlyTxn>(_txnBoxName);
  final _uuid = const Uuid();

  // 👇 NEW: Category CRUD
  Future<MonthlyCategory> addCategory({
    required String name,
    required String monthKey,
    required String type, // 'income' | 'expense'
    String? parentId,
  }) async {
    final c = MonthlyCategory(
      id: _uuid.v4(),
      name: name.trim(),
      monthKey: monthKey,
      type: type,
      parentId: parentId,
    );
    await _catBox.put(c.id, c);
    return c;
  }

  Future<void> renameCategory(String id, String newName) async {
    final c = _catBox.get(id);
    if (c == null) return;
    c.name = newName.trim();
    await c.save();
  }

  Future<void> deleteCategory(String id) async {
    // also delete its sub-categories + orphan txns
    final subs =
        _catBox.values.where((x) => x.parentId == id).map((x) => x.id).toSet();
    await _catBox.deleteAll(subs);
    await _txnBox.deleteAll(_txnBox.values
        .where((t) => t.categoryId == id || subs.contains(t.categoryId))
        .map((t) => t.id));
    await _catBox.delete(id);
  }

  List<MonthlyCategory> categoriesFor(String monthKey,
      {String? type, String? parentId}) {
    return _catBox.values
        .where((c) =>
            c.monthKey == monthKey &&
            (type == null || c.type == type) &&
            (parentId == c.parentId))
        .toList()
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // 👇 NEW: Transactions
  Future<MonthlyTxn> addTxn({
    required String monthKey,
    required String categoryId,
    required double amount,
    required String currency,
    String note = '',
    DateTime? date,
    required String type, // 'income' | 'expense'
  }) async {
    final t = MonthlyTxn(
      id: _uuid.v4(),
      monthKey: monthKey,
      categoryId: categoryId,
      amount: amount,
      currency: currency,
      note: note,
      date: date ?? DateTime.now(),
      type: type,
    );
    await _txnBox.put(t.id, t);
    return t;
  }

  Future<void> deleteTxn(String id) async => _txnBox.delete(id);

  List<MonthlyTxn> txnsFor(String monthKey) {
    final list = _txnBox.values
        .where((t) => t.monthKey == monthKey)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }
}
// ===== monthly_store.dart — END =====
