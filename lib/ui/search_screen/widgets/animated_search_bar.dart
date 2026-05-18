import 'package:flutter/material.dart';

class AnimatedSearchBar extends StatelessWidget {
  const AnimatedSearchBar({super.key, required this.visibility, required this.slotHeight, required this.child});

  final double visibility;
  final double slotHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: visibility,
        child: Opacity(
          opacity: visibility,
          child: SizedBox(height: slotHeight, child: child),
        ),
      ),
    );
  }
}
