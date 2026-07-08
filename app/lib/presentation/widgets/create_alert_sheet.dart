import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/aemet_config.dart';
import '../../core/constants/countries.dart';
import '../../core/weather_provider_prefs.dart';
import '../../data/aemet_municipios_catalog.dart';
import '../../data/models/alert.dart';
import '../../data/models/city_suggestion.dart';
import '../../data/repositories/weather_repository.dart';

class CreateAlertSheet extends StatefulWidget {
  final void Function(Alert) onCreated;
  final Alert? initialAlert;

  const CreateAlertSheet({super.key, required this.onCreated, this.initialAlert});

  @override
  State<CreateAlertSheet> createState() => _CreateAlertSheetState();
}

class _CreateAlertSheetState extends State<CreateAlertSheet> {
  final _weatherRepo = WeatherRepository();

  late String? _selectedCountry;
  late final TextEditingController _cityController;
  late double _forecastDays;
  late double _wind;
  late double _temperature;
  late double _rainProbability;
  late bool _windEnabled;
  late bool _temperatureEnabled;
  late bool _rainEnabled;
  late WeatherProvider _provider;

  Timer? _debounceTimer;
  List<CitySuggestion> _suggestions = [];
  bool _loadingSuggestions = false;

  double? _selectedLat;
  double? _selectedLon;
  String? _selectedMunicipioId;
  bool _submitting = false;

  bool get _isAemet => _provider == WeatherProvider.aemet;

  @override
  void initState() {
    super.initState();
    final a = widget.initialAlert;
    _provider = a?.provider ?? weatherProviderPrefs.provider.value;
    _selectedCountry = _isAemet ? 'España' : (a?.country ?? 'España');
    _cityController = TextEditingController(text: a?.city ?? '');
    _forecastDays = (a?.forecastDays ?? 7).toDouble();
    _wind = a?.wind ?? 10;
    _temperature = a?.temperature ?? 25;
    _rainProbability = a?.rainProbability ?? 50;
    _windEnabled = a?.windEnabled ?? true;
    _temperatureEnabled = a?.temperatureEnabled ?? true;
    _rainEnabled = a?.rainEnabled ?? true;
    _selectedLat = a?.latitude;
    _selectedLon = a?.longitude;
    _selectedMunicipioId = a?.aemetMunicipioId;
  }

  void _onProviderChanged(WeatherProvider provider) {
    if (provider == _provider) return;
    weatherProviderPrefs.setProvider(provider);
    setState(() {
      _provider = provider;
      if (_isAemet) _selectedCountry = 'España';
      _selectedLat = null;
      _selectedLon = null;
      _selectedMunicipioId = null;
      _suggestions = [];
    });
  }

  void _onCityChanged(String value) {
    _selectedLat = null;
    _selectedLon = null;
    _selectedMunicipioId = null;
    setState(() => _suggestions = []);
    _debounceTimer?.cancel();
    if (value.trim().length < 2) return;
    _debounceTimer = Timer(
      const Duration(seconds: 2),
      () => _fetchSuggestions(value.trim()),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _loadingSuggestions = true);
    final started = DateTime.now();
    try {
      final results = _isAemet
          ? await AemetMunicipiosCatalog.search(query)
          : await _weatherRepo.fetchSuggestions(query, _selectedCountry);
      // The AEMET catalog is a local, bundled lookup and resolves almost
      // instantly, which would otherwise make the loading bar flash too
      // fast to be visible. Enforce a minimum duration so both providers
      // give the same visual feedback while searching.
      final elapsed = DateTime.now().difference(started);
      const minDuration = Duration(milliseconds: 300);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }
      if (mounted) setState(() => _suggestions = results);
    } catch (_) {
      // silently ignore network errors
    } finally {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedCountry == null || _cityController.text.trim().isEmpty) return;
    setState(() => _submitting = true);

    double? lat = _selectedLat;
    double? lon = _selectedLon;
    String? municipioId = _selectedMunicipioId;

