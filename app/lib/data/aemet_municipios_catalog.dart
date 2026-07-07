import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models/city_suggestion.dart';

class _Municipio {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final String normalized;

  _Municipio(this.id, this.name, this.lat, this.lon)
      : normalized = _normalize(name);
}

String _normalize(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑ';
  const to = 'aaaaaeeeeiiiiooooouuuunAAAAAEEEEIIIIOOOOOUUUUN';
  final buffer = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i].toLowerCase() : ch);
  }
  return buffer.toString();
}

/// Local, offline search over the AEMET municipios (INE) catalog bundled as
/// `assets/aemet_municipios.json`. AEMET identifies locations by municipio
/// id rather than free-form geocoding, so city search when AEMET is the
/// selected provider is resolved against this static list instead of a
/// network call.
class AemetMunicipiosCatalog {
  static List<_Municipio>? _all;

  static Future<void> _ensureLoaded() async {
    if (_all != null) return;
    final raw = await rootBundle.loadString('assets/aemet_municipios.json');
    final list = jsonDecode(raw) as List<dynamic>;
    _all = list
        .map((m) => _Municipio(
              m['i'] as String,
              m['n'] as String,
              (m['a'] as num).toDouble(),
              (m['o'] as num).toDouble(),
            ))
        .toList();
  }

  static Future<List<CitySuggestion>> search(String query, {int limit = 5}) async {
    await _ensureLoaded();
    final needle = _normalize(query.trim());
    if (needle.isEmpty) return [];
    final matches = _all!.where((m) => m.normalized.contains(needle)).toList()
      ..sort((a, b) {
        final aStarts = a.normalized.startsWith(needle);
        final bStarts = b.normalized.startsWith(needle);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return matches
        .take(limit)
        .map((m) => CitySuggestion(
              name: m.name,
              latitude: m.lat,
              longitude: m.lon,
              aemetMunicipioId: m.id,
            ))
        .toList();
  }
}
