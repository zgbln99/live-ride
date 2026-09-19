import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../models/ride_statistics.dart';

/// Słupki dystansu w okresie.
///
/// Wykres rysuje każdy przedział, także pusty — tydzień z trzema dniami
/// jazdy ma wyglądać jak tydzień z trzema dniami jazdy, a nie jak trzy
/// słupki obok siebie.
class StatsChart extends StatelessWidget {
  const StatsChart({
    super.key,
    required this.statistics,
    required this.now,
    this.metric = true,
    this.height = 120,
  });

  final RideStatistics statistics;
  final DateTime now;
  final bool metric;
  final double height;

  @override
  Widget build(BuildContext context) {
    final slots = _slots();
    if (slots.isEmpty) return const SizedBox.shrink();

    final maximum = slots.fold<double>(
      0,
      (best, slot) => math.max(best, slot.distanceMeters),
    );

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final slot in slots)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (slot.distanceMeters > 0)
                      Text(
                        Fmt.distance(slot.distanceMeters, metric: metric),
                        style: LR.body.copyWith(fontSize: 8.5),
                        maxLines: 1,
                      ),
                    const SizedBox(height: 2),
                    Container(
                      height: maximum <= 0
                          ? 2
                          : math.max(
                              2,
                              slot.distanceMeters / maximum * (height - 34),
                            ),
                      decoration: BoxDecoration(
                        color: slot.distanceMeters > 0
                            ? LR.accentDeep
                            : LR.line,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slot.label,
                      style: LR.body.copyWith(fontSize: 9),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<({String label, double distanceMeters})> _slots() {
    final byStart = {
      for (final bucket in statistics.buckets) bucket.start: bucket,
    };
    double distanceAt(DateTime start) => byStart[start]?.distanceMeters ?? 0;

    switch (statistics.period) {
      case StatsPeriod.week:
        const days = ['pn', 'wt', 'śr', 'cz', 'pt', 'sb', 'nd'];
        final start = statistics.from;
        return [
          for (var i = 0; i < 7; i++)
            (
              label: days[i],
              distanceMeters: distanceAt(
                DateTime(start.year, start.month, start.day + i),
              ),
            ),
        ];
      case StatsPeriod.month:
        final start = statistics.from;
        final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
        return [
          for (var day = 1; day <= daysInMonth; day++)
            (
              label: day % 5 == 0 || day == 1 ? '$day' : '',
              distanceMeters: distanceAt(
                DateTime(start.year, start.month, day),
              ),
            ),
        ];
      case StatsPeriod.year:
        const months = [
          'I',
          'II',
          'III',
          'IV',
          'V',
          'VI',
          'VII',
          'VIII',
          'IX',
          'X',
          'XI',
          'XII',
        ];
        return [
          for (var month = 1; month <= 12; month++)
            (
              label: months[month - 1],
              distanceMeters: distanceAt(DateTime(statistics.from.year, month)),
            ),
        ];
      case StatsPeriod.allTime:
        if (statistics.buckets.isEmpty) return const [];
        final firstYear = statistics.buckets.first.start.year;
        final lastYear = math.max(statistics.buckets.last.start.year, now.year);
        return [
          for (var year = firstYear; year <= lastYear; year++)
            (
              label: '$year'.substring(2),
              distanceMeters: distanceAt(DateTime(year)),
            ),
        ];
    }
  }
}

/// Kalendarz przejazdów: im dłuższy dystans, tym mocniejszy kolor dnia.
class RideCalendar extends StatelessWidget {
  const RideCalendar({
    super.key,
    required this.month,
    required this.days,
    this.onTapDay,
  });

  final DateTime month;
  final Map<DateTime, ({int rides, double distanceMeters})> days;
  final void Function(DateTime day)? onTapDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final maximum = days.values.fold<double>(
      0,
      (best, value) => math.max(best, value.distanceMeters),
    );

    return Column(
      children: [
        Row(
          children: [
            for (final label in ['pn', 'wt', 'śr', 'cz', 'pt', 'sb', 'nd'])
              Expanded(
                child: Center(
                  child: Text(label, style: LR.body.copyWith(fontSize: 10)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < ((leading + daysInMonth) / 7).ceil(); row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: _Day(
                    day: row * 7 + column - leading + 1,
                    daysInMonth: daysInMonth,
                    month: month,
                    days: days,
                    maximum: maximum,
                    onTap: onTapDay,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.daysInMonth,
    required this.month,
    required this.days,
    required this.maximum,
    required this.onTap,
  });

  final int day;
  final int daysInMonth;
  final DateTime month;
  final Map<DateTime, ({int rides, double distanceMeters})> days;
  final double maximum;
  final void Function(DateTime day)? onTap;

  @override
  Widget build(BuildContext context) {
    if (day < 1 || day > daysInMonth) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox.shrink());
    }
    final date = DateTime(month.year, month.month, day);
    final entry = days[date];
    final intensity = entry == null || maximum <= 0
        ? 0.0
        : (0.25 + entry.distanceMeters / maximum * 0.75).clamp(0.0, 1.0);

    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: entry == null || onTap == null ? null : () => onTap!(date),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: entry == null
                  ? LR.panel
                  : LR.accentDeep.withValues(alpha: intensity),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: LR.line),
            ),
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 11,
                fontWeight: entry == null ? FontWeight.w400 : FontWeight.w800,
                color: intensity > 0.55 ? Colors.white : LR.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
