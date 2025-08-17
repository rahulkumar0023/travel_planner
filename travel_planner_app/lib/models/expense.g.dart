// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  final int typeId = 0;

  @override
  Expense read(BinaryReader reader) {
    // inside ExpenseAdapter.read(...)
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

// helpers
    String _s(dynamic v, [String d = '']) => (v as String?) ?? d;
    List<String> _ls(dynamic v) => v is List ? v.cast<String>() : const <String>[];

    return Expense(
      id: _s(fields[0]),
      tripId: _s(fields[1]),
      title: _s(fields[2]),
      amount: (fields[3] as num?)?.toDouble() ?? 0.0,
      category: _s(fields[4]),
      date: (fields[5] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0),
      paidBy: _s(fields[6]),
      sharedWith: _ls(fields[7]),
      currency: _s(fields[8]),
    );
  }

  @override
  void write(BinaryWriter writer, Expense obj) {
    writer
      ..writeByte(9) // must be 9
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.tripId)
      ..writeByte(2)..write(obj.title)
      ..writeByte(3)..write(obj.amount)
      ..writeByte(4)..write(obj.category)
      ..writeByte(5)..write(obj.date)
      ..writeByte(6)..write(obj.paidBy)
      ..writeByte(7)..write(obj.sharedWith)
      ..writeByte(8)..write(obj.currency);

  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
