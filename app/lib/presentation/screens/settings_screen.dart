import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/notification_prefs.dart';
import '../../core/theme_notifier.dart';
import '../../data/repositories/auth_repository.dart';

const _dbUrl =
    'https://meteo-alert-409a8-default-rtdb.europe-west1.firebasedatabase.app';

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

  Future<void> _onPushChanged(bool value) async {
    await notificationPrefs.setPush(value);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: _dbUrl,
    ).ref('users/$uid/fcmToken');
    if (value) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        debugPrint('[FCM] Enviando token al servidor: $token');
        await ref.set(token);
      }
    } else {
      await ref.remove();
    }
  }

  Future<bool> _showDeleteWithPasswordDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? errorText;
        bool isLoading = false;

        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Confirmar eliminación'),
            content: isLoading
                ? const SizedBox(
                    height: 72,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Introduce tu contraseña para confirmar.'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        obscureText: true,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          errorText: errorText,
                        ),
                      ),
                    ],
                  ),
            actions: isLoading
                ? null
                : [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (controller.text.isEmpty) return;
                        setState(() {
                          isLoading = true;
                          errorText = null;
                        });
                        try {
                          await AuthRepository()
                              .deleteAccount(controller.text);
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on FirebaseAuthException catch (e) {
                          setState(() {
                            isLoading = false;
                            errorText = e.code == 'wrong-password' ||
                                    e.code == 'invalid-credential'
                                ? 'Contraseña incorrecta'
                                : 'Error al eliminar. Inténtalo de nuevo.';
                          });
                        }
                      },
                      child: const Text(
                        'Eliminar',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
          ),
        );
      },
    );
    return result == true;
  }

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
        ValueListenableBuilder<bool>(
          valueListenable: notificationPrefs.local,
          builder: (context, enabled, _) => SwitchListTile(
            secondary: const Icon(Icons.notifications_active),
            title: const Text('Notificaciones locales'),
            subtitle: const Text('Alertas generadas por la app'),
            value: enabled,
            onChanged: notificationPrefs.setLocal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: notificationPrefs.push,
          builder: (context, enabled, _) => SwitchListTile(
            secondary: const Icon(Icons.cloud_outlined),
            title: const Text('Notificaciones push'),
            subtitle: const Text('Alertas enviadas desde el servidor'),
            value: enabled,
            onChanged: _onPushChanged,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'Usuario: ${FirebaseAuth.instance.currentUser?.email ?? ''}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 4),
        TextButton(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Eliminar cuenta'),
                content: const Text(
                  '¿Seguro que quieres eliminar tu cuenta?\n\n'
                  'Se eliminarán todas tus alertas y datos asociados. '
                  'Esta acción no se puede deshacer.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Continuar',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
            if (confirmed == true && context.mounted) {
              final deleted = await _showDeleteWithPasswordDialog(context);
              if (deleted && context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.centerLeft,
          ),
          child: const Text('Eliminar cuenta'),
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
        const SizedBox(height: 32),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) => Text(
            snapshot.hasData ? 'v${snapshot.data!.version}' : '',
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
