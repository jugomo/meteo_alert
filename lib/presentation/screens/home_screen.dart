import 'package:flutter/material.dart';

import '../../data/models/alert.dart';
import '../../data/repositories/alert_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/alert_detail_view.dart';
import '../widgets/create_alert_sheet.dart';

class HomeScreen extends StatefulWidget {
  final String uid;

  const HomeScreen({super.key, required this.uid});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _alertRepo = AlertRepository();
  final _authRepo = AuthRepository();
  final List<Alert> _alerts = [];
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    final loaded = await _alertRepo.load(widget.uid);
    if (loaded.isEmpty) return;
    setState(() {
      _alerts.addAll(loaded);
      _tabController = TabController(length: _alerts.length, vsync: this);
    });
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
    _alertRepo.save(widget.uid, _alerts);
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
    _alertRepo.save(widget.uid, _alerts);
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
    _alertRepo.save(widget.uid, _alerts);
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

  Future<void> _signOut() async {
    await _authRepo.signOut();
  }

  @override
  void dispose() {
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
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
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
