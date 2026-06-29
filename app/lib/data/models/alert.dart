class Alert {
  final String country;
  final String city;
  final int forecastDays;
  final double wind;
  final double temperature;
  final double rainProbability;
  final double? latitude;
  final double? longitude;
  final bool windEnabled;
  final bool temperatureEnabled;
  final bool rainEnabled;

  const Alert({
    required this.country,
    required this.city,
    required this.forecastDays,
    required this.wind,
    required this.temperature,
    required this.rainProbability,
    this.latitude,
    this.longitude,
    this.windEnabled = true,
    this.temperatureEnabled = true,
    this.rainEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'country': country,
        'city': city,
        'forecastDays': forecastDays,
        'wind': wind,
        'temperature': temperature,
        'rainProbability': rainProbability,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'windEnabled': windEnabled,
        'temperatureEnabled': temperatureEnabled,
        'rainEnabled': rainEnabled,
      };

  factory Alert.fromJson(Map<String, dynamic> j) => Alert(
        country: j['country'] as String,
        city: j['city'] as String,
        forecastDays: j['forecastDays'] as int,
        wind: (j['wind'] as num).toDouble(),
        temperature: (j['temperature'] as num).toDouble(),
        rainProbability: (j['rainProbability'] as num).toDouble(),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        windEnabled: (j['windEnabled'] as bool?) ?? true,
        temperatureEnabled: (j['temperatureEnabled'] as bool?) ?? true,
        rainEnabled: (j['rainEnabled'] as bool?) ?? true,
      );
}
