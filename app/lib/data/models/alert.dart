import 'dart:math';

enum WeatherProvider {
  openMeteo,
  aemet;

  String get id => this == WeatherProvider.aemet ? 'aemet' : 'openMeteo';

  String get label =>
      this == WeatherProvider.aemet ? 'AEMET OpenData' : 'Open-Meteo';

  static WeatherProvider fromId(String? id) =>
      id == 'aemet' ? WeatherProvider.aemet : WeatherProvider.openMeteo;
}

/// Whether a threshold is crossed when the value goes above or below it.
enum ThresholdDirection {
  above,
  below;

  String get id => name;

  String get symbol => this == ThresholdDirection.below ? '<' : '>';

  String get label => this == ThresholdDirection.below ? 'Por debajo' : 'Por encima';

  bool isCrossed(double value, double threshold) =>
      this == ThresholdDirection.below ? value < threshold : value > threshold;

  static ThresholdDirection fromId(String? id) =>
      id == 'below' ? ThresholdDirection.below : ThresholdDirection.above;
}

class Alert {
  /// Maximum alerts per user. Must match MAX_ALERTS_PER_USER in lambda/index.py,
  /// which ignores any alert beyond this count.
  static const maxPerUser = 20;

  /// Hour options offered for lead time, in hours (0 = only the current hour).
  static const leadHourOptions = [0, 1, 3, 6, 12, 24];

  /// Stable identifier used by the backend to track which episodes were already
  /// notified. Null for alerts created before ids existed.
  final String? id;
  final String country;
  final String city;
  final int forecastDays;
  final double wind;
  final double temperature;
  final ThresholdDirection temperatureDirection;
  final double rainProbability;
  final double? latitude;
  final double? longitude;
  final bool windEnabled;
  final bool temperatureEnabled;
  final bool rainEnabled;
  final WeatherProvider provider;
  final String? aemetMunicipioId;

  /// Notify when thresholds will be exceeded within the next [leadHours] hours.
  final int leadHours;

  /// Send a daily summary of the next 24 h at [digestHour] (local time of the city).
  final bool digestEnabled;
  final int digestHour;

  const Alert({
    this.id,
    required this.country,
    required this.city,
    required this.forecastDays,
    required this.wind,
    required this.temperature,
    this.temperatureDirection = ThresholdDirection.above,
    required this.rainProbability,
    this.latitude,
    this.longitude,
    this.windEnabled = true,
    this.temperatureEnabled = true,
    this.rainEnabled = true,
    this.provider = WeatherProvider.openMeteo,
    this.aemetMunicipioId,
    this.leadHours = 0,
    this.digestEnabled = false,
    this.digestHour = 8,
  });

  bool temperatureCrossed(double t) =>
      temperatureEnabled && temperatureDirection.isCrossed(t, temperature);

  String get temperatureLabel =>
      '${temperatureDirection.symbol}${temperature.toStringAsFixed(0)}°C';

  static String newId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = Random().nextInt(0xFFFFFFFF).toRadixString(36);
    return '$now$rnd';
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'country': country,
        'city': city,
        'forecastDays': forecastDays,
        'wind': wind,
        'temperature': temperature,
        'temperatureDirection': temperatureDirection.id,
        'rainProbability': rainProbability,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'windEnabled': windEnabled,
        'temperatureEnabled': temperatureEnabled,
        'rainEnabled': rainEnabled,
        'provider': provider.id,
        if (aemetMunicipioId != null) 'aemetMunicipioId': aemetMunicipioId,
        'leadHours': leadHours,
        'digestEnabled': digestEnabled,
        'digestHour': digestHour,
      };

  factory Alert.fromJson(Map<String, dynamic> j) => Alert(
        id: j['id'] as String?,
        country: j['country'] as String,
        city: j['city'] as String,
        forecastDays: j['forecastDays'] as int,
        wind: (j['wind'] as num).toDouble(),
        temperature: (j['temperature'] as num).toDouble(),
        temperatureDirection:
            ThresholdDirection.fromId(j['temperatureDirection'] as String?),
        rainProbability: (j['rainProbability'] as num).toDouble(),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        windEnabled: (j['windEnabled'] as bool?) ?? true,
        temperatureEnabled: (j['temperatureEnabled'] as bool?) ?? true,
        rainEnabled: (j['rainEnabled'] as bool?) ?? true,
        provider: WeatherProvider.fromId(j['provider'] as String?),
        aemetMunicipioId: j['aemetMunicipioId'] as String?,
        leadHours: (j['leadHours'] as num?)?.toInt() ?? 0,
        digestEnabled: (j['digestEnabled'] as bool?) ?? false,
        digestHour: (j['digestHour'] as num?)?.toInt() ?? 8,
      );
}
