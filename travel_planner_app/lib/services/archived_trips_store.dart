import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ArchivedTripsStore {
  static const _k = 'archived_trip_ids_v1';

  static Future<Set<String>> _load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_k);
    if (s == null || s.isEmpty) return <String>{};
    try { return (List<String>.from(jsonDecode(s))).toSet(); } catch (_) { return <String>{}; }
  }

  static Future<void> _save(Set<String> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(ids.toList()));
  }

  static Future<bool> isArchived(String id) async => (await _load()).contains(id);

  static Future<void> archive(String id) async {
    final s = await _load(); s.add(id); await _save(s);
  }

  static Future<void> unarchive(String id) async {
    final s = await _load(); s.remove(id); await _save(s);
  }

  static Future<Set<String>> all() => _load();
}
