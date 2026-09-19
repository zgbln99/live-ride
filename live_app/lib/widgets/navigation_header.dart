import 'package:flutter/material.dart';

import '../i18n/strings.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../models/navigation_plan.dart';
import 'chrome_fade.dart';

/// The turn-by-turn block at the top of the navigation screen.
///
/// Layout, top to bottom: a thin status strip (remaining distance, remaining
/// time, ETA, LIVE), then the maneuver itself — a large arrow, the distance to
/// the turn at the biggest type size in the app, the instruction and the
/// street it puts the rider on.
class NavigationHeader extends StatelessWidget {
  const NavigationHeader({
    super.key,
    required this.progress,
    required this.metric,
    required this.routeName,
    this.etaSeconds,
    this.live = false,
    this.mapMatched = true,
    this.chromeVisible = true,
    this.onExit,
    this.onOverview,
  });

  final NavigationProgress? progress;
  final bool metric;
  final String routeName;
  final double? etaSeconds;
  final bool live;
  final bool mapMatched;

  /// False once the ride has gone quiet: the exit and overview buttons and the
  /// route name retire, while the maneuver, the distance left and the ETA — the
  /// reasons this header exists — stay exactly where they were.
  final bool chromeVisible;

  final VoidCallback? onExit;
  final VoidCallback? onOverview;

  @override
  Widget build(BuildContext context) {
    final next = progress?.next;
    final offRoute = progress?.offRoute ?? false;
    final distanceToTurn = progress?.distanceToManeuver ?? 0;

    return Material(
      color: LR.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusStrip(context),
            if (offRoute)
              _banner(
                icon: Icons.warning_amber_rounded,
                color: LR.alert,
                text:
                    'OFF ROUTE · ${Fmt.turnDistance(progress!.offRouteMeters, metric: metric)} '
                    '${Fmt.turnDistanceUnit(progress!.offRouteMeters, metric: metric)} from the line',
              )
            else if (!mapMatched)
              _banner(
                icon: Icons.alt_route,
                color: LR.inkSoft,
                text: 'FOLLOWING THE IMPORTED TRACK · no turn instructions',
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 74,
                    child: Icon(
                      next?.icon ?? Icons.navigation,
                      size: 66,
                      color: offRoute ? LR.alert : LR.ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                next == null
                                    ? '--'
                                    : Fmt.turnDistance(
                                        distanceToTurn,
                                        metric: metric,
                                      ),
                                style: LR.fieldValue(64),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                next == null
                                    ? ''
                                    : Fmt.turnDistanceUnit(
                                        distanceToTurn,
                                        metric: metric,
                                      ),
                                style: LR.fieldUnit.copyWith(fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _instruction(next),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: LR.ink,
                          ),
                        ),
                        if (next?.streetName.isNotEmpty ?? false) ...[
                          const SizedBox(height: 3),
                          Text(
                            next!.streetName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LR.body.copyWith(fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _instruction(NavManeuver? next) {
    if (next == null) {
      return mapMatched ? S.stayOnRoute : S.followTheTrack;
    }
    if (next.instruction.isNotEmpty) return next.instruction;
    return next.isDestination ? S.arriveAtDestination : S.continueAhead;
  }

  Widget _statusStrip(BuildContext context) {
    final remaining = progress?.remainingMeters;
    final eta = etaSeconds;
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LR.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The strip sheds content as the screen narrows, in the order a
          // rider misses it least: the route name first (they know which
          // route they started), then the ETA, then the LIVE marker. The
          // distance left and the exit button always survive, and the
          // readouts scale down rather than clipping if a locale or a font
          // makes them wider than expected.
          final width = constraints.maxWidth;
          final showName = width >= 430;
          final showEta = width >= 360;
          final showLive = live && width >= 330;

          return Row(
            children: [
              if (onExit != null)
                ChromeFade(
                  visible: chromeVisible,
                  child: _stripButton(Icons.close, 'Exit navigation', onExit!),
                ),
              const SizedBox(width: 6),
              if (showName)
                Expanded(
                  child: ChromeFade(
                    visible: chromeVisible,
                    child: Text(
                      routeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: LR.inkSoft,
                      ),
                    ),
                  ),
                ),
              Expanded(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showLive) ...[
                        const _LiveDot(),
                        const SizedBox(width: 10),
                      ],
                      _stripStat(
                        remaining == null
                            ? '--'
                            : '${Fmt.distance(remaining, metric: metric)} '
                                  '${Fmt.distanceUnit(metric: metric)}',
                        'LEFT',
                      ),
                      if (showEta) ...[
                        const SizedBox(width: 12),
                        _stripStat(
                          eta == null
                              ? '--'
                              : Fmt.clock(
                                  DateTime.now().add(
                                    Duration(seconds: eta.round()),
                                  ),
                                ),
                          'ETA',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (onOverview != null)
                ChromeFade(
                  visible: chromeVisible,
                  child: _stripButton(
                    Icons.map_outlined,
                    S.routeOverview,
                    onOverview!,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _stripStat(String value, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: LR.ink,
          fontFeatures: LR.numeric,
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: LR.fieldLabel.copyWith(fontSize: 9)),
    ],
  );

  Widget _stripButton(IconData icon, String tooltip, VoidCallback onTap) =>
      IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: LR.ink,
        padding: EdgeInsets.zero,
        // A default icon button reserves a 48 px tap target in both axes,
        // which does not fit a 42 px strip on a narrow phone.
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      );

  Widget _banner({
    required IconData icon,
    required Color color,
    required String text,
  }) => Container(
    width: double.infinity,
    color: color == LR.alert ? LR.alert : LR.panel,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    child: Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: color == LR.alert ? Colors.white : LR.inkSoft,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
              color: color == LR.alert ? Colors.white : LR.inkSoft,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: LR.alert,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      const Text(
        'LIVE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: LR.alert,
        ),
      ),
    ],
  );
}
