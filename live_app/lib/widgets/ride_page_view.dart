import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../models/ride_data_field.dart';
import '../models/ride_pages.dart';
import 'ride_data_grid.dart';

/// Strony komputera rowerowego przesuwane palcem w bok.
///
/// Wysokość bierze się z układu aktualnej strony, żeby strona z dwoma polami
/// oddała mapie miejsce, którego strona z ośmioma potrzebuje.
class RidePageView extends StatefulWidget {
  const RidePageView({
    super.key,
    required this.pages,
    required this.data,
    required this.height,
    this.onFieldTap,
    this.onFieldLongPress,
    this.onPageChanged,
    this.showIndicator = true,
    this.compactThreshold = 2,
  });

  final List<RideDataPage> pages;
  final RideFieldContext data;

  /// Wysokość przyznana przez ekran — już po jego ograniczeniach.
  final double height;

  final void Function(int page, int field)? onFieldTap;
  final void Function(int page, int field)? onFieldLongPress;
  final void Function(int page)? onPageChanged;

  /// Kropki stron. Chowają się razem z resztą sterowania.
  final bool showIndicator;

  final int compactThreshold;

  @override
  State<RidePageView> createState() => RidePageViewState();
}

class RidePageViewState extends State<RidePageView> {
  late final PageController _controller = PageController();
  int _index = 0;

  int get pageIndex => _index;

  @override
  void didUpdateWidget(RidePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.pages.length) {
      _index = widget.pages.isEmpty ? 0 : widget.pages.length - 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void goTo(int index) {
    if (index < 0 || index >= widget.pages.length) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.pages.length,
            onPageChanged: (index) {
              setState(() => _index = index);
              widget.onPageChanged?.call(index);
            },
            itemBuilder: (context, index) {
              final page = widget.pages[index];
              return RideDataGrid(
                fields: page.activeFields,
                layout: page.layout,
                compact: page.layout.rows > widget.compactThreshold,
                data: widget.data,
                onFieldTap: widget.onFieldTap == null
                    ? null
                    : (field) => widget.onFieldTap!(index, field),
                onFieldLongPress: widget.onFieldLongPress == null
                    ? null
                    : (field) => widget.onFieldLongPress!(index, field),
              );
            },
          ),
          if (widget.showIndicator && widget.pages.length > 1)
            Positioned(
              top: 4,
              left: 0,
              right: 0,
              child: _PageDots(count: widget.pages.length, index: _index),
            ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == index ? 14 : 5,
          height: 5,
          decoration: BoxDecoration(
            color: i == index ? LR.accentDeep : LR.lineStrong,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );
}
