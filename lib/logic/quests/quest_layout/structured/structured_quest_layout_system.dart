import 'dart:math';
import 'dart:ui';

import 'package:lumox/logic/quests/quest.dart';
import 'package:lumox/logic/quests/quest_system.dart';

/// ============================================================================
/// RADIAL QUEST LAYOUT ENGINE
/// ============================================================================
///
/// Ziele:
/// - organisches radial layout
/// - stabile physics
/// - echte rechteck-kollisionen
/// - parent-basierte verzweigungen
/// - pseudo-zufällige skill-tree optik
/// - weniger crossings
/// - bessere edge anchors
///
/// Inspiration:
/// - Path of Exile
/// - Civilization
/// - Sphere Grid
/// - Destiny
///
/// ============================================================================

class RadialQuestLayoutConfig {
  /// Abstand zwischen Depth-Ringen
  final double layerSpacing;

  /// Minimaler Abstand zwischen Nodes
  final double nodeSpacing;

  /// Physics
  final int physicsIterations;

  /// Stärke der Node-Abstoßung
  final double repulsionStrength;

  /// Stärke der Edge-Federn
  final double springStrength;

  /// Radius-Stabilisierung
  final double radialStrength;

  /// Randomness
  final int seed;
  final double angleJitter;

  /// Grid
  final bool snapToGrid;
  final double gridSize;

  const RadialQuestLayoutConfig({
    this.layerSpacing = 420,
    this.nodeSpacing = 80,

    this.physicsIterations = 160,

    this.repulsionStrength = 120000,
    this.springStrength = 0.018,
    this.radialStrength = 0.05,

    this.seed = 1337,
    this.angleJitter = 0.55,

    this.snapToGrid = false,
    this.gridSize = 40,
  });
}

class RadialQuestLayouter {
  final RadialQuestLayoutConfig config;

  RadialQuestLayouter({this.config = const RadialQuestLayoutConfig()});

  late Map<int, _LayoutNode> _nodes;
  late Random _random;

  /// ==========================================================================
  /// ENTRY
  /// ==========================================================================

  void layout(QuestSystem system) {
    _random = Random(config.seed);

    _buildGraph(system);

    _assignDepths();

    _assignAngles();

    _assignInitialPositions();

    _runPhysics();

    _removeOverlaps();

    if (config.snapToGrid) {
      _snapToGrid();
    }

    _writeBack(system);
  }

  /// ==========================================================================
  /// BUILD GRAPH
  /// ==========================================================================

  void _buildGraph(QuestSystem system) {
    _nodes = {};

    for (final quest in system.quests) {
      _nodes[quest.id] = _LayoutNode(quest: quest);
    }

    for (final quest in system.quests) {
      final prereqs = system.prerequisiteIds(quest.id);

      for (final prereqId in prereqs) {
        final from = _nodes[prereqId];
        final to = _nodes[quest.id];

        if (from == null || to == null) {
          continue;
        }

        from.outgoing.add(to);
        to.incoming.add(from);
      }
    }
  }

  /// ==========================================================================
  /// DEPTH ASSIGNMENT
  /// ==========================================================================

  void _assignDepths() {
    final roots = _nodes.values.where((n) => n.incoming.isEmpty).toList();

    final queue = <_LayoutNode>[];

    for (final root in roots) {
      root.depth = 0;
      root.angle = 0;
      queue.add(root);
    }

    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);

