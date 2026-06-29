import 'dart:js_interop';

import 'package:web/web.dart' as web;

class NotificationService {
  static Future<void> init() async {
    await web.Notification.requestPermission().toDart;
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (web.Notification.permission == 'granted') {
      web.Notification(title, web.NotificationOptions(body: body));
    }
  }
}
