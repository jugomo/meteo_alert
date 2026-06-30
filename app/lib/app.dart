import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'core/notification_prefs.dart';
import 'core/theme_notifier.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/home_screen.dart';

const _dbUrl =
    'https://meteo-alert-409a8-default-rtdb.europe-west1.firebasedatabase.app';

Future<void> _saveFcmToken(String uid) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: _dbUrl,
    ).ref('users/$uid/fcmToken').set(token);
  } catch (_) {}
}

class MeteoAlertApp extends StatelessWidget {
  const MeteoAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Meteo Alert',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: mode,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final user = snapshot.data;
              if (user == null) return const AuthScreen();
              if (notificationPrefs.push.value) _saveFcmToken(user.uid);
              return HomeScreen(uid: user.uid);
            },
          ),
        );
      },
    );
  }
}
