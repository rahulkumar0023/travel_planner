import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip.dart';
import 'local_trip_store.dart'; // + so we can read all cached trips

class TripStorageService {
  static late SharedPreferences _prefs;
  static const _keyId = 'activeTripId';
  static const _keyName = 'activeTripName';
  static const _keyCurrency = 'activeTripCurrency';
  static const _keyHomeCurrency = 'homeCurrency';

  static Future<void> setHomeCurrency(String code) async {
    await _prefs.setString(_keyHomeCurrency, code.toUpperCase());
  }

  static String getHomeCurrency({String fallback = 'EUR'}) {
    return _prefs.getString(_keyHomeCurrency) ?? fallback;
  }

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> save(Trip trip) async {
    await _prefs.setString(_keyId, trip.id);
    await _prefs.setString(_keyName, trip.name);
    await _prefs.setString(_keyCurrency, trip.currency);
  }

  // TripStorageService.loadAll method start
  /// Load all locally cached trips (used by data migrations/backfills).
  /// Returns [] if none are cached.
  static Future<List<Trip>> loadAll() async {
    try {
      return await LocalTripStore.load();
    } catch (_) {
      return <Trip>[];
    }
  }
// TripStorageService.loadAll method end

  // TripStorageService clear helpers start
  static Future<void> clear() async {
    // whatever you used in save(), remove it here
    // e.g., SharedPreferences:
    final p = await SharedPreferences.getInstance();
    await p.remove('active_trip_json');    // <-- match your existing key
    await p.remove('active_trip_id');      // if you store id separately
  }

  /// Clear only if the currently saved trip id matches [tripId]
  static Future<void> clearIf(String tripId) async {
    final active = loadLightweight();
    if (active != null && active.id == tripId) {
      await clear();
    }
  }
// TripStorageService clear helpers end


  static Trip? loadLightweight() {
    final id = _prefs.getString(_keyId);
    final name = _prefs.getString(_keyName);
    final currency = _prefs.getString(_keyCurrency);
    if (id == null || name == null || currency == null) return null;
    return Trip(
      id: id,
      name: name,
      startDate: DateTime.now(),
      endDate: DateTime.now(),
      initialBudget: 0,
      currency: currency,
      participants: const [],
    );
  }

  // static Future<void> clear() async {
  //   await _prefs.remove(_keyId);
  //   await _prefs.remove(_keyName);
  //   await _prefs.remove(_keyCurrency);
  // }
}
