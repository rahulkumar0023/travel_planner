// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monthly_category.dart';

class MonthlyCategoryAdapter extends TypeAdapter<MonthlyCategory> {
  @override
  final int typeId = 41;

  @override
  MonthlyCategory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return MonthlyCategory(
      id: fields[0] as String,
      name: fields[1] as String,
      monthKey: fields[2] as String,
      type: fields[3] as String,
      parentId: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MonthlyCategory obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.monthKey)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.parentId);
  }
}
