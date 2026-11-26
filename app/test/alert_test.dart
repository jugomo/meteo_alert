import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meteo_alert/data/models/alert.dart';

void main() {
  test('legacy alert JSON gets default notification settings', () {
    final a = Alert.fromJson({
      'country': 'España',
      'city': 'Madrid',
      'forecastDays': 7,
      'wind': 10,
      'temperature': 25,
      'rainProbability': 50,
    });
    expect(a.id, isNull);
    expect(a.leadHours, 0);
    expect(a.digestEnabled, isFalse);
    expect(a.digestHour, 8);
    expect(a.temperatureDirection, ThresholdDirection.above);
    expect(a.toJson().containsKey('id'), isFalse);
  });

  test('notification settings survive a JSON round trip', () {
    final a = Alert(
      id: Alert.newId(),
      country: 'España',
      city: 'Madrid',
      forecastDays: 7,
      wind: 10,
      temperature: 25,
      rainProbability: 50,
      leadHours: 6,
      digestEnabled: true,
      digestHour: 21,
    );
    final b = Alert.fromJson(a.toJson());
    expect(b.id, a.id);
    expect(b.leadHours, 6);
    expect(b.digestEnabled, isTrue);
    expect(b.digestHour, 21);
  });

  test('temperature direction survives a JSON round trip and is applied', () {
    final a = Alert(
      country: 'España',
      city: 'Madrid',
      forecastDays: 7,
      wind: 10,
      temperature: 0,
      temperatureDirection: ThresholdDirection.below,
      rainProbability: 50,
    );
    final b = Alert.fromJson(a.toJson());
    expect(b.temperatureDirection, ThresholdDirection.below);
    expect(b.temperatureLabel, '<0°C');
    expect(b.temperatureCrossed(-2), isTrue);
    expect(b.temperatureCrossed(3), isFalse);
  });

  test('newId generates distinct ids', () {
    expect(Alert.newId(), isNot(Alert.newId()));
  });

  test('maxPerUser matches MAX_ALERTS_PER_USER in the Lambda', () {
    final source = File('../lambda/index.py').readAsStringSync();
    final match = RegExp(r'^MAX_ALERTS_PER_USER = (\d+)', multiLine: true)
        .firstMatch(source);
    expect(match, isNotNull);
    expect(int.parse(match!.group(1)!), Alert.maxPerUser);
  });
}
