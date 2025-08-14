import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip.dart';

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

  static Future<void> clear() async {
    await _prefs.remove(_keyId);
    await _prefs.remove(_keyName);
    await _prefs.remove(_keyCurrency);
  }
}
