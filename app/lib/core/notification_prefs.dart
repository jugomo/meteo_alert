import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPrefsNotifier {
  static const _localKey = 'local_notifications_enabled';
  static const _pushKey = 'push_notifications_enabled';

  final local = ValueNotifier<bool>(true);
  final push = ValueNotifier<bool>(true);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    local.value = prefs.getBool(_localKey) ?? true;
    push.value = prefs.getBool(_pushKey) ?? true;
  }

  Future<void> setLocal(bool value) async {
    local.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localKey, value);
  }

  Future<void> setPush(bool value) async {
    push.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pushKey, value);
  }
}

final notificationPrefs = NotificationPrefsNotifier();
