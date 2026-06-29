import 'package:flutter/material.dart';

import '../../core/theme_notifier.dart';
import '../../data/repositories/auth_repository.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ajustes'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Ajustes'),
              Tab(text: 'Acerca de'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SettingsTab(),
            _AboutTab(),
          ],
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (context, mode, _) => SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Modo oscuro'),
            value: mode == ThemeMode.dark,
            onChanged: (_) => themeNotifier.toggle(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text(
            'Cerrar sesión',
            style: TextStyle(color: Colors.red),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.shade200),
          ),
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Cerrar sesión'),
                content: const Text('¿Seguro que quieres cerrar sesión?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Cerrar sesión',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await AuthRepository().signOut();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            }
          },
        ),
      ],
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.cloud,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Meteo Alert',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Text(
          'Descripción',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Meteo Alert te permite crear alertas meteorológicas personalizadas '
          'para las ciudades que elijas. Define umbrales de temperatura, '
          'viento y probabilidad de lluvia, y consulta de un vistazo qué '
          'horas de los próximos días superarán esos límites.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 24),
        Text(
          'API meteorológica',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Los datos meteorológicos son proporcionados por Open-Meteo, '
          'una API gratuita y de código abierto que ofrece previsiones '
          'horarias de alta resolución basadas en modelos numéricos del tiempo '
          'de acceso público.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 8),
        Text(
          'open-meteo.com',
          style: textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
