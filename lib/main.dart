import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/notification_service.dart';
import 'core/theme_notifier.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://meteo-alert-409a8-default-rtdb.europe-west1.firebasedatabase.app',
    ).setPersistenceEnabled(true);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  await themeNotifier.init();
  await NotificationService.init();
  runApp(const MeteoAlertApp());
}
