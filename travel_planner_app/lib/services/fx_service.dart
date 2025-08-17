import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FxService {
  static String _key(String base) => 'fx_rates_$base';

  // Save rates as: { 'TRY': 35.0, 'INR': 92.0 } meaning 1 base = rate * quote.
  static Future<void> saveRates(String base, Map<String, double> rates) async {
    final p = await SharedPreferences.getInstance();
    final map = rates.map((k, v) => MapEntry(k.toUpperCase(), v));
    await p.setString(_key(base.toUpperCase()), jsonEncode(map));
  }

  static Future<Map<String, double>> loadRates(String base) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key(base.toUpperCase()));
    if (s == null || s.isEmpty) return {};
    final raw = Map<String, dynamic>.from(jsonDecode(s));
    return raw.map((k, v) => MapEntry(k.toUpperCase(), (v as num).toDouble()));
  }

  // Convert amount from -> to using 'to' as base's table
  // If base == to, rates should contain entries for 'from' (or identity if same).
  static double convert({
    required double amount,
    required String from,
    required String to,
    required Map<String, double> ratesForBaseTo,
  }) {
    final f = from.toUpperCase();
    final t = to.toUpperCase();
    if (f == t) return amount;

    // ratesForBaseTo are relative to base 'to': 1 to = rate[to->quote] ??? We store 1 'to' = r[QUOTE].
    // To convert from 'from' -> 'to':
    // if from == to: amount
    // if from is quoted as r[from], then 1 to = r[from] from => 1 from = 1/r[from] to
    // amount_from -> to = amount_from * (1 / r[from])
    final rFrom = ratesForBaseTo[f];
    if (rFrom == null || rFrom == 0) {
      // Fallback: treat as identity if unknown rate
      return amount;
    }
    return amount * (1.0 / rFrom);
  }
}
