import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ParticipantsService {
  static String _key(String tripId) => 'participants_$tripId';

  // Always return a growable (modifiable) list
  static Future<List<String>> get(String tripId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(tripId));
    if (raw == null) {
      // return growable default list (NOT const)
      return <String>['You'];
    }
    final decoded = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    // ensure growable even if JSON decoder returns a fixed-length list
    return List<String>.from(decoded, growable: true).isEmpty
        ? <String>['You']
        : List<String>.from(decoded, growable: true);
  }

  static Future<void> save(String tripId, List<String> names) async {
    final sp = await SharedPreferences.getInstance();
    final cleaned = names
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(); // growable by default
    await sp.setString(_key(tripId), jsonEncode(cleaned));
  }

  static Future<void> add(String tripId, String name) async {
    final current = await get(tripId);
    final next = List<String>.from(current, growable: true)..add(name);
    await save(tripId, next);
  }

  static Future<void> remove(String tripId, String name) async {
    final current = await get(tripId);
    final next = List<String>.from(current, growable: true)
      ..removeWhere((n) => n.toLowerCase() == name.toLowerCase());
    await save(tripId, next);
  }
}
