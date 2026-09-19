import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../models/ride_data_field.dart';

/// The Garmin-style data field block.
///
/// Fields are separated by hairlines, values are as large as the cell allows
/// and nothing decorates the numbers. The red rule along the top edge is the
/// only accent — it marks where the instrument starts and the map ends.
class RideDataGrid extends StatelessWidget {
  const RideDataGrid({
    super.key,
    required this.fields,
    required this.layout,
    required this.data,
    this.onFieldTap,
    this.compact = false,
  });

  final List<RideDataField> fields;
  final RideFieldLayout layout;
  final RideFieldContext data;
  final void Function(int index)? onFieldTap;

  /// Slightly shorter rows, used when the map needs the space.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final columns = layout.columns;
    final rows = <Widget>[];
    for (var row = 0; row < layout.rows; row++) {
      final cells = <Widget>[];
      for (var column = 0; column < columns; column++) {
        final index = row * columns + column;
        if (index >= fields.length) break;
        if (column > 0) {
          cells.add(const VerticalDivider(width: 1, color: LR.line));
        }
        cells.add(
          Expanded(
            child: _DataCell(
              field: fields[index],
              value: fields[index].read(data),
              rows: layout.rows,
              compact: compact,
              onTap: onFieldTap == null ? null : () => onFieldTap!(index),
            ),
          ),
        );
      }
      rows.add(
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: row == 0
                  ? null
                  : const Border(top: BorderSide(color: LR.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cells,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: LR.surface,
        border: Border(top: BorderSide(color: LR.alert, width: 2)),
      ),
      child: Column(children: rows),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({
    required this.field,
    required this.value,
    required this.rows,
    required this.compact,
    this.onTap,
  });

  final RideDataField field;
  final RideFieldValue value;
  final int rows;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        // The value fills the cell: a two-field layout gets the huge readout a
        // cycling computer shows at speed, eight fields get a compact one.
        final valueSize = (height * (rows <= 2 ? 0.52 : 0.46)).clamp(
          20.0,
          compact ? 58.0 : 84.0,
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            compact ? 8 : 10,
            12,
            compact ? 8 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  if (field.icon != null) ...[
                    Icon(
                      field.icon,
                      size: 11,
                      color: field == RideDataField.heartRate
                          ? LR.alert
                          : LR.muted,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      field.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LR.fieldLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        value.value,
                        style: LR
                            .fieldValue(valueSize)
                            .copyWith(color: value.alert ? LR.alert : LR.ink),
                      ),
                      if (value.unit.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Text(
                          value.unit,
                          style: LR.fieldUnit.copyWith(
                            fontSize: (valueSize * 0.26).clamp(11.0, 18.0),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: body),
    );
  }
}
