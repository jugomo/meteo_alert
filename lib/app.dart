import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core/theme_notifier.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/home_screen.dart';

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
              return HomeScreen(uid: user.uid);
            },
          ),
        );
      },
    );
  }
}
