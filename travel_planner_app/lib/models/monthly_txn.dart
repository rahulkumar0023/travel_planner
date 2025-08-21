// ===== monthly_txn.dart — START =====
// Description: Model for Monthly Transactions (salary & expenses).

import 'package:hive/hive.dart';

enum MonthlyTxnKind { income, expense }

class MonthlyTxn {
  final String id;
  final MonthlyTxnKind kind;
  final String currency;
  final double amount;
  final String? categoryId;
  final String? subCategoryId;
  final String note;
  final DateTime date;

  MonthlyTxn({
    required this.id,
    required this.kind,
    required this.currency,
    required this.amount,
    this.categoryId,
    this.subCategoryId,
    this.note = '',
    required this.date,
  });

  // Backwards-compatibility getter for UI code expecting a `type` string.
  // Maps the `MonthlyTxnKind` enum to 'income' or 'expense'.
  String get type =>
      kind == MonthlyTxnKind.income ? 'income' : 'expense';

  factory MonthlyTxn.fromJson(Map<String, dynamic> json) => MonthlyTxn(
        id: json['id'] as String,
        kind: MonthlyTxnKind.values.firstWhere(
            (k) => k.name == (json['kind'] as String? ?? 'expense'),
            orElse: () => MonthlyTxnKind.expense),
        currency: json['currency'] as String? ?? '',
        amount: (json['amount'] as num).toDouble(),
        categoryId: json['categoryId'] as String?,
        subCategoryId: json['subCategoryId'] as String?,
        note: json['note'] as String? ?? '',
        date: DateTime.parse(json['date'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'currency': currency,
        'amount': amount,
        if (categoryId != null) 'categoryId': categoryId,
        if (subCategoryId != null) 'subCategoryId': subCategoryId,
        'note': note,
        'date': date.toIso8601String(),
      };
}

// Adapter for Hive persistence
class MonthlyTxnAdapter extends TypeAdapter<MonthlyTxn> {
  @override
  final int typeId = 42;

  @override
  MonthlyTxn read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return MonthlyTxn(
      id: fields[0] as String,
      kind: MonthlyTxnKind.values[fields[1] as int],
      currency: fields[2] as String,
      amount: fields[3] as double,
      categoryId: fields[4] as String?,
      subCategoryId: fields[5] as String?,
      note: fields[6] as String,
      date: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, MonthlyTxn obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.kind.index)
      ..writeByte(2)
      ..write(obj.currency)
      ..writeByte(3)
      ..write(obj.amount)
      ..writeByte(4)
      ..write(obj.categoryId)
      ..writeByte(5)
      ..write(obj.subCategoryId)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.date);
  }
}
// ===== monthly_txn.dart — END =====
