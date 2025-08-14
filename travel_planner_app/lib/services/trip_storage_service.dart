import 'package:shared_preferences/shared_preferences.dart';

class TripStorageService {
  static const String _selectedTripIdKey = 'selected_trip_id';
  static const String _selectedTripNameKey = 'selected_trip_name';

  static Future<String?> getSelectedTripId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedTripIdKey);
  }

  static Future<String?> getSelectedTripName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedTripNameKey);
  }

  static Future<void> setSelectedTrip(String tripId, String tripName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedTripIdKey, tripId);
    await prefs.setString(_selectedTripNameKey, tripName);
  }

  static Future<void> clearSelectedTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedTripIdKey);
    await prefs.remove(_selectedTripNameKey);
  }

  static Future<bool> hasSelectedTrip() async {
    final tripId = await getSelectedTripId();
    return tripId != null && tripId.isNotEmpty;
  }
}