    if (lat == null || lon == null) {
      if (_isAemet) {
        final matches = await AemetMunicipiosCatalog.search(_cityController.text.trim(), limit: 1);
        if (matches.isEmpty) {
          if (mounted) {
            setState(() => _submitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se encontró el municipio. Selecciona una sugerencia.'),
              ),
            );
          }
          return;
        }
        lat = matches.first.latitude;
        lon = matches.first.longitude;
        municipioId = matches.first.aemetMunicipioId;
      } else {
        final coords = await _weatherRepo.geocodeCity(
          _cityController.text.trim(),
          _selectedCountry,
        );
        if (coords == null) {
          if (mounted) {
            setState(() => _submitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se encontró la ciudad. Selecciona una sugerencia.'),
              ),
            );
          }
          return;
        }
        lat = coords.$1;
        lon = coords.$2;
      }
    }

    widget.onCreated(Alert(
      country: _selectedCountry!,
      city: _cityController.text.trim(),
      forecastDays: _forecastDays.round(),
      wind: _wind,
      temperature: _temperature,
      rainProbability: _rainProbability,
      latitude: lat,
      longitude: lon,
      windEnabled: _windEnabled,
      temperatureEnabled: _temperatureEnabled,
      rainEnabled: _rainEnabled,
      provider: _provider,
      aemetMunicipioId: _isAemet ? municipioId : null,
    ));

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.initialAlert == null
                  ? 'Crear nueva alerta meteorológica'
                  : 'Editar alerta meteorológica',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Text(
              'Proveedor meteorológico',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<WeatherProvider>(
              segments: [
                const ButtonSegment(
                  value: WeatherProvider.openMeteo,
                  label: Text('Open-Meteo'),
                ),
                ButtonSegment(
                  value: WeatherProvider.aemet,
                  label: const Text('AEMET OpenData'),
                  enabled: AemetConfig.isAvailable,
                ),
              ],
              selected: {_provider},
              onSelectionChanged: widget.initialAlert == null
                  ? (s) => _onProviderChanged(s.first)
                  : null,
            ),
            if (widget.initialAlert != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'El proveedor no se puede cambiar al editar una alerta.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCountry,
              decoration: const InputDecoration(
                labelText: 'País',
                border: OutlineInputBorder(),
              ),
              items: countries
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: _isAemet ? null : (v) => setState(() => _selectedCountry = v),
            ),
            if (_isAemet)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'AEMET OpenData solo cubre España.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _cityController,
              onChanged: _onCityChanged,
              decoration: const InputDecoration(
                labelText: 'Ciudad',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            if (_loadingSuggestions)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(),
              ),
            if (_suggestions.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 4),
                elevation: 4,
                child: Column(
                  children: _suggestions
                      .map((s) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_city, size: 18),
                            title: Text(s.name),
                            onTap: () {
                              _cityController.text = s.name;
                              _selectedLat = s.latitude;
                              _selectedLon = s.longitude;
                              _selectedMunicipioId = s.aemetMunicipioId;
                              setState(() => _suggestions = []);
                            },
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Duración pronóstico'),
                Text(
                  '${_forecastDays.round()} días',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Slider(
              value: _forecastDays,
              min: 1,
              max: 7,
              divisions: 6,
              label: '${_forecastDays.round()} días',
              onChanged: (v) => setState(() => _forecastDays = v),
            ),
            const SizedBox(height: 8),
            _ThresholdRow(
              enabled: _windEnabled,
              label: 'Viento',
              valueLabel: '${_wind.toStringAsFixed(0)} km/h',
              onToggle: (v) => setState(() => _windEnabled = v ?? true),
            ),
            Slider(
              value: _wind,
              min: 0,
              max: 150,
              divisions: 30,
              label: '${_wind.toStringAsFixed(0)} km/h',
              onChanged: _windEnabled ? (v) => setState(() => _wind = v) : null,
            ),
            const SizedBox(height: 8),
            _ThresholdRow(
              enabled: _temperatureEnabled,
              label: 'Temperatura',
              valueLabel: '${_temperature.toStringAsFixed(0)} ºC',
              onToggle: (v) => setState(() => _temperatureEnabled = v ?? true),
            ),
            Slider(
              value: _temperature,
              min: 0,
              max: 50,
              divisions: 50,
              label: '${_temperature.toStringAsFixed(0)} ºC',
              onChanged: _temperatureEnabled ? (v) => setState(() => _temperature = v) : null,
            ),
            const SizedBox(height: 8),
            _ThresholdRow(
              enabled: _rainEnabled,
              label: 'Probabilidad de lluvia',
              valueLabel: '${_rainProbability.toStringAsFixed(0)} %',
              onToggle: (v) => setState(() => _rainEnabled = v ?? true),
            ),
            Slider(
              value: _rainProbability,
              min: 0,
              max: 100,
              divisions: 20,
              label: '${_rainProbability.toStringAsFixed(0)} %',
              onChanged: _rainEnabled ? (v) => setState(() => _rainProbability = v) : null,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.initialAlert == null ? 'Crear alerta' : 'Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  final bool enabled;
  final String label;
  final String valueLabel;
  final void Function(bool?) onToggle;

  const _ThresholdRow({
    required this.enabled,
    required this.label,
    required this.valueLabel,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(value: enabled, onChanged: onToggle),
        Expanded(child: Text(label)),
        Text(
          valueLabel,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: enabled ? null : Colors.grey,
          ),
        ),
      ],
    );
  }
}
