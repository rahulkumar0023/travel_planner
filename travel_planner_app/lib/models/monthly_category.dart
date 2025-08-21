// ===== monthly_category.dart — START =====
// Description: Hive model for Monthly Category. Supports sub-categories via parentId.
// TypeId: pick a free one; keep unique across your app. Example: 41.

import 'package:hive/hive.dart';

part 'monthly_category.g.dart';

@HiveType(typeId: 41) // 👈 NEW: ensure this does not clash with existing adapters
class MonthlyCategory extends HiveObject {
  @HiveField(0)
  String id; // uuid

  @HiveField(1)
  String name;

  @HiveField(2)
  String monthKey; // 'YYYY-MM' e.g., '2025-08'

  @HiveField(3)
  String type; // 'income' | 'expense'

  @HiveField(4)
  String? parentId; // if set => sub-category of that category

  MonthlyCategory({
    required this.id,
    required this.name,
    required this.monthKey,
    required this.type,
    this.parentId,
  });

  bool get isSub => parentId != null;
}
// ===== monthly_category.dart — END =====
