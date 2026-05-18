import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ScrollArea extends StatelessWidget {
  const ScrollArea({super.key, required this.scrollController, required this.child});

  final ScrollController scrollController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          if (!scrollController.hasClients) return;
          final position = scrollController.positions.last;
          final newOffset = (position.pixels + event.scrollDelta.dy * 1.8).clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
          position.animateTo(newOffset, duration: const Duration(milliseconds: 180), curve: Curves.easeOutCubic);
        }
      },
      child: child,
    );
  }
}

class SmoothScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};
}
