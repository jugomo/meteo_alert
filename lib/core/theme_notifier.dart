import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ValueNotifier<ThemeMode> {
  static const _key = 'dark_mode';

  ThemeNotifier() : super(ThemeMode.system);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_key);
    if (isDark != null) {
      value = isDark ? ThemeMode.dark : ThemeMode.light;
    }
  }

  bool get isDark => value == ThemeMode.dark;

  Future<void> toggle() async {
    final nowDark = !isDark;
    value = nowDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, nowDark);
  }
}

final themeNotifier = ThemeNotifier();
