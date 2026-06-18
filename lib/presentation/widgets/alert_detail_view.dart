import 'package:flutter/material.dart';

import '../../data/models/alert.dart';
import '../../data/models/forecast_hour.dart';
import '../../data/repositories/weather_repository.dart';
import 'hour_tile.dart';
import 'summary_chip.dart';

class AlertDetailView extends StatefulWidget {
  final Alert alert;
  final VoidCallback? onEdit;
  final VoidCallback? onRefreshed;

  const AlertDetailView({
    super.key,
    required this.alert,
    this.onEdit,
    this.onRefreshed,
  });

  @override
  State<AlertDetailView> createState() => _AlertDetailViewState();
}

class _AlertDetailViewState extends State<AlertDetailView> {
  final _weatherRepo = WeatherRepository();
  List<ForecastHour>? _exceeded;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.alert.latitude != null && widget.alert.longitude != null) {
      _fetchForecast();
    } else {
      setState(() {
        _loading = false;
        _error = 'Esta alerta no tiene coordenadas. Vuelve a crearla.';
      });
    }
  }

  @override
  void didUpdateWidget(AlertDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.alert, widget.alert)) {
      if (widget.alert.latitude != null && widget.alert.longitude != null) {
        _fetchForecast();
      } else {
        setState(() {
          _loading = false;
          _exceeded = null;
          _error = 'Esta alerta no tiene coordenadas. Vuelve a crearla.';
        });
      }
    }
  }

  Future<void> _fetchForecast() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final exceeded = await _weatherRepo.fetchExceeded(widget.alert);
      if (mounted) {
        setState(() {
          _exceeded = exceeded;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo cargar el pronóstico.';
          _loading = false;
        });
      }
    }
  }

  Map<DateTime, List<ForecastHour>> _groupByDay(List<ForecastHour> hours) {
    final map = <DateTime, List<ForecastHour>>{};
    for (final h in hours) {
      final day = DateTime(h.time.year, h.time.month, h.time.day);
      map.putIfAbsent(day, () => []).add(h);
    }
    return map;
  }

  String _formatDay(DateTime d) {
    const weekdays = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${alert.city}, ${alert.country}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  if (widget.onEdit != null)
                    IconButton(
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Editar alerta',
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  SummaryChip(
                    icon: Icons.calendar_today,
                    label: '${alert.forecastDays} días',
                  ),
                  if (alert.temperatureEnabled)
                    SummaryChip(
                      icon: Icons.thermostat,
                      label: '>${alert.temperature.toStringAsFixed(0)}°C',
                    ),
                  if (alert.windEnabled)
                    SummaryChip(
                      icon: Icons.air,
                      label: '>${alert.wind.toStringAsFixed(0)} km/h',
                    ),
                  if (alert.rainEnabled)
                    SummaryChip(
                      icon: Icons.water_drop,
                      label: '>${alert.rainProbability.toStringAsFixed(0)}%',
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _fetchForecast,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final exceeded = _exceeded!;
    if (exceeded.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('No se superarán los umbrales', style: TextStyle(fontSize: 16)),
            SizedBox(height: 4),
            Text('en el período de pronóstico', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final grouped = _groupByDay(exceeded);
    final days = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchForecast();
        widget.onRefreshed?.call();
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: days.length,
        itemBuilder: (ctx, i) {
          final day = days[i];
          final hours = grouped[day]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                child: Text(
                  _formatDay(day),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const Divider(height: 1),
              ...hours.map((h) => HourTile(hour: h)),
            ],
          );
        },
      ),
    );
  }
}
