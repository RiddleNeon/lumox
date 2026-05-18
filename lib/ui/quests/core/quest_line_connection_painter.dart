import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lumox/logic/quests/quest_system.dart';

import 'bezier_helper.dart';

class _ConnectionGeometry {
  const _ConnectionGeometry({
    required this.p0,
    required this.cp1,
    required this.cp2,
    required this.p3,
    required this.lut,
    required this.startColor,
    required this.endColor,
    required this.midPoint,
    required this.bounds,
  });

  final Offset p0, cp1, cp2, p3;
  final ArcLut lut;
  final Color startColor, endColor;

  final Offset midPoint;
  final Rect bounds;
}

class _CubicSplit {
  const _CubicSplit({
    required this.leftP0,
    required this.leftP1,
    required this.leftP2,
    required this.leftP3,
    required this.rightP0,
    required this.rightP1,
    required this.rightP2,
    required this.rightP3,
  });

  final Offset leftP0, leftP1, leftP2, leftP3;
  final Offset rightP0, rightP1, rightP2, rightP3;
}

class QuestLineConnectionPainter extends CustomPainter {
  QuestLineConnectionPainter({
    required this.questSystem,
    required this.animation,
    this.viewportRect,
    this.scale = 1.0,
    this.arrowHideScale = 0.2,
    this.pixelSpacing = 50.0,
    this.lineWidth = 3.5,
    this.borderWidth = 2.2,
    this.borderColor = const Color(0xFF0A0A0A),
    this.arrowSize = 9.0,
    this.derivedQuestColors,
  }) : super(repaint: animation);

  int? currentDraggedQuestId;
  Offset? currentDraggedQuestPos;

  int? connectionSourceId;
  Offset? connectionPreviewEnd;

  Rect? viewportRect;
  double scale;
  
  Map<int, Color>? derivedQuestColors;

  QuestSystem questSystem;
  final Animation<double> animation;

  final double arrowHideScale;
  final double pixelSpacing;
  final double lineWidth;
  final double borderWidth;
  final Color borderColor;
  final double arrowSize;

  final Map<(int, int), _ConnectionGeometry> _cache = {};
  final Map<String, Set<(int, int)>> _spatialIndex = {};

  static const double _spatialIndexCellSize = 180.0;

  void rebuildCache() {
    print("rebuilding cache!");
    _cache.clear();
    _spatialIndex.clear();
    for (final quest in questSystem.quests) {
      for (final prereq in questSystem.prerequisitesOf(quest.id)) {
        _buildAndStoreEntry(prereq.id, quest.id);
      }
    }
  }

  void rebuildCacheForQuest(int questId) {
    rebuildCache();
  }

  _ConnectionGeometry? _buildAndStoreEntry(int fromId, int toId) {
    final geom = _computeGeometry(fromId, toId, null, null);
    if (geom != null) {
      final key = (fromId, toId);
      _cache[key] = geom;
      _indexGeometry(key, geom.bounds);
    }
    return geom;
  }

  void _indexGeometry((int, int) key, Rect bounds) {
    final minCellX = (bounds.left / _spatialIndexCellSize).floor();
    final maxCellX = (bounds.right / _spatialIndexCellSize).floor();
    final minCellY = (bounds.top / _spatialIndexCellSize).floor();
    final maxCellY = (bounds.bottom / _spatialIndexCellSize).floor();

    for (int x = minCellX; x <= maxCellX; x++) {
      for (int y = minCellY; y <= maxCellY; y++) {
        final cellKey = _cellKey(x, y);
        _spatialIndex.putIfAbsent(cellKey, () => <(int, int)>{}).add(key);
      }
    }
  }

  String _cellKey(int x, int y) => '$x:$y';

