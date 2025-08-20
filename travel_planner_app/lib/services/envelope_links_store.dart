import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class EnvelopeLinksStore {
  // key is month; value is { tripBudgetId: envelopeId }
  static String _key(DateTime month) {
    final y = month.year;
    final m = month.month.toString().padLeft(2, '0');
    return 'envelope_links_${y}_$m';
  }

  static Future<Map<String, String>> load(DateTime month) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key(month));
    if (s == null || s.isEmpty) return <String, String>{};
    try {
      final raw = Map<String, dynamic>.from(jsonDecode(s));
      return raw.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<void> save(DateTime month, Map<String, String> map) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(month), jsonEncode(map));
  }

  static Future<void> setLink(DateTime month, {required String tripBudgetId, required String envelopeId}) async {
    final m = await load(month);
    m[tripBudgetId] = envelopeId;
    await save(month, m);
  }

  static Future<void> unlink(DateTime month, String tripBudgetId) async {
    final m = await load(month);
    m.remove(tripBudgetId);
    await save(month, m);
  }
}

