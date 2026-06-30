import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../core/alert_checker.dart';
import '../../core/notification_prefs.dart';
import '../../core/notification_service.dart';
import '../../data/models/alert.dart';
import '../../data/repositories/alert_repository.dart';
import '../widgets/alert_detail_view.dart';
import '../widgets/create_alert_sheet.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final String uid;

  const HomeScreen({super.key, required this.uid});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _alertRepo = AlertRepository();
  final List<Alert> _alerts = [];
  TabController? _tabController;
  StreamSubscription<RemoteMessage>? _fcmSubscription;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _fcmSubscription = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
  }

  void _onForegroundMessage(RemoteMessage message) {
    if (!notificationPrefs.push.value) return;
    final title = message.notification?.title ?? 'Meteo Alert';
    final body = message.notification?.body ?? '';
    NotificationService.show(id: message.hashCode, title: title, body: body);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud, size: 36),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAlerts() async {
    try {
      final loaded = await _alertRepo.load(widget.uid);
      if (!mounted) return;
      if (loaded.isEmpty) return;
      setState(() {
        _alerts.addAll(loaded);
        _tabController = TabController(length: _alerts.length, vsync: this);
      });
      AlertChecker.checkAndNotify(_alerts);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar las alertas: $e')),
      );
    }
  }

  Future<void> _saveAlerts() async {
    try {
      await _alertRepo.save(widget.uid, _alerts);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar las alertas: $e')),
      );
    }
  }

  void _addAlert(Alert alert) {
    setState(() {
      _alerts.add(alert);
      _tabController?.dispose();
      _tabController = TabController(
        length: _alerts.length,
        vsync: this,
        initialIndex: _alerts.length - 1,
      );
    });
    _saveAlerts();
    AlertChecker.checkAndNotify(_alerts);
  }

  void _removeAlert(int index) {
    setState(() {
      _alerts.removeAt(index);
      _tabController?.dispose();
      if (_alerts.isEmpty) {
        _tabController = null;
      } else {
        final newIndex = index < _alerts.length ? index : _alerts.length - 1;
        _tabController = TabController(
          length: _alerts.length,
          vsync: this,
          initialIndex: newIndex,
        );
      }
    });
    _saveAlerts();
  }

  void _editAlert(int index, Alert alert) {
    final currentIndex = _tabController?.index ?? index;
    setState(() {
      _alerts[index] = alert;
      _tabController?.dispose();
      _tabController = TabController(
        length: _alerts.length,
        vsync: this,
        initialIndex: currentIndex,
      );
    });
    _saveAlerts();
    AlertChecker.checkAndNotify(_alerts);
  }

  void _openCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CreateAlertSheet(onCreated: _addAlert),
    );
  }

  void _openEditSheet(int index, Alert alert) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CreateAlertSheet(
        initialAlert: alert,
        onCreated: (updated) => _editAlert(index, updated),
      ),
    );
  }

  @override
  void dispose() {
    _fcmSubscription?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAlerts = _alerts.isNotEmpty && _tabController != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meteo Alert'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
          ),
        ],
        bottom: hasAlerts
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabs: List.generate(
                    _alerts.length,
                    (i) => Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_alerts[i].city),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _removeAlert(i),
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: hasAlerts
          ? TabBarView(
              controller: _tabController,
              children: List.generate(
                _alerts.length,
                (i) => AlertDetailView(
                  alert: _alerts[i],
                  onEdit: () => _openEditSheet(i, _alerts[i]),
                  onRefreshed: () => AlertChecker.checkAndNotify(_alerts),
                ),
              ),
            )
          : const _EmptyState(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No hay alertas activas',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Pulsa + para crear una nueva alerta',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
