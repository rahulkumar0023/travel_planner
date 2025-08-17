import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip.dart';

class LocalTripStore {
  static const _k = 'cached_trips_v1';
  static Future<void> save(List<Trip> trips) async {
    final p = await SharedPreferences.getInstance();
    final list = trips.map((t) => t.toJson()).toList();
    await p.setString(_k, jsonEncode(list));
  }
  static Future<List<Trip>> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_k);
    if (s == null || s.isEmpty) return <Trip>[];
    try {
      final raw = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return raw.map(Trip.fromJson).toList();
    } catch (_) {
      return <Trip>[];
    }
  }
}