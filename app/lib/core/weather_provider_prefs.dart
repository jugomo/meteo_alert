import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/alert.dart';

class WeatherProviderPrefsNotifier {
  static const _key = 'weather_provider';

  final provider = ValueNotifier<WeatherProvider>(WeatherProvider.openMeteo);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    provider.value = WeatherProvider.fromId(prefs.getString(_key));
  }

  Future<void> setProvider(WeatherProvider value) async {
    provider.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.id);
  }
}

final weatherProviderPrefs = WeatherProviderPrefsNotifier();