  Iterable<(int, int)> _candidateConnections(Rect queryRect) sync* {
    if (_spatialIndex.isEmpty) return;

    final seen = <(int, int)>{};
    final minCellX = (queryRect.left / _spatialIndexCellSize).floor();
    final maxCellX = (queryRect.right / _spatialIndexCellSize).floor();
    final minCellY = (queryRect.top / _spatialIndexCellSize).floor();
    final maxCellY = (queryRect.bottom / _spatialIndexCellSize).floor();

    for (int x = minCellX; x <= maxCellX; x++) {
      for (int y = minCellY; y <= maxCellY; y++) {
        final candidates = _spatialIndex[_cellKey(x, y)];
        if (candidates == null) continue;
        for (final key in candidates) {
          if (seen.add(key)) {
            yield key;
          }
        }
      }
    }
  }

  ({int fromId, int toId, Offset midpoint})? hitTestConnection(
    Offset scenePos, {
    required double scale,
  }) {
    if (_cache.isEmpty) return null;

    final safeScale = scale <= 0 ? 1.0 : scale;
    final sceneHitRadius = max(18.0 / safeScale, (lineWidth + borderWidth) * 0.5 + 4.0 / safeScale);
    final queryRect = Rect.fromCircle(center: scenePos, radius: sceneHitRadius).inflate(4.0 / safeScale);

    ({int fromId, int toId, Offset midpoint})? best;
    double bestDistance = double.infinity;

    for (final key in _candidateConnections(queryRect)) {
      final geom = _cache[key];
      if (geom == null) continue;

      if (!geom.bounds.inflate(sceneHitRadius).overlaps(queryRect)) continue;

      final tolerance = max(0.2, sceneHitRadius / 8.0);
      final dist = _distanceToCubicBezier(scenePos, geom.p0, geom.cp1, geom.cp2, geom.p3, tolerance: tolerance);
      if (dist <= sceneHitRadius && dist < bestDistance) {
        bestDistance = dist;
        best = (fromId: key.$1, toId: key.$2, midpoint: geom.midPoint);
      }
    }

    return best;
  }

  double _distanceToCubicBezier(
    Offset point,
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3, {
    required double tolerance,
    int depth = 0,
  }) {
    final flatness = max(_distanceToLine(p1, p0, p3), _distanceToLine(p2, p0, p3));
    if (flatness <= tolerance || depth >= 12) {
      return _distanceToSegment(point, p0, p3);
    }

    final split = _splitCubic(p0, p1, p2, p3);
    return min(
      _distanceToCubicBezier(point, split.leftP0, split.leftP1, split.leftP2, split.leftP3, tolerance: tolerance, depth: depth + 1),
      _distanceToCubicBezier(point, split.rightP0, split.rightP1, split.rightP2, split.rightP3, tolerance: tolerance, depth: depth + 1),
    );
  }

  double _distanceToLine(Offset point, Offset lineStart, Offset lineEnd) {
    final segment = lineEnd - lineStart;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared == 0) return (point - lineStart).distance;

