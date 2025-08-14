import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const _kHomeCurrency = 'home_currency';

  static Future<void> setHomeCurrency(String code) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHomeCurrency, code);
  }

  static Future<String> getHomeCurrency() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kHomeCurrency) ?? 'EUR';
  }
}
