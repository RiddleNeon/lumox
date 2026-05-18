import 'package:flutter/material.dart';
import 'package:lumox/logic/quests/quest.dart';

const double kConnectionHandleRadius = 12.0;

class QuestBubble extends StatelessWidget {
  final bool debugMode;
  final Quest quest;

  final Color effectiveColor;

  final bool isConnectionSource;
  final bool isConnectionTarget;
  final ColorScheme cs;

  const QuestBubble({
    super.key,
    required this.quest,
    required this.effectiveColor,
    this.isConnectionSource = false,
    this.isConnectionTarget = false,
    this.debugMode = false,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = effectiveColor;
    final glowColor = _adjustColor(baseColor, lightness: 0.60, saturation: 0.75);

    final borderColor = isConnectionSource
        ? glowColor
        : isConnectionTarget
        ? Colors.white.withValues(alpha: 0.85)
        : glowColor.withValues(alpha: 0.45);

    final borderWidth = (isConnectionSource || isConnectionTarget) ? 2.5 : 1.5;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: quest.sizeX,
          height: quest.sizeY,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(quest.sizeY / 2),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [baseColor, baseColor]),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: isConnectionTarget
                ? [BoxShadow(color: glowColor.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: 3)]
                : isConnectionSource
                ? [BoxShadow(color: glowColor.withValues(alpha: 0.4), blurRadius: 12)]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(quest.sizeY / 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    quest.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.4, height: 1.35),
                  ),
                  const SizedBox(height: 5),
                ],
              ),
            ),
          ),
        ),

        if (debugMode)
          Positioned(
            right: -kConnectionHandleRadius,
            top: quest.sizeY / 2 - kConnectionHandleRadius,
            child: _ConnectionHandle(color: glowColor, active: isConnectionSource),
          ),
      ],
    );
  }
}

class _ConnectionHandle extends StatelessWidget {
  const _ConnectionHandle({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const size = kConnectionHandleRadius * 2;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : color.withValues(alpha: 0.70),
        border: Border.all(color: Colors.white.withValues(alpha: active ? 0.85 : 0.40), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: active ? 0.75 : 0.35),
            blurRadius: active ? 12 : 6,
          ),
        ],
      ),
      child: Icon(Icons.add, size: 13, color: Colors.white.withValues(alpha: active ? 1.0 : 0.75)),
    );
  }
}

Color _adjustColor(Color color, {double? lightness, double? saturation}) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness(lightness ?? hsl.lightness).withSaturation(saturation ?? hsl.saturation).toColor();
}
