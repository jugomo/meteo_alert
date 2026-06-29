import '../data/models/alert.dart';
import '../data/repositories/weather_repository.dart';
import 'notification_service.dart';

class AlertChecker {
  static final _weatherRepo = WeatherRepository();

  static Future<void> checkAndNotify(List<Alert> alerts) async {
    try {
      await Future.wait([
        for (int i = 0; i < alerts.length; i++) _check(i, alerts[i]),
      ]);
    } catch (_) {}
  }

  static Future<void> _check(int id, Alert alert) async {
    if (alert.latitude == null || alert.longitude == null) return;
    try {
      final now = DateTime.now();
      final windowStart = DateTime(now.year, now.month, now.day, now.hour);
      final windowEnd = now.add(const Duration(hours: 1));

      final exceeded = await _weatherRepo.fetchExceeded(alert);
      final upcoming = exceeded
          .where((h) =>
              !h.time.isBefore(windowStart) && !h.time.isAfter(windowEnd))
          .toList();

      if (upcoming.isEmpty) return;

      final parts = <String>[];
      if (upcoming.any((h) => h.temperature != null)) {
        parts.add('Temperatura: >${alert.temperature.toStringAsFixed(0)}°C');
      }
      if (upcoming.any((h) => h.wind != null)) {
        parts.add('Viento: >${alert.wind.toStringAsFixed(0)} km/h');
      }
      if (upcoming.any((h) => h.rain != null)) {
        parts.add(
            'Prob. lluvia: >${alert.rainProbability.toStringAsFixed(0)}%');
      }

      if (parts.isNotEmpty) {
        await NotificationService.show(
          id: id,
          title: alert.city,
          body: parts.join('\n'),
        );
      }
    } catch (_) {}
  }
}
