import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/alert.dart';

class AlertRepository {
  static const _dbUrl =
      'https://meteo-alert-409a8-default-rtdb.europe-west1.firebasedatabase.app';

  DatabaseReference _ref(String uid) => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _dbUrl,
      ).ref('users/$uid/alertsJson');

  Future<List<Alert>> load(String uid) async {
    final snapshot = await _ref(uid).get();
    if (!snapshot.exists || snapshot.value == null) return [];
    final list = jsonDecode(snapshot.value as String) as List<dynamic>;
    return list
        .map((m) => Alert.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(String uid, List<Alert> alerts) async {
    await _ref(uid).set(
      jsonEncode(alerts.map((a) => a.toJson()).toList()),
    );
  }
}
