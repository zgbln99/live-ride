import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/lr_theme.dart';
import '../../i18n/strings.dart';
import '../../models/ride_record.dart';
import '../../models/ride_statistics.dart';
import '../../services/app_services.dart';
import '../../widgets/lr_common.dart';
import '../../widgets/stats_chart.dart';
import '../../widgets/track_preview.dart';
import '../heatmap_screen.dart';
import '../ride_summary_screen.dart';

/// Historia przejazdów z podsumowaniem okresu, wykresem, rekordami
/// i kalendarzem.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<RecordedRide> _rides = const [];
  RideStatistics? _statistics;
  List<RideRecord> _records = const [];
  Map<DateTime, ({int rides, double distanceMeters})> _calendar = const {};
  StatsPeriod _period = StatsPeriod.month;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = AppServices.of(context);
    final rides = await services.rides.list(refresh: true);
    final dao = services.rides.dao;
    final statistics = await dao.statistics(_period);
    final records = await dao.records();
    final calendar = await dao.calendar(
      from: _calendarMonth,
      to: DateTime(_calendarMonth.year, _calendarMonth.month + 1),
    );
    if (!mounted) return;
    setState(() {
      _rides = rides;
      _statistics = statistics;
      _records = records;
      _calendar = calendar;
      _loading = false;
    });
  }

  Future<void> _reloadStats() async {
    final dao = AppServices.of(context).rides.dao;
    final statistics = await dao.statistics(_period);
    final calendar = await dao.calendar(
      from: _calendarMonth,
      to: DateTime(_calendarMonth.year, _calendarMonth.month + 1),
    );
    if (!mounted) return;
    setState(() {
      _statistics = statistics;
      _calendar = calendar;
    });
  }

  @override
  Widget build(BuildContext context) {
    final metric = AppServices.of(context).profile.profile.metricUnits;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rides.isEmpty) {
      return LrEmptyState(
        icon: Icons.history,
        title: S.noRidesYet,
        message: S.noRidesMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _periodPicker(),
          const SizedBox(height: 12),
          if (_statistics != null) _summary(_statistics!, metric),
          const SizedBox(height: 18),
          if (_records.isNotEmpty) ...[
            LrSectionHeader(
              title: S.records,
              padding: const EdgeInsets.only(bottom: 8),
            ),
            _recordsPanel(metric),
            const SizedBox(height: 18),
          ],
          LrSectionHeader(
            title: S.calendar,
            padding: const EdgeInsets.only(bottom: 8),
            trailing: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text(
                  Fmt.monthYear(_calendarMonth),
                  style: LR.body.copyWith(fontSize: 12.5),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
          ),
          LrPanel(
            child: RideCalendar(
              month: _calendarMonth,
              days: _calendar,
              onTapDay: _openDay,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(S.heatmap),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HeatmapScreen()),
            ),
          ),
          const SizedBox(height: 18),
          LrSectionHeader(
            title: S.rides,
            padding: const EdgeInsets.only(bottom: 8),
          ),
          for (final ride in _rides) ...[
            _rideCard(ride, metric),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _periodPicker() => SegmentedButton<StatsPeriod>(
    segments: [
      for (final period in StatsPeriod.values)
        ButtonSegment(value: period, label: Text(period.label)),
    ],
    selected: {_period},
    showSelectedIcon: false,
    onSelectionChanged: (selection) {
      setState(() => _period = selection.first);
      unawaited(_reloadStats());
    },
  );

  Widget _summary(RideStatistics statistics, bool metric) {
    final change = statistics.distanceChangePercent;
    return LrPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: LrStat(
                  label: S.rides,
                  value: '${statistics.rides}',
                  valueSize: 24,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: S.distance,
                  value: Fmt.distance(
                    statistics.distanceMeters,
                    metric: metric,
                  ),
                  unit: Fmt.distanceUnit(metric: metric),
                  valueSize: 24,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: S.ascent,
                  value: Fmt.elevation(statistics.ascentMeters, metric: metric),
                  unit: Fmt.elevationUnit(metric: metric),
                  valueSize: 24,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: S.elapsed,
                  value: Fmt.durationCompact(statistics.movingTime),
                  valueSize: 24,
                ),
              ),
            ],
          ),
          if (change != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  change >= 0 ? Icons.trending_up : Icons.trending_down,
                  size: 16,
                  color: change >= 0 ? LR.go : LR.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  S.comparedToPrevious(
                    '${change >= 0 ? '+' : ''}${change.round()} %',
                  ),
                  style: LR.body.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          StatsChart(
            statistics: statistics,
            now: DateTime.now(),
            metric: metric,
          ),
        ],
      ),
    );
  }

  Widget _recordsPanel(bool metric) => LrPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < _records.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.emoji_events_outlined, size: 20),
            title: Text(_records[i].kind.label, style: LR.fieldValue(14)),
            subtitle: Text(
              '${_records[i].rideName} · ${Fmt.date(_records[i].achievedAt)}',
              style: LR.body.copyWith(fontSize: 11.5),
            ),
            trailing: Text(
              _recordValue(_records[i], metric),
              style: LR.fieldValue(16),
            ),
            onTap: () => _openRide(_records[i].rideId),
          ),
        ],
      ],
    ),
  );

  String _recordValue(RideRecord record, bool metric) => switch (record.kind) {
    RideRecordKind.longestDistance =>
      '${Fmt.distance(record.value, metric: metric)} '
          '${Fmt.distanceUnit(metric: metric)}',
    RideRecordKind.longestTime => Fmt.durationCompact(
      Duration(seconds: record.value.round()),
    ),
    RideRecordKind.biggestAscent =>
      '${Fmt.elevation(record.value, metric: metric)} '
          '${Fmt.elevationUnit(metric: metric)}',
    RideRecordKind.fastestAverage || RideRecordKind.highestSpeed =>
      '${Fmt.speed(record.value, metric: metric)} '
          '${Fmt.speedUnit(metric: metric)}',
    RideRecordKind.bestNormalizedPower => '${record.value.round()} W',
  };

  void _shiftMonth(int delta) {
    setState(() {
      _calendarMonth = DateTime(
        _calendarMonth.year,
        _calendarMonth.month + delta,
      );
    });
    unawaited(_reloadStats());
  }

  Future<void> _openDay(DateTime day) async {
    final match = _rides.where(
      (ride) =>
          ride.startedAt.year == day.year &&
          ride.startedAt.month == day.month &&
          ride.startedAt.day == day.day,
    );
    if (match.isEmpty) return;
    await _open(match.first);
  }

  Future<void> _openRide(String id) async {
    final match = _rides.where((ride) => ride.id == id);
    if (match.isEmpty) return;
    await _open(match.first);
  }

  Widget _rideCard(RecordedRide ride, bool metric) => LrPanel(
    padding: EdgeInsets.zero,
    onTap: () => _open(ride),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 58,
                child: TrackPreview(points: ride.preview, strokeWidth: 2.2),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${Fmt.date(ride.startedAt)} · '
                      '${Fmt.clock(ride.startedAt)}',
                      style: LR.body.copyWith(fontSize: 12.5),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        if (ride.hasHeartRate)
                          _Chip(
                            icon: Icons.favorite,
                            color: LR.alert,
                            label: '${ride.averageHeartRate} bpm',
                          ),
                        if (ride.hasPower)
                          _Chip(
                            icon: Icons.bolt,
                            color: LR.accentDeep,
                            label: '${ride.averagePower} W',
                          ),
                        if (ride.hasCadence)
                          _Chip(
                            icon: Icons.rotate_right,
                            color: LR.inkSoft,
                            label: '${ride.averageCadence} rpm',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: LrStat(
                  label: S.distance,
                  value: Fmt.distance(ride.distanceMeters, metric: metric),
                  unit: Fmt.distanceUnit(metric: metric),
                  valueSize: 18,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: S.movingTime,
                  value: Fmt.duration(ride.movingTime),
                  valueSize: 18,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: S.average,
                  value: Fmt.speed(ride.averageSpeedKmh, metric: metric),
                  unit: Fmt.speedUnit(metric: metric),
                  valueSize: 18,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: S.ascent,
                  value: Fmt.elevation(
                    ride.elevationGainMeters,
                    metric: metric,
                  ),
                  unit: Fmt.elevationUnit(metric: metric),
                  valueSize: 18,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _open(RecordedRide ride) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RideSummaryScreen(ride: ride)),
    );
    unawaited(_load());
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: LR.fieldLabel.copyWith(fontSize: 10)),
    ],
  );
}
