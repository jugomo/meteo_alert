class CitySuggestion {
  final String name;
  final double latitude;
  final double longitude;

  /// AEMET municipio id (INE code), only set for suggestions coming from the
  /// AEMET municipios catalog.
  final String? aemetMunicipioId;

  const CitySuggestion({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.aemetMunicipioId,
  });
}
