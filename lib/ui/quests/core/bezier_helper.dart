import 'dart:ui';

import 'package:lumox/logic/quests/quest_system.dart';

Offset bezierPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final mt = 1.0 - t;
  return p0 * (mt * mt * mt) + p1 * (3 * mt * mt * t) + p2 * (3 * mt * t * t) + p3 * (t * t * t);
}

List<Offset> calculateCubicControlPointsOffsetting(
  Offset pStart,
  Offset dirStart,
  Offset pEnd,
  Offset dirEnd,
  int sourceId,
  int targetId,
  QuestSystem questSystem,
  Offset? currentDraggedQuestPos,
  int? currentDraggedQuestId,
) {
  final delta = pEnd - pStart;
  final dist = delta.distance;
  final tension = (dist * 0.4).clamp(30.0, 200.0);

  Offset cp1 = pStart + dirStart * tension;
  Offset cp2 = pEnd + dirEnd * tension;

  final int lowId = sourceId < targetId ? sourceId : targetId;
  final int highId = sourceId < targetId ? targetId : sourceId;

  final pLow = getQuestCenter(lowId, questSystem, currentDraggedQuestId, currentDraggedQuestPos)!;
  final pHigh = getQuestCenter(highId, questSystem, currentDraggedQuestId, currentDraggedQuestPos)!;
  final refDelta = pHigh - pLow;
  final refDist = refDelta.distance;

  if (refDist > 1.0) {
    final perp = Offset(-refDelta.dy, refDelta.dx) / refDist;

    final double side = (sourceId == lowId) ? 1.0 : -1.0;

    double pushAmount = (dist * 0.2).clamp(10.0, 60.0);

    bool hasReverse = questSystem.isConnected(sourceId, targetId) && questSystem.isConnected(targetId, sourceId);
    if (!hasReverse) {
      pushAmount = 0;
    }

    cp1 += perp * (pushAmount * side);
    cp2 += perp * (pushAmount * side);
  }

  return [cp1, cp2];
}

List<Offset> calculateCubicControlPoints(Offset pStart, Offset dirStart, Offset pEnd, Offset dirEnd) {
  final dist = (pEnd - pStart).distance;
  final tension = (dist * 0.4).clamp(30.0, 200.0);

  return [pStart + dirStart * tension, pEnd + dirEnd * tension];
}

const int _kLutSamples = 64;
const int _kMaxCacheEntries = 256;
final Map<String, ArcLut> _lutCache = {};

ArcLut getLut(Offset p0, Offset p1, Offset p2, Offset p3) {
  final key =
      '${p0.dx.round()},${p0.dy.round()},'
      '${p1.dx.round()},${p1.dy.round()},'
      '${p2.dx.round()},${p2.dy.round()},'
      '${p3.dx.round()},${p3.dy.round()}';

  var lut = _lutCache[key];
  if (lut != null) return lut;

  if (_lutCache.length >= _kMaxCacheEntries) _lutCache.clear();

  lut = ArcLut.build(p0, p1, p2, p3, _kLutSamples, bezierPoint);
  _lutCache[key] = lut;
  return lut;
}

class ArcLut {
  final List<double> _data;

  double get totalLength => _data[_data.length - 1];

  const ArcLut._(this._data);

  factory ArcLut.build(Offset p0, Offset p1, Offset p2, Offset p3, int samples, Offset Function(Offset, Offset, Offset, Offset, double) bezierPoint) {
    final data = List<double>.filled((samples + 1) * 2, 0.0);
    var cumLen = 0.0;
    var prev = p0;
    for (int i = 0; i <= samples; i++) {
      final t = i / samples;
      final pt = bezierPoint(p0, p1, p2, p3, t);
      if (i > 0) cumLen += (pt - prev).distance;
      data[i * 2] = t;
      data[i * 2 + 1] = cumLen;
      prev = pt;
    }
    return ArcLut._(data);
  }

  double tForArcLen(double arcLen) {
    final total = totalLength;
    if (arcLen <= 0) return 0;
    if (arcLen >= total) return 1;

    int lo = 0, hi = (_data.length ~/ 2) - 1;
    while (lo + 1 < hi) {
      final mid = (lo + hi) >> 1;
      if (_data[mid * 2 + 1] < arcLen) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final len0 = _data[lo * 2 + 1];
    final len1 = _data[hi * 2 + 1];
    final t0 = _data[lo * 2];
    final t1 = _data[hi * 2];
    return t0 + (t1 - t0) * ((arcLen - len0) / (len1 - len0));
  }
}

class Anchor {
  final Offset pos;
  final Offset sideDir;

  Anchor(this.pos, this.sideDir);
}

Anchor getBestAnchor(int id, Offset targetCenter, QuestSystem questSystem, int? currentDraggedQuestId, Offset? currentDraggedQuestPos) {
  final quest = questSystem.maybeGetQuestById(id);
  if (quest == null) return Anchor(Offset.zero, Offset.zero);

  final pos = (id == currentDraggedQuestId && currentDraggedQuestPos != null) ? currentDraggedQuestPos : quest.position;

  final double w = quest.sizeX;
  final double h = quest.sizeY;
  final Offset center = pos + Offset(w / 2, h / 2);

  final dx = targetCenter.dx - center.dx;
  final dy = targetCenter.dy - center.dy;

  if ((dx / w).abs() > (dy / h).abs()) {
    if (dx > 0) {
      return Anchor(Offset(pos.dx + w, center.dy), const Offset(1, 0));
    } else {
      return Anchor(Offset(pos.dx, center.dy), const Offset(-1, 0));
    }
  } else {
    if (dy > 0) {
      return Anchor(Offset(center.dx, pos.dy + h), const Offset(0, 1));
    } else {
      return Anchor(Offset(center.dx, pos.dy), const Offset(0, -1));
    }
  }
}

Offset? getQuestCenter(int id, QuestSystem questSystem, int? currentDraggedQuestId, Offset? currentDraggedQuestPos) {
  final quest = questSystem.maybeGetQuestById(id);
  if (quest == null) return null;
  final pos = (id == currentDraggedQuestId && currentDraggedQuestPos != null) ? currentDraggedQuestPos : quest.position;
  return pos + Offset(quest.sizeX, quest.sizeY) / 2;
}
