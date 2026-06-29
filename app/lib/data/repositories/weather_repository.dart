import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/countries.dart';
import '../models/alert.dart';
import '../models/city_suggestion.dart';
import '../models/forecast_hour.dart';

class WeatherRepository {
  Future<List<ForecastHour>> fetchExceeded(Alert alert) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=${alert.latitude}'
      '&longitude=${alert.longitude}'
      '&hourly=temperature_2m,precipitation_probability,windspeed_10m'
      '&forecast_days=${alert.forecastDays}'
      '&timezone=auto',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) throw Exception('Error del servidor');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final hourly = data['hourly'] as Map<String, dynamic>;
    final times = (hourly['time'] as List).cast<String>();
    final temps = (hourly['temperature_2m'] as List).cast<num>();
    final winds = (hourly['windspeed_10m'] as List).cast<num>();
    final rains = (hourly['precipitation_probability'] as List)
        .map((e) => (e as num?)?.toDouble())
        .toList();

    final exceeded = <ForecastHour>[];
    for (int i = 0; i < times.length; i++) {
      final t = temps[i].toDouble();
      final w = winds[i].toDouble();
      final r = rains[i] ?? 0.0;

      final tOver = alert.temperatureEnabled && t > alert.temperature;
      final wOver = alert.windEnabled && w > alert.wind;
      final rOver = alert.rainEnabled && r > alert.rainProbability;

      if (tOver || wOver || rOver) {
        exceeded.add(ForecastHour(
          time: DateTime.parse(times[i]),
          temperature: tOver ? t : null,
          wind: wOver ? w : null,
          rain: rOver ? r : null,
        ));
      }
    }
    return exceeded;
  }

  Future<List<CitySuggestion>> fetchSuggestions(
    String query,
    String? country, {
    int count = 5,
  }) async {
    final code = countryCode[country];
    final countryParam = code != null ? '&countryCode=$code' : '';
    final uri = Uri.parse(
      'https://geocoding-api.open-meteo.com/v1/search'
      '?name=${Uri.encodeComponent(query)}&count=$count&language=es&format=json$countryParam',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>?) ?? [];
    return results
        .map((r) => CitySuggestion(
              name: r['name'] as String,
              latitude: (r['latitude'] as num).toDouble(),
              longitude: (r['longitude'] as num).toDouble(),
            ))
        .toList();
  }

  Future<(double, double)?> geocodeCity(String city, String? country) async {
    final suggestions = await fetchSuggestions(city, country, count: 1);
    if (suggestions.isEmpty) return null;
    return (suggestions.first.latitude, suggestions.first.longitude);
  }
}
