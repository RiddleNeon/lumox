import 'package:flutter/material.dart';
import 'package:shimmer_animation/shimmer_animation.dart';

class ShimmerBlock extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Color? color;
  final bool isCircle;

  const ShimmerBlock({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.color,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = isCircle ? null : (borderRadius ?? BorderRadius.circular(12));
    return Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color ?? cs.surfaceContainerHighest,
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: radius,
        ),
      ),
    );
  }
}