      for (final child in node.outgoing) {
        final nextDepth = node.depth + 1;

        if (nextDepth > child.depth) {
          child.depth = nextDepth;

          queue.add(child);
        }
      }
    }
  }

  /// ==========================================================================
  /// ANGLE PROPAGATION
  /// ==========================================================================

  void _assignAngles() {
    final roots = _nodes.values.where((n) => n.incoming.isEmpty).toList();

    final rootStep = (pi * 2) / max(1, roots.length);

    for (int i = 0; i < roots.length; i++) {
      roots[i].angle = i * rootStep;
    }

    final visited = <_LayoutNode>{};

    void propagate(_LayoutNode node) {
      if (visited.contains(node)) return;

      visited.add(node);

      final children = node.outgoing;

      if (children.isEmpty) return;

      const spread = 1.4;

      for (int i = 0; i < children.length; i++) {
        final child = children[i];

        final t = children.length == 1 ? 0.5 : i / (children.length - 1);

        final offset = lerpDouble(-spread, spread, t)!;

        child.angle = node.angle + offset + (_random.nextDouble() * 2 - 1) * config.angleJitter;

        propagate(child);
      }
    }

    for (final root in roots) {
      propagate(root);
    }
  }

  /// ==========================================================================
  /// INITIAL POSITIONING
  /// ==========================================================================

  void _assignInitialPositions() {
    for (final node in _nodes.values) {
      final radius = node.depth * config.layerSpacing + node.quest.difficulty * 120;

      node.x = cos(node.angle) * radius;
      node.y = sin(node.angle) * radius;
    }
  }

  /// ==========================================================================
  /// PHYSICS
  /// ==========================================================================

  void _runPhysics() {
    final nodes = _nodes.values.toList();

    for (int iteration = 0; iteration < config.physicsIterations; iteration++) {
      for (final node in nodes) {
        double fx = 0;
        double fy = 0;

        /// ================================================================
        /// REPULSION
        /// ================================================================

        for (final other in nodes) {
          if (node == other) continue;

          final dx = node.x - other.x;
          final dy = node.y - other.y;

          final distSq = dx * dx + dy * dy + 0.01;

          final force = config.repulsionStrength / distSq;

          fx += dx * force;
          fy += dy * force;
        }

        /// ================================================================
        /// EDGE SPRINGS
        /// ================================================================

        for (final neighbor in [...node.incoming, ...node.outgoing]) {
          final dx = neighbor.x - node.x;

          final dy = neighbor.y - node.y;

          fx += dx * config.springStrength;
          fy += dy * config.springStrength;
        }

        /// ================================================================
        /// RADIAL CONSTRAINT
        /// ================================================================

        final targetRadius = node.depth * config.layerSpacing;

        final currentRadius = sqrt(node.x * node.x + node.y * node.y);

        final radialDelta = targetRadius - currentRadius;

        if (currentRadius > 0.001) {
          fx += (node.x / currentRadius) * radialDelta * config.radialStrength;

          fy += (node.y / currentRadius) * radialDelta * config.radialStrength;
        }

        /// ================================================================
        /// APPLY
        /// ================================================================

        node.vx = (node.vx + fx * 0.003) * 0.82;

        node.vy = (node.vy + fy * 0.003) * 0.82;

        node.x += node.vx;
        node.y += node.vy;
      }
    }
  }

  /// ==========================================================================
  /// RECTANGLE OVERLAP REMOVAL
  /// ==========================================================================

  void _removeOverlaps() {
    final nodes = _nodes.values.toList();

    for (int iteration = 0; iteration < 60; iteration++) {
      bool moved = false;

      for (int i = 0; i < nodes.length; i++) {
        for (int j = i + 1; j < nodes.length; j++) {
          final a = nodes[i];
          final b = nodes[j];

          final overlapX = min(a.right, b.right) - max(a.left, b.left);

          final overlapY = min(a.bottom, b.bottom) - max(a.top, b.top);

          if (overlapX <= 0 || overlapY <= 0) {
            continue;
          }

          moved = true;

          if (overlapX < overlapY) {
            final push = overlapX / 2 + config.nodeSpacing;

            if (a.x < b.x) {
              a.x -= push;
              b.x += push;
            } else {
              a.x += push;
              b.x -= push;
            }
          } else {
            final push = overlapY / 2 + config.nodeSpacing;

            if (a.y < b.y) {
              a.y -= push;
              b.y += push;
            } else {
              a.y += push;
              b.y -= push;
            }
          }
        }
      }

      if (!moved) break;
    }
  }

  /// ==========================================================================
  /// GRID
  /// ==========================================================================

  void _snapToGrid() {
    for (final node in _nodes.values) {
      node.x = (node.x / config.gridSize).round() * config.gridSize;

      node.y = (node.y / config.gridSize).round() * config.gridSize;
    }
  }

  /// ==========================================================================
  /// WRITE BACK
  /// ==========================================================================

  void _writeBack(QuestSystem system) {
    for (final node in _nodes.values) {
      final oldQuest = system.getQuestById(node.quest.id);

      final updated = oldQuest.copyWith(posX: node.x, posY: node.y);

      system.upsertQuest(updated);
    }
  }

  /// ==========================================================================
  /// EDGE ANCHORS
  /// ==========================================================================

  Offset _edgePointTowards(_LayoutNode from, _LayoutNode to) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;

    final hw = from.quest.sizeX / 2;
    final hh = from.quest.sizeY / 2;

    final scaleX = dx == 0 ? double.infinity : hw / dx.abs();

    final scaleY = dy == 0 ? double.infinity : hh / dy.abs();

    final scale = min(scaleX, scaleY);

    return Offset(from.x + dx * scale, from.y + dy * scale);
  }
}

/// ============================================================================
/// INTERNAL NODE
/// ============================================================================

class _LayoutNode {
  final Quest quest;

  final List<_LayoutNode> incoming = [];
  final List<_LayoutNode> outgoing = [];

  int depth = 0;

  double angle = 0;

  double x = 0;
  double y = 0;

  double vx = 0;
  double vy = 0;

  _LayoutNode({required this.quest});

  double get left => x - quest.sizeX / 2;

  double get right => x + quest.sizeX / 2;

  double get top => y - quest.sizeY / 2;

  double get bottom => y + quest.sizeY / 2;
}
