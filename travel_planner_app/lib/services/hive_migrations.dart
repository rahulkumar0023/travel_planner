import 'package:hive/hive.dart';
import '../models/expense.dart';
import '../models/trip.dart';
import '../services/trip_storage_service.dart'; // if you have local trips
// If you don't keep local trips per id, pick a constant like 'EUR'.

class HiveMigrations {
  static Future<void> backfillExpenseCurrency() async {
    final box = Hive.box<Expense>('expensesBox');
    // Optional: have a map of tripId -> currency if you cache trips
    final Map<String, String> tripCurrency = <String, String>{};
    try {
      final trips = await TripStorageService.loadAll(); // or LocalTripStore.load()
      for (final t in trips) {
        tripCurrency[t.id] = t.currency;
      }
    } catch (_) {/* ignore if not available */}

    for (final key in box.keys) {
      final e = box.get(key) as Expense?;
      if (e == null) continue;
      if (e.currency == '' || e.currency == 'null' || e.currency == null) {
        final ccy = tripCurrency[e.tripId] ?? 'EUR';
        e.currency = ccy;
        await e.save();
      }
    }
  }
}
