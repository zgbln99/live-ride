import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../models/route/route_waypoint.dart';
import '../services/route_builder_controller.dart';
import '../widgets/lr_common.dart';

/// Lista punktów trasy z możliwością zmiany kolejności i usuwania.
Future<void> showWaypointListSheet(
  BuildContext context,
  RouteBuilderController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    maxChildSize: 0.92,
    builder: (context, scrollController) => _WaypointList(
      controller: controller,
      scrollController: scrollController,
    ),
  ),
);

class _WaypointList extends StatefulWidget {
  const _WaypointList({
    required this.controller,
    required this.scrollController,
  });

  final RouteBuilderController controller;
  final ScrollController scrollController;

  @override
  State<_WaypointList> createState() => _WaypointListState();
}

class _WaypointListState extends State<_WaypointList> {
  @override
  Widget build(BuildContext context) {
    final waypoints = widget.controller.waypoints;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(
            children: [
              const Expanded(
                child: LrSectionHeader(
                  title: 'Punkty trasy',
                  padding: EdgeInsets.zero,
                ),
              ),
              if (waypoints.length >= 2)
                TextButton.icon(
                  onPressed: () {
                    widget.controller.reverse();
                    setState(() {});
                  },
                  icon: const Icon(Icons.swap_vert, size: 17),
                  label: const Text('ODWRÓĆ'),
                ),
            ],
          ),
        ),
        Expanded(
          child: waypoints.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Dotknij mapy, żeby postawić pierwszy punkt.',
                      textAlign: TextAlign.center,
                      style: LR.body,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  scrollController: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: waypoints.length,
                  // onReorderItem dostaje już poprawiony indeks docelowy,
                  // więc nie trzeba go korygować ręcznie.
                  onReorderItem: (from, to) {
                    widget.controller.reorderWaypoint(from, to);
                    setState(() {});
                  },
                  itemBuilder: (context, index) {
                    final waypoint = waypoints[index];
                    return Padding(
                      key: ValueKey('waypoint-$index-${waypoint.lat}'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LrPanel(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        child: Row(
                          children: [
                            _badge(waypoint, index),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    waypoint.name.isEmpty
                                        ? waypoint.kind.label
                                        : waypoint.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${waypoint.lat.toStringAsFixed(5)}, '
                                    '${waypoint.lon.toStringAsFixed(5)}',
                                    style: LR.body.copyWith(fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Usuń punkt',
                              icon: const Icon(Icons.delete_outline, size: 19),
                              onPressed: () {
                                widget.controller.removeWaypoint(index);
                                setState(() {});
                              },
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(
                                  Icons.drag_handle,
                                  size: 20,
                                  color: LR.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _badge(RouteWaypoint waypoint, int index) {
    final color = switch (waypoint.kind) {
      WaypointKind.start => LR.go,
      WaypointKind.finish => LR.alert,
      WaypointKind.via => LR.ink,
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        switch (waypoint.kind) {
          WaypointKind.start => 'S',
          WaypointKind.finish => 'M',
          WaypointKind.via => '$index',
        },
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
