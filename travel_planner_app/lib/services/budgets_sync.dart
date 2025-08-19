// 👇 NEW: Budgets sync bus (singleton)
// BudgetsSync class start
import 'package:flutter/foundation.dart';

class BudgetsSync extends ChangeNotifier {
  BudgetsSync._();
  static final BudgetsSync instance = BudgetsSync._();
  void bump() => notifyListeners();
}
// BudgetsSync class end
