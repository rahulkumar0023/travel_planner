// last_used_store.dart start
import 'package:shared_preferences/shared_preferences.dart';

class LastUsedStore {
  static String _key(String tripId) => 'last_expense_ccy_$tripId';

  // 👇 NEW: read last selected expense currency for a trip
  static Future<String?> getExpenseCurrencyForTrip(String tripId) async {
    if (tripId.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    return p.getString(_key(tripId));
  }

  // 👇 NEW: save last selected expense currency for a trip
  static Future<void> setExpenseCurrencyForTrip(String tripId, String currency) async {
    if (tripId.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(tripId), currency.toUpperCase());
  }
}
// last_used_store.dart end
