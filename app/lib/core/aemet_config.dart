import 'package:flutter/services.dart' show rootBundle;

/// Loads the AEMET OpenData API key from `assets/aemet_key.txt`.
///
/// That file is gitignored: it only exists on machines/builds where a
/// developer has placed a real key. When it's missing, [isAvailable] stays
/// false and the AEMET provider is disabled everywhere in the app.
class AemetConfig {
  static String? _apiKey;

  static Future<void> load() async {
    try {
      final key = (await rootBundle.loadString('assets/aemet_key.txt')).trim();
      _apiKey = key.isEmpty ? null : key;
    } catch (_) {
      _apiKey = null;
    }
  }

  static String? get apiKey => _apiKey;
  static bool get isAvailable => _apiKey != null;
}
