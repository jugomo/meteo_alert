import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/aemet_config.dart';
import '../models/alert.dart';
import '../models/forecast_hour.dart';

/// Fetches hourly forecasts from AEMET OpenData for a given municipio (INE
/// code). Unlike Open-Meteo, AEMET requests are resolved in two steps: the
/// first call (authenticated with an api_key header) returns a short-lived
/// `datos` URL, which is then fetched to get the actual forecast payload
/// (encoded as ISO-8859-15).
class AemetWeatherRepository {
  static const _base = 'https://opendata.aemet.es/opendata/api';

  Future<List<ForecastHour>> fetchExceeded(Alert alert) async {
    final municipioId = alert.aemetMunicipioId;
    final apiKey = AemetConfig.apiKey;
    if (municipioId == null || apiKey == null) {
      throw Exception('AEMET no disponible');
    }

    final metaResponse = await http.get(
      Uri.parse('$_base/prediccion/especifica/municipio/horaria/$municipioId'),
      headers: {'api_key': apiKey},
    );
    if (metaResponse.statusCode != 200) throw Exception('Error del servidor');
    final meta = jsonDecode(metaResponse.body) as Map<String, dynamic>;
    final dataUrl = meta['datos'] as String?;
    if (dataUrl == null) throw Exception('Error del servidor');

    final dataResponse = await http.get(Uri.parse(dataUrl));
    if (dataResponse.statusCode != 200) throw Exception('Error del servidor');
    final decoded = latin1.decode(dataResponse.bodyBytes);
    final list = jsonDecode(decoded) as List<dynamic>;
    if (list.isEmpty) return [];

    final prediccion = (list.first as Map<String, dynamic>)['prediccion'] as Map<String, dynamic>;
    final dias = (prediccion['dia'] as List).cast<Map<String, dynamic>>();

    final exceeded = <ForecastHour>[];
    for (final dia in dias.take(alert.forecastDays)) {
      final date = DateTime.parse(dia['fecha'] as String);

      final tempByHour = <int, double>{};
      for (final t in (dia['temperatura'] as List? ?? const [])) {
        final hour = int.tryParse(t['periodo'] as String? ?? '');
        final value = double.tryParse(t['value'] as String? ?? '');
        if (hour != null && value != null) tempByHour[hour] = value;
      }

      final windByHour = <int, double>{};
      for (final w in (dia['vientoAndRachaMax'] as List? ?? const [])) {
        if (w is! Map || !w.containsKey('velocidad')) continue;
        final hour = int.tryParse(w['periodo'] as String? ?? '');
        final velocidad = (w['velocidad'] as List?)?.cast<String>();
        final value = velocidad != null && velocidad.isNotEmpty ? double.tryParse(velocidad.first) : null;
        if (hour != null && value != null) windByHour[hour] = value;
      }

      final rainBlocks = <(int, int, double)>[];
      for (final p in (dia['probPrecipitacion'] as List? ?? const [])) {
        final periodo = p['periodo'] as String?;
        final value = double.tryParse(p['value'] as String? ?? '');
        if (periodo != null && periodo.length == 4 && value != null) {
          rainBlocks.add((int.parse(periodo.substring(0, 2)), int.parse(periodo.substring(2, 4)), value));
        }
      }

      for (final hour in tempByHour.keys.toList()..sort()) {
        final t = tempByHour[hour]!;
        final w = windByHour[hour] ?? 0.0;
        final r = _rainForHour(rainBlocks, hour) ?? 0.0;

        final tOver = alert.temperatureEnabled && t > alert.temperature;
        final wOver = alert.windEnabled && w > alert.wind;
        final rOver = alert.rainEnabled && r > alert.rainProbability;

        if (tOver || wOver || rOver) {
          exceeded.add(ForecastHour(
            time: DateTime(date.year, date.month, date.day, hour),
            temperature: tOver ? t : null,
            wind: wOver ? w : null,
            rain: rOver ? r : null,
          ));
        }
      }
    }
    return exceeded;
  }

  double? _rainForHour(List<(int, int, double)> blocks, int hour) {
    for (final (start, end, value) in blocks) {
      final inRange = end > start ? (hour >= start && hour < end) : (hour >= start || hour < end);
      if (inRange) return value;
    }
    return null;
  }
}
