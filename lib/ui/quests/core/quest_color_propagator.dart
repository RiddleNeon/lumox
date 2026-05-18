import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lumox/logic/quests/quest.dart';

const int kNoColorValue = 0xFFFFFFFF;

class QuestColorPropagator {
  QuestColorPropagator._();
  
  static bool isColorless(Color c) => c.toARGB32() == kNoColorValue;

  static Map<int, List<int>> buildAdjacency({
    required List<Quest> quests,
    required List<Quest> Function(int questId) prerequisiteResolver,
  }) {
    final adj = <int, List<int>>{for (final q in quests) q.id: []};

    for (final quest in quests) {
      for (final prereq in prerequisiteResolver(quest.id)) {
        if (!adj[quest.id]!.contains(prereq.id)) {
          adj[quest.id]!.add(prereq.id);
        }
        adj[prereq.id] ??= [];
        if (!adj[prereq.id]!.contains(quest.id)) {
          adj[prereq.id]!.add(quest.id);
        }
      }
    }

    return adj;
  }


  static Map<int, Color> compute({
    required List<Quest> quests,
    required Map<int, List<int>> adjacency,
  }) {
    final byId = <int, Quest>{for (final q in quests) q.id: q};
    final seeds = quests.where((q) => !isColorless(q.color)).toList();

    if (seeds.isEmpty) return {for (final q in quests) q.id: q.color};


    final weights = <int, Map<int, double>>{};
    for (final q in quests) {
      weights[q.id] = {};
      for (final nId in (adjacency[q.id] ?? [])) {
        final neighbor = byId[nId];
        if (neighbor == null) continue;
        weights[q.id]![nId] = 1.0 / _pixelDist(q, neighbor).clamp(1.0, double.infinity);
      }
    }

    var bufR = <int, double?>{};
    var bufG = <int, double?>{};
    var bufB = <int, double?>{};

    for (final seed in seeds) {
      final (sr, sg, sb) = _toLinear(seed.color);
      bufR[seed.id] = sr;
      bufG[seed.id] = sg;
      bufB[seed.id] = sb;
    }
    
    const maxIter = 80;
    const eps = 0.5 / 255.0;

    for (var iter = 0; iter < maxIter; iter++) {
      var maxDelta = 0.0;

      final nextR = Map<int, double?>.from(bufR);
      final nextG = Map<int, double?>.from(bufG);
      final nextB = Map<int, double?>.from(bufB);

      for (final q in quests) {
        if (!isColorless(q.color)) continue;

        double wSum = 0, rAcc = 0, gAcc = 0, bAcc = 0;

        for (final nId in (adjacency[q.id] ?? [])) {
          final rN = bufR[nId];
          if (rN == null) continue;
          final w = weights[q.id]![nId] ?? 0.0;
          rAcc += w * rN;
          gAcc += w * bufG[nId]!;
          bAcc += w * bufB[nId]!;
          wSum += w;
        }

        if (wSum <= 0) continue;

        final newR = rAcc / wSum;
        final newG = gAcc / wSum;
        final newB = bAcc / wSum;

        maxDelta = max(maxDelta, (newR - (bufR[q.id] ?? 0.0)).abs());
        maxDelta = max(maxDelta, (newG - (bufG[q.id] ?? 0.0)).abs());
        maxDelta = max(maxDelta, (newB - (bufB[q.id] ?? 0.0)).abs());

        nextR[q.id] = newR;
        nextG[q.id] = newG;
        nextB[q.id] = newB;
      }

      bufR = nextR;
      bufG = nextG;
      bufB = nextB;

      if (maxDelta < eps) break;
    }
    
    final result = <int, Color>{};

    for (final q in quests) {
      if (!isColorless(q.color)) {
        result[q.id] = q.color;
        continue;
      }

      final rV = bufR[q.id];
      if (rV == null) {
        result[q.id] = const Color(kNoColorValue);
        continue;
      }

      Color color = _fromLinear(rV, bufG[q.id]!, bufB[q.id]!);

      final neighbors = adjacency[q.id] ?? [];
      double wSum = 0, wMax = 0;
      for (final nId in neighbors) {
        final rN = bufR[nId];
        if (rN == null) continue;
        final w = weights[q.id]![nId] ?? 0.0;
        wSum += w;
        if (w > wMax) wMax = w;
      }

      final blend = wSum > 0 ? 1.0 - (wMax / wSum) : 0.0;


      final maxHueShift = 6.0 * (blend * 2.0) * (blend * 2.0);

      if (maxHueShift > 0.3) {
        color = _applyHueVariation(color, maxHueShift, q.id);
      }

      result[q.id] = color;
    }

    return result;
  }
  
  static (double, double, double) _toLinear(Color c) => (
  _chanToLinear(c.r),
  _chanToLinear(c.g),
  _chanToLinear(c.b),
  );

  static double _chanToLinear(double v) =>
      v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();

  static Color _fromLinear(double r, double g, double b) => Color.from(
    alpha: 1.0,
    red: _chanToSrgb(r.clamp(0.0, 1.0)),
    green: _chanToSrgb(g.clamp(0.0, 1.0)),
    blue: _chanToSrgb(b.clamp(0.0, 1.0)),
  );

  static double _chanToSrgb(double v) =>
      v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055;


  static double _pixelDist(Quest a, Quest b) {
    final dx = (a.posX + a.sizeX / 2) - (b.posX + b.sizeX / 2);
    final dy = (a.posY + a.sizeY / 2) - (b.posY + b.sizeY / 2);
    return sqrt(dx * dx + dy * dy);
  }
  
  static Color _applyHueVariation(Color color, double maxHueShift, int questId) {
    final hsl = HSLColor.fromColor(color);
    final rng = Random(questId * 0x9e3779b9);
    final hueShift = (rng.nextDouble() * 2.0 - 1.0) * maxHueShift;
    final satShift = (rng.nextDouble() * 2.0 - 1.0) * 0.06;
    return HSLColor.fromAHSL(
      1.0,
      (hsl.hue + hueShift + 360.0) % 360.0,
      (hsl.saturation + satShift).clamp(0.25, 1.0),
      hsl.lightness,
    ).toColor();
  }
}