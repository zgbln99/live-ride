import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../models/ride_record.dart';
import '../models/ride_route.dart';
import '../services/gpx_service.dart';
import '../services/heart_rate_service.dart';
import '../services/live_service.dart';
import '../services/ride_storage_service.dart';
import 'free_ride_screen.dart';
import 'navigation_screen.dart';
import 'ride_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.gpx,
    required this.rideStorage,
    required this.heartRate,
    required this.live,
    required this.onLogout,
  });

  final ApiClient api;
  final GpxService gpx;
  final RideStorageService rideStorage;
  final HeartRateService heartRate;
  final LiveSessionController live;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _loadingRoutes = true;
  bool _loadingRides = true;
  bool _importing = false;
  List<RideRoute> _routes = [];
  List<RecordedRide> _rides = [];

  @override
  void initState() {
    super.initState();
    _reloadRoutes();
    _reloadRides();
  }

  Future<void> _reloadRoutes() async {
    final routes = await widget.gpx.loadSaved();
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _loadingRoutes = false;
    });
  }

  Future<void> _reloadRides() async {
    final rides = await widget.rideStorage.loadAll();
    if (!mounted) return;
    setState(() {
      _rides = rides;
      _loadingRides = false;
    });
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final route = await widget.gpx.importRoute();
      if (route != null) {
        await _reloadRoutes();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Zaimportowano: ${route.name} • ${route.points.length} punktów',
            ),
          ),
        );
      }
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _startFreeRide() async {
    final result = await Navigator.of(context).push<RecordedRide>(
      MaterialPageRoute(
        builder: (_) => FreeRideScreen(
          heartRate: widget.heartRate,
          storage: widget.rideStorage,
        ),
      ),
    );
    if (result != null) {
      await _reloadRides();
      if (mounted) setState(() => _tab = 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Jazda', 'Historia', 'LIVE', 'Ustawienia'];
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
          _rideTab(),
          _historyTab(),
          _liveTab(),
          _settingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.directions_bike_outlined),
            selectedIcon: Icon(Icons.directions_bike),
            label: 'Jazda',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Historia',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'LIVE',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ustawienia',
          ),
        ],
      ),
    );
  }

  Widget _rideTab() {
    return RefreshIndicator(
      onRefresh: _reloadRoutes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF071018),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Jedź bez trasy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Nagrywaj GPS, dystans, czas, prędkość, przewyższenie i HR z WHOOP.',
                  style: TextStyle(color: Color(0xFF9FB0BD)),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _startFreeRide,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('START RIDE'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF19D8FF),
                    foregroundColor: const Color(0xFF071018),
                    minimumSize: const Size.fromHeight(58),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Trasy GPX',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _importing ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined),
                label: const Text('Import GPX'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingRoutes)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_routes.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nie masz jeszcze tras. Kliknij Import GPX i wybierz plik z aplikacji Pliki.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final route in _routes) ...[
              _routeCard(route),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _routeCard(RideRoute route) => Card(
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
                  child: const Icon(Icons.route),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(route.totalDistanceMeters / 1000).toStringAsFixed(1)} km • ${route.points.length} punktów',
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );

  Widget _historyTab() {
    if (_loadingRides) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _reloadRides,
      child: RideHistoryScreen(rides: _rides),
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
                      const Text(
                        'Nie transmitujesz pozycji.',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _createLive,
                        icon: const Icon(Icons.sensors),
                        label: const Text('Utwórz LIVE'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _joinLive,
                        icon: const Icon(Icons.group_add_outlined),
                        label: const Text('Dołącz kodem'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.circle, color: Colors.redAccent, size: 12),
                          SizedBox(width: 8),
                          Text(
                            'LIVE AKTYWNE',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        'Kod: ${session.joinToken}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(widget.live.viewerUrl ?? ''),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(text: widget.live.viewerUrl ?? ''),
                        ),
                        icon: const Icon(Icons.share),
                        label: const Text('Udostępnij widzom'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _stopLive,
                        child: const Text('Zakończ LIVE'),
                      ),
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
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _scanHeartRate,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Skanuj czujniki'),
                ),
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
                            leading: Icon(
                              device.likelyHeartRate
                                  ? Icons.favorite
                                  : Icons.bluetooth,
                            ),
                            title: Text(device.name),
                            subtitle: Text('${device.rssi} dBm'),
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
          const ListTile(
            title: Text('Serwer'),
            subtitle: Text(ApiClient.serverOrigin),
            leading: Icon(Icons.cloud_done_outlined),
          ),
          const ListTile(
            title: Text('Jednostki'),
            subtitle: Text('Metryczne'),
            leading: Icon(Icons.straighten),
          ),
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
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
          ),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Połączono: ${device.name}')),
        );
      }
    } catch (e) {
      _error(e);
    }
  }

  Future<String?> _textDialog(
    String title,
    String hint,
    String action,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(action),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _error(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('FormatException: ', ''))),
    );
  }
}
