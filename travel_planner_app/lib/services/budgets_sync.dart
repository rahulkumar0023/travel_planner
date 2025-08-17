// budgets_sync.dart start
import 'package:flutter/foundation.dart';

/// Fire-and-forget notifier. Call [BudgetsSync.bump()] after any
/// create/edit/delete/link/unlink on budgets. Listeners (e.g. Dashboard)
/// can refresh their view when this changes.
class BudgetsSync {
  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static void bump() => version.value++;
}
// budgets_sync.dart end
