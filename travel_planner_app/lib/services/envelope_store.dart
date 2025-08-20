import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/envelope.dart';

class EnvelopeStore {
  static String _key(DateTime month) {
    final y = month.year;
    final m = month.month.toString().padLeft(2, '0');
    return 'envelopes_${y}_$m';
  }

  // Load the envelope definitions for a month
  static Future<List<EnvelopeDef>> load(DateTime month) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key(month));
    if (s == null || s.isEmpty) return <EnvelopeDef>[];
    try {
      final raw = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return raw.map(EnvelopeDef.fromJson).toList();
    } catch (_) {
      return <EnvelopeDef>[];
    }
  }

  // Save/replace the list for a month
  static Future<void> save(DateTime month, List<EnvelopeDef> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key(month),
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  // Helpers
  static Future<void> upsert(DateTime month, EnvelopeDef def) async {
    final list = await load(month);
    final next = [
      ...list.where((e) => e.id != def.id),
      def,
    ];
    await save(month, next);
  }

  static Future<void> remove(DateTime month, String id) async {
    final list = await load(month);
    await save(month, list.where((e) => e.id != id).toList());
  }
}

