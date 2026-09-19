import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../models/ride_route.dart';
import '../services/gpx_service.dart';
import '../services/heart_rate_service.dart';
import '../services/live_service.dart';
import 'navigation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.gpx,
    required this.heartRate,
    required this.live,
    required this.onLogout,
  });

  final ApiClient api;
  final GpxService gpx;
  final HeartRateService heartRate;
  final LiveSessionController live;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _loadingRoutes = true;
  bool _importing = false;
  List<RideRoute> _routes = [];

  @override
  void initState() {
    super.initState();
    _reloadRoutes();
  }

  Future<void> _reloadRoutes() async {
    final routes = await widget.gpx.loadSaved();
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _loadingRoutes = false;
    });
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final route = await widget.gpx.importRoute();
      if (route != null) await _reloadRoutes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('FormatException: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Trasy', 'LIVE', 'Ustawienia'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'LIVE RIDE',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _routesTab(),
          _liveTab(),
          _settingsTab(),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _importing ? null : _import,
              icon: _importing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_upload_outlined),
              label: const Text('Import GPX'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Trasy'),
          NavigationDestination(icon: Icon(Icons.sensors_outlined), selectedIcon: Icon(Icons.sensors), label: 'LIVE'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ustawienia'),
        ],
      ),
    );
  }

  Widget _routesTab() {
    if (_loadingRoutes) return const Center(child: CircularProgressIndicator());
    if (_routes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route, size: 64),
              SizedBox(height: 16),
              Text('Nie masz jeszcze tras', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              SizedBox(height: 8),
              Text('Wrzuć GPX i jedź. Bez dodatkowych formularzy.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _routes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final route = _routes[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NavigationScreen(
                  route: route,
                  api: widget.api,
                  heartRate: widget.heartRate,
                  live: widget.live,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.directions_bike),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(route.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('${(route.totalDistanceMeters / 1000).toStringAsFixed(1)} km  •  ${route.points.length} punktów'),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _liveTab() {
    final session = widget.live.session;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Sesja LIVE'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: session == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Nie transmitujesz pozycji.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      FilledButton.icon(onPressed: _createLive, icon: const Icon(Icons.sensors), label: const Text('Utwórz LIVE')),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(onPressed: _joinLive, icon: const Icon(Icons.group_add_outlined), label: const Text('Dołącz kodem')),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(children: [Icon(Icons.circle, color: Colors.redAccent, size: 12), SizedBox(width: 8), Text('LIVE AKTYWNE', style: TextStyle(fontWeight: FontWeight.w900))]),
                      const SizedBox(height: 12),
                      SelectableText('Kod dla rowerzystów: ${session.joinToken}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      SelectableText(widget.live.viewerUrl ?? ''),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => SharePlus.instance.share(ShareParams(text: widget.live.viewerUrl ?? '')),
                        icon: const Icon(Icons.share),
                        label: const Text('Udostępnij widzom'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: _stopLive, child: const Text('Zakończ LIVE')),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 22),
        _sectionTitle('WHOOP / czujnik HR'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StreamBuilder<int>(
                  stream: widget.heartRate.bpm,
                  initialData: widget.heartRate.latestBpm,
                  builder: (_, snapshot) => Text(
                    snapshot.data == null ? 'Brak połączenia' : '${snapshot.data} bpm',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('W WHOOP włącz HR Broadcast. Skan nie filtruje po nazwie ani reklamowanym UUID.'),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(onPressed: _scanHeartRate, icon: const Icon(Icons.bluetooth_searching), label: const Text('Skanuj czujniki')),
                StreamBuilder<List<HeartRateDevice>>(
                  stream: widget.heartRate.devices,
                  builder: (_, snapshot) {
                    final devices = snapshot.data ?? const [];
                    if (devices.isEmpty) return const SizedBox.shrink();
                    return Column(
                      children: [
                        const Divider(height: 28),
                        for (final device in devices.take(12))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(device.likelyHeartRate ? Icons.favorite : Icons.bluetooth),
                            title: Text(device.name),
                            subtitle: Text('${device.rssi} dBm${device.likelyHeartRate ? ' • HR' : ''}'),
                            trailing: const Icon(Icons.link),
                            onTap: () => _connectHeartRate(device),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingsTab() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Live Ride'),
          const ListTile(title: Text('Serwer'), subtitle: Text(ApiClient.serverOrigin), leading: Icon(Icons.cloud_done_outlined)),
          const ListTile(title: Text('Jednostki'), subtitle: Text('Metryczne'), leading: Icon(Icons.straighten)),
          const ListTile(title: Text('Nawigacja'), subtitle: Text('Heading-up, Garmin-style HUD'), leading: Icon(Icons.navigation_outlined)),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: () async {
              await widget.api.logout();
              widget.onLogout();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Wyloguj'),
          ),
        ],
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: .8)),
      );

  Future<void> _createLive() async {
    final title = await _textDialog('Nowy LIVE', 'Nazwa jazdy', 'Utwórz');
    if (title == null || title.trim().isEmpty) return;
    try {
      await widget.live.create(title: title.trim());
      if (mounted) setState(() {});
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _joinLive() async {
    final code = await _textDialog('Dołącz do LIVE', 'Kod', 'Dołącz');
    if (code == null || code.trim().isEmpty) return;
    try {
      await widget.live.join(code);
      if (mounted) setState(() {});
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _stopLive() async {
    try {
      await widget.live.stop();
      if (mounted) setState(() {});
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _scanHeartRate() async {
    try {
      await widget.heartRate.startScan();
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _connectHeartRate(HeartRateDevice device) async {
    try {
      await widget.heartRate.connect(device.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Połączono: ${device.name}')));
      }
    } catch (e) {
      _error(e);
    }
  }

  Future<String?> _textDialog(String title, String hint, String action) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(action)),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _error(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
  }
}
