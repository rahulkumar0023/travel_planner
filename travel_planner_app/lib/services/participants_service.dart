import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ParticipantsService {
  static String _key(String tripId) => 'participants_$tripId';

  static Future<List<String>> get(String tripId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(tripId));
    if (raw == null) return const ['You']; // default
    final list = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    return list.isEmpty ? const ['You'] : list;
  }

  static Future<void> save(String tripId, List<String> names) async {
    final sp = await SharedPreferences.getInstance();
    final cleaned =
        names.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    await sp.setString(_key(tripId), jsonEncode(cleaned));
  }

  static Future<void> add(String tripId, String name) async {
    final list = await get(tripId);
    list.add(name);
    await save(tripId, list);
  }

  static Future<void> remove(String tripId, String name) async {
    final list = await get(tripId);
    list.removeWhere((n) => n.toLowerCase() == name.toLowerCase());
    await save(tripId, list);
  }
}
