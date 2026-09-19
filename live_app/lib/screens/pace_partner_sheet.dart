import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/pace_partner.dart';
import '../models/ride_record.dart';
import '../models/ride_route.dart';
import '../services/app_services.dart';
import '../services/pace_partner.dart';
import '../widgets/lr_common.dart';

/// Wybór wirtualnego rywala przed startem.
Future<bool> showPacePartnerSheet(
  BuildContext context,
  AppServices services, {
  RideRoute? route,
}) async {
  final started = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, controller) => _PacePartnerSheet(
        services: services,
        route: route,
        scrollController: controller,
      ),
    ),
  );
  return started ?? false;
}

class _PacePartnerSheet extends StatefulWidget {
  const _PacePartnerSheet({
    required this.services,
    required this.route,
    required this.scrollController,
  });

  final AppServices services;
  final RideRoute? route;
  final ScrollController scrollController;

  @override
  State<_PacePartnerSheet> createState() => _PacePartnerSheetState();
}

class _PacePartnerSheetState extends State<_PacePartnerSheet> {
  double _speed = 25;
  int _minutes = 60;
  List<RecordedRide> _rides = const [];
  bool _loading = true;

  double get _routeDistance =>
      widget.route?.distanceMeters ?? _rides.firstOrNull?.distanceMeters ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final rides = await widget.services.rides.list();
    if (!mounted) return;
    setState(() {
      _rides = rides.take(10).toList();
      _loading = false;
    });
  }

  void _start(PaceTarget target) {
    widget.services.pace.start(target, route: widget.route);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final metric = widget.services.profile.profile.metricUnits;
    final active = widget.services.pace.isActive;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        LrSectionHeader(
          title: S.pacePartner,
          padding: const EdgeInsets.only(bottom: 6),
        ),
        Text(S.pacePartnerHint, style: LR.body.copyWith(fontSize: 12.5)),
        if (active) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: Text(S.stopPacePartner),
            onPressed: () {
              widget.services.pace.stop();
              Navigator.of(context).pop(false);
            },
          ),
        ],
        const SizedBox(height: 20),

        // --- stała prędkość --------------------------------------------
        Text(S.targetSpeed, style: LR.fieldLabel),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _speed,
                min: 10,
                max: 45,
                divisions: 35,
                label: '${_speed.round()} km/h',
                onChanged: (value) => setState(() => _speed = value),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                '${_speed.round()} ${Fmt.speedUnit(metric: metric)}',
                textAlign: TextAlign.end,
                style: LR.fieldValue(16),
              ),
            ),
          ],
        ),
        FilledButton(
          onPressed: () => _start(
            PaceTarget(
              kind: PaceTargetKind.speed,
              label: '${_speed.round()} ${Fmt.speedUnit(metric: metric)}',
              routeDistanceMeters: _routeDistance,
              targetSpeedKmh: _speed,
            ),
          ),
          child: Text(S.startPacePartner),
        ),

        // --- czas na trasie ---------------------------------------------
        if (_routeDistance > 0) ...[
          const SizedBox(height: 24),
          Text(S.targetTime, style: LR.fieldLabel),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _minutes.toDouble(),
                  min: 10,
                  max: 480,
                  divisions: 47,
                  label: '$_minutes min',
                  onChanged: (value) =>
                      setState(() => _minutes = value.round()),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  Fmt.durationCompact(Duration(minutes: _minutes)),
                  textAlign: TextAlign.end,
                  style: LR.fieldValue(16),
                ),
              ),
            ],
          ),
          FilledButton(
            onPressed: () => _start(
              PaceTarget(
                kind: PaceTargetKind.time,
                label: Fmt.durationCompact(Duration(minutes: _minutes)),
                routeDistanceMeters: _routeDistance,
                targetDuration: Duration(minutes: _minutes),
              ),
            ),
            child: Text(S.startPacePartner),
          ),
        ],

        // --- ghost z przejazdu -------------------------------------------
        const SizedBox(height: 24),
        LrSectionHeader(
          title: PaceTargetKind.previousRide.label,
          padding: const EdgeInsets.only(bottom: 6),
        ),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_rides.isEmpty)
          Text(S.ghostNeedsRide, style: LR.body.copyWith(fontSize: 12.5))
        else
          for (final ride in _rides)
            Builder(
              builder: (context) {
                final target = PacePartnerService.fromRide(
                  ride,
                  label: ride.name,
                );
                return ListTile(
                  dense: true,
                  enabled: target != null,
                  leading: const Icon(Icons.directions_bike),
                  title: Text(ride.name),
                  subtitle: Text(
                    target == null
                        ? S.ghostNeedsRide
                        : '${Fmt.distance(ride.distanceMeters, metric: metric)} '
                              '${Fmt.distanceUnit(metric: metric)} · '
                              '${Fmt.durationCompact(ride.movingTime)}',
                  ),
                  onTap: target == null ? null : () => _start(target),
                );
              },
            ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