    final t = (((point.dx - lineStart.dx) * segment.dx) + ((point.dy - lineStart.dy) * segment.dy)) / lengthSquared;
    final projected = lineStart + segment * t;
    return (point - projected).distance;
  }

  double _distanceToSegment(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (point - a).distance;

    final t = (((point.dx - a.dx) * ab.dx) + ((point.dy - a.dy) * ab.dy)) / lengthSquared;
    final clampedT = t.clamp(0.0, 1.0);
    final projected = a + ab * clampedT;
    return (point - projected).distance;
  }

  _CubicSplit _splitCubic(Offset p0, Offset p1, Offset p2, Offset p3) {
    final p01 = (p0 + p1) * 0.5;
    final p12 = (p1 + p2) * 0.5;
    final p23 = (p2 + p3) * 0.5;
    final p012 = (p01 + p12) * 0.5;
    final p123 = (p12 + p23) * 0.5;
    final p0123 = (p012 + p123) * 0.5;

    return _CubicSplit(
      leftP0: p0,
      leftP1: p01,
      leftP2: p012,
      leftP3: p0123,
      rightP0: p0123,
      rightP1: p123,
      rightP2: p23,
      rightP3: p3,
    );
  }

  Rect _geometryBounds(Offset p0, Offset p1, Offset p2, Offset p3) {
    final left = min(min(p0.dx, p1.dx), min(p2.dx, p3.dx));
    final top = min(min(p0.dy, p1.dy), min(p2.dy, p3.dy));
    final right = max(max(p0.dx, p1.dx), max(p2.dx, p3.dx));
    final bottom = max(max(p0.dy, p1.dy), max(p2.dy, p3.dy));
    return Rect.fromLTRB(left, top, right, bottom);
  }

  _ConnectionGeometry? _computeGeometry(int fromId, int toId, int? draggedId, Offset? draggedPos) {
    final startCenter = getQuestCenter(fromId, questSystem, draggedId, draggedPos);
    final endCenter = getQuestCenter(toId, questSystem, draggedId, draggedPos);
    if (startCenter == null || endCenter == null) return null;

    final anchorStart = getBestAnchor(fromId, endCenter, questSystem, draggedId, draggedPos);
    final anchorEnd = getBestAnchor(toId, startCenter, questSystem, draggedId, draggedPos);

    final cps = calculateCubicControlPointsOffsetting(
      anchorStart.pos,
      anchorStart.sideDir,
      anchorEnd.pos,
      anchorEnd.sideDir,
      fromId,
      toId,
      questSystem,
      draggedPos,
      draggedId,
    );

    final p0 = anchorStart.pos;
    final cp1 = cps[0];
    final cp2 = cps[1];
    final p3 = anchorEnd.pos;

    final lut = getLut(p0, cp1, cp2, p3);
    final midPoint = bezierPoint(p0, cp1, cp2, p3, lut.tForArcLen(lut.totalLength / 2.0));

    return _ConnectionGeometry(
      p0: p0,
      cp1: cp1,
      cp2: cp2,
      p3: p3,
      lut: lut,
      startColor: glowColorOfQuest(fromId, questSystem),
      endColor: glowColorOfQuest(toId, questSystem),
      midPoint: midPoint,
      bounds: _geometryBounds(p0, cp1, cp2, p3),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pixelOffset = animation.value * pixelSpacing;
    final showArrows = scale >= arrowHideScale;
    final cullRect = viewportRect?.inflate(_cullPadding());

    for (final quest in questSystem.quests) {
      final prereqs = questSystem.prerequisitesOf(quest.id);
      if (prereqs.isEmpty) continue;

      for (final prereq in prereqs) {
        final connection = questSystem.getConnection(prereq.id, quest.id);
        if (connection == null) continue;

        final bool isDynamic = currentDraggedQuestId != null && (prereq.id == currentDraggedQuestId || quest.id == currentDraggedQuestId);

        final _ConnectionGeometry? geom;
        if (isDynamic) {
          geom = _computeGeometry(prereq.id, quest.id, currentDraggedQuestId, currentDraggedQuestPos);
        } else {
          geom = _cache[(prereq.id, quest.id)] ?? _buildAndStoreEntry(prereq.id, quest.id);
        }

        if (geom == null) continue;

        if (cullRect != null && !_aabbIntersects(cullRect, geom.p0, geom.cp1, geom.cp2, geom.p3)) {
          continue;
        }

        _drawBorderLine(canvas, geom.p0, geom.cp1, geom.cp2, geom.p3);
        _drawBaseLine(canvas, geom.p0, geom.cp1, geom.cp2, geom.p3, geom.startColor, geom.endColor);

        if (showArrows) {
          _drawMarchingArrows(canvas, geom.p0, geom.cp1, geom.cp2, geom.p3, geom.lut, pixelOffset, geom.startColor, geom.endColor, cullRect);
        }

        _drawLockedIndicator(canvas, geom.midPoint, Colors.grey, connection.xpRequirement.ceil(), false);
      }
    }

    if (connectionSourceId != null && connectionPreviewEnd != null) {
      final start = getQuestCenter(connectionSourceId!, questSystem, currentDraggedQuestId, currentDraggedQuestPos);
      if (start != null) {
        _drawConnectionPreview(canvas, start, connectionPreviewEnd!, glowColorOfQuest(connectionSourceId!, questSystem), connectionSourceId!);
      }
    }
  }

  //draws a lock icon with a given level requirement at the midpoint of the connection
  void _drawLockedIndicator(
      Canvas canvas,
      Offset center,
      Color color,
      int levelRequirement,
      bool isOpen
      ) {
    const lockSize = 40.0;

    final bodyPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shacklePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final shackleRect = Rect.fromCenter(
      center: center.translate(0, -lockSize * 0.2),
      width: lockSize * 0.6,
      height: lockSize * 0.7,
    );

    canvas.drawArc(shackleRect, pi * (isOpen ? 0.7 : 1), pi, false, shacklePaint);

    final bodyRect = Rect.fromCenter(
      center: center.translate(0, lockSize * 0.2),
      width: lockSize * 0.95,
      height: lockSize * 0.85,
    );

    final bodyRRect = RRect.fromRectAndRadius(
      bodyRect,
      const Radius.circular(10),
    );

    canvas.drawRRect(bodyRRect, bodyPaint);
    canvas.drawRRect(bodyRRect, outlinePaint);

    final highlightRect = Rect.fromLTWH(
      bodyRect.left,
      bodyRect.top,
      bodyRect.width,
      bodyRect.height * 0.4,
    );

    final highlightPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.25),
          Colors.transparent,
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(highlightRect);

    canvas.drawRRect(bodyRRect, highlightPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '$levelRequirement',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(
              blurRadius: 2,
              offset: Offset(0, 1),
              color: Colors.black54,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = center.translate(
      -textPainter.width / 2,
      lockSize*0.01,
    );

    textPainter.paint(canvas, textOffset);
  }

  double _cullPadding() => (arrowSize * 2.0) / scale.clamp(0.01, double.infinity);

  bool _aabbIntersects(Rect r, Offset p0, Offset p1, Offset p2, Offset p3) {
    final minX = [p0.dx, p1.dx, p2.dx, p3.dx].reduce((a, b) => a < b ? a : b);
    final minY = [p0.dy, p1.dy, p2.dy, p3.dy].reduce((a, b) => a < b ? a : b);
    final maxX = [p0.dx, p1.dx, p2.dx, p3.dx].reduce((a, b) => a > b ? a : b);
    final maxY = [p0.dy, p1.dy, p2.dy, p3.dy].reduce((a, b) => a > b ? a : b);
    return !(maxX < r.left || minX > r.right || maxY < r.top || minY > r.bottom);
  }

  void _drawBorderLine(Canvas canvas, Offset p0, Offset p1, Offset p2, Offset p3) {
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor.withValues(alpha: 0.8)
        ..strokeWidth = lineWidth + borderWidth * 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawBaseLine(Canvas canvas, Offset p0, Offset p1, Offset p2, Offset p3, Color c0, Color c1) {
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(p0, p3, [c0.withValues(alpha: 0.45), c1.withValues(alpha: 0.45)])
        ..strokeWidth = lineWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawMarchingArrows(
    Canvas canvas,
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    ArcLut lut,
    double pixelOffset,
    Color startColor,
    Color endColor,
    Rect? cullRect,
  ) {
    final totalLen = lut.totalLength;
    if (totalLen < 1) return;

    final arrowWorldSize = arrowSize / scale.clamp(0.01, double.infinity);
    final arrowCullRect = cullRect?.inflate(arrowWorldSize);

    double arcPos = pixelOffset;
    while (arcPos < totalLen) {
      final progress = arcPos / totalLen;
      final t = lut.tForArcLen(arcPos);
      final pos = bezierPoint(p0, p1, p2, p3, t);

      if (arrowCullRect != null && !arrowCullRect.contains(pos)) {
        arcPos += pixelSpacing;
        continue;
      }

      final fadeAlpha = _edgeFade(progress);
      final tangent = _bezierTangent(p0, p1, p2, p3, t);

      if (tangent.distance > 0.001) {
        final dir = tangent / tangent.distance;
        final color = Color.lerp(startColor, endColor, progress)!;
        _drawArrowHead(canvas, pos, dir, color, fadeAlpha);
      }

      arcPos += pixelSpacing;
    }
  }

  double _edgeFade(double progress) {
    const fadeZone = 0.07;
    if (progress < fadeZone) return progress / fadeZone;
    if (progress > 1.0 - fadeZone) return (1.0 - progress) / fadeZone;
    return 1.0;
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Offset dir, Color color, double alpha) {
    final perp = Offset(-dir.dy, dir.dx);
    final base = tip - dir * arrowSize;
    final left = base + perp * (arrowSize * 0.48);
    final right = base - perp * (arrowSize * 0.48);

    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = borderColor.withValues(alpha: alpha * 0.60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth * 1.2
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = color.withValues(alpha: alpha * 0.92)
        ..style = PaintingStyle.fill,
    );
  }

  Offset _bezierTangent(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final mt = 1.0 - t;
    return (p1 - p0) * (3 * mt * mt) + (p2 - p1) * (6 * mt * t) + (p3 - p2) * (3 * t * t);
  }

  void _drawConnectionPreview(Canvas canvas, Offset start, Offset end, Color color, int connectionId) {
    final pixelOffset = animation.value * pixelSpacing;
    final showArrows = scale >= arrowHideScale;
    final cullRect = viewportRect?.inflate(_cullPadding());

    final anchorStart = getBestAnchor(connectionId, end, questSystem, currentDraggedQuestId, currentDraggedQuestPos);
    final anchorEnd = Anchor(end, ui.Offset.zero);

    final cps = calculateCubicControlPoints(anchorStart.pos, anchorStart.sideDir, anchorEnd.pos, anchorEnd.sideDir);

    final p0 = anchorStart.pos;
    final cp1 = cps[0];
    final cp2 = cps[1];
    final p3 = anchorEnd.pos;

    if (cullRect != null && !_aabbIntersects(cullRect, start, cp1, cp2, end)) {
      return;
    }

    final lut = getLut(p0, cp1, cp2, p3);
    _drawBorderLine(canvas, p0, cp1, cp2, p3);
    _drawBaseLine(canvas, p0, cp1, cp2, p3, color, color);

    if (showArrows) {
      _drawMarchingArrows(canvas, p0, cp1, cp2, p3, lut, pixelOffset, color, color, cullRect);
    }
  }

  @override
  bool shouldRepaint(covariant QuestLineConnectionPainter old) =>
      old.currentDraggedQuestId != currentDraggedQuestId ||
      old.currentDraggedQuestPos != currentDraggedQuestPos ||
      old.connectionSourceId != connectionSourceId ||
      old.connectionPreviewEnd != connectionPreviewEnd ||
      old.viewportRect != viewportRect ||
      old.scale != scale ||
      old.animation.value != animation.value;
  
  void recomputeGlowColors(){
    glowColors.clear();
    rebuildCache();
  }

  Color glowColorOfQuest(int id, QuestSystem system) {
    if (glowColors.containsKey(id)) return glowColors[id]!;
    
    final hsl = HSLColor.fromColor(derivedQuestColors?[id] ?? system.getQuestById(id).color);
    final color = hsl.withLightness(0.65).withSaturation(0.75).toColor();
    return glowColors[id] = color;
  }

  Map<int, Color> glowColors = {};
}