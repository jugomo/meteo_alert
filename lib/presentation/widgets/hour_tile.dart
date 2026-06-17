import 'package:flutter/material.dart';

import '../../data/models/forecast_hour.dart';
import 'value_chip.dart';

class HourTile extends StatelessWidget {
  final ForecastHour hour;

  const HourTile({super.key, required this.hour});

  @override
  Widget build(BuildContext context) {
    final timeStr = '${hour.time.hour.toString().padLeft(2, '0')}:00';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              timeStr,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 8,
            children: [
              if (hour.temperature != null)
                ValueChip(
                  icon: Icons.thermostat,
                  label: '${hour.temperature!.toStringAsFixed(1)}°C',
                  color: Colors.orange,
                ),
              if (hour.wind != null)
                ValueChip(
                  icon: Icons.air,
                  label: '${hour.wind!.toStringAsFixed(0)} km/h',
                  color: Colors.blue,
                ),
              if (hour.rain != null)
                ValueChip(
                  icon: Icons.water_drop,
                  label: '${hour.rain!.toStringAsFixed(0)}%',
                  color: Colors.indigo,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
