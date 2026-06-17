class ForecastHour {
  final DateTime time;
  final double? temperature;
  final double? wind;
  final double? rain;

  const ForecastHour({
    required this.time,
    this.temperature,
    this.wind,
    this.rain,
  });
}
