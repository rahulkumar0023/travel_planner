// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monthly_txn.dart';

class MonthlyTxnAdapter extends TypeAdapter<MonthlyTxn> {
  @override
  final int typeId = 42;

  @override
  MonthlyTxn read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return MonthlyTxn(
      id: fields[0] as String,
      monthKey: fields[1] as String,
      categoryId: fields[2] as String,
      amount: fields[3] as double,
      currency: fields[4] as String,
      note: fields[5] as String,
      date: fields[6] as DateTime,
      type: fields[7] as String,
    );
  }

  @override
  void write(BinaryWriter writer, MonthlyTxn obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.monthKey)
      ..writeByte(2)
      ..write(obj.categoryId)
      ..writeByte(3)
      ..write(obj.amount)
      ..writeByte(4)
      ..write(obj.currency)
      ..writeByte(5)
      ..write(obj.note)
      ..writeByte(6)
      ..write(obj.date)
      ..writeByte(7)
      ..write(obj.type);
  }
}
