import 'dart:math';
import 'dart:ui';

import 'package:lumox/logic/quests/quest.dart';
import 'package:lumox/logic/quests/quest_connection.dart';
import 'package:lumox/logic/quests/quest_system.dart';

/// ============================================================================
/// STRUCTURED QUEST LAYOUT ENGINE
/// ============================================================================
///
/// Ziel:
/// - deterministisches Layout
/// - perfekte Layer-Struktur
/// - stabile Symmetrie
/// - kaum Edge Crossings
/// - keine Physics-Zufälligkeit
/// - große Graphen performant
///
/// Architektur:
/// 1. Graph Analysis
/// 2. Layer Assignment
/// 3. Symmetry Detection
/// 4. Crossing Minimization
/// 5. Deterministic Placement
/// 6. Orthogonal Cleanup
/// 7. Optional Physics Polish
///
/// ============================================================================

class StructuredQuestLayoutConfig {
  /// Core
  final double layerSpacing;
  final double nodeSpacing;
  final double clusterSpacing;

  /// Grid
  final bool snapToGrid;
  final double gridSize;

  /// Symmetry
  final bool enableSymmetry;
  final bool mirrorSymmetry;
  final bool radialSymmetry;

  /// Hubs
  final bool enableHubClusters;
  final int hubMinConnections;
  final double hubRadius;

  /// Crossing minimization
  final int crossingIterations;

  /// Physics polish
  final bool enablePhysicsPolish;
  final int polishIterations;
  final double polishStrength;

  /// Routing
  final bool orthogonalRouting;
  final bool forceLayerAlignment;

  /// Cleanup
  final bool removeOverlaps;
  final bool compactLayout;
  final bool straightenChains;

  const StructuredQuestLayoutConfig({
    this.layerSpacing = 500,
    this.nodeSpacing = 220,
    this.clusterSpacing = 700,

    this.snapToGrid = true,
    this.gridSize = 40,

    this.enableSymmetry = true,
    this.mirrorSymmetry = true,
    this.radialSymmetry = true,

    this.enableHubClusters = true,
    this.hubMinConnections = 5,
    this.hubRadius = 420,

    this.crossingIterations = 12,

    this.enablePhysicsPolish = true,
    this.polishIterations = 40,
    this.polishStrength = 0.12,

    this.orthogonalRouting = true,
    this.forceLayerAlignment = true,

    this.removeOverlaps = true,
    this.compactLayout = true,
    this.straightenChains = true,
  });
}

class StructuredQuestLayouter {
  final StructuredQuestLayoutConfig config;

  StructuredQuestLayouter({
    this.config = const StructuredQuestLayoutConfig(),
  });

  late Map<int, _LayoutNode> _nodes;

  /// ==========================================================================
  /// PUBLIC ENTRY
  /// ==========================================================================

  void layout(QuestSystem system) {
    _buildNodes(system);

    _assignLayers();

    _minimizeCrossings();

    _assignInitialPositions();

    if (config.enableSymmetry) {
      _applySymmetry();
    }

    if (config.enableHubClusters) {
      _applyHubClusters();
    }

    if (config.straightenChains) {
      _straightenChains();
    }

    if (config.removeOverlaps) {
      _removeOverlaps();
    }

    if (config.compactLayout) {
      _compactLayout();
    }

    if (config.enablePhysicsPolish) {
      _physicsPolish();
    }

    if (config.snapToGrid) {
      _snapToGrid();
    }

    _writeBack(system);
  }

  /// ==========================================================================
  /// BUILD GRAPH
  /// ==========================================================================

  void _buildNodes(QuestSystem system) {
    _nodes = {};

    for (final quest in system.quests) {
      _nodes[quest.id] = _LayoutNode(
        quest: quest,
      );
    }

    for (final conn in system.quests.expand((q) {
      return system
          .prerequisiteIds(q.id)
          .map((p) => QuestConnection(
        fromQuestId: p,
        toQuestId: q.id,
      ));
    })) {
      final from = _nodes[conn.fromQuestId];
      final to = _nodes[conn.toQuestId];

      if (from == null || to == null) continue;

      from.outgoing.add(to);
      to.incoming.add(from);
    }
  }

  /// ==========================================================================
  /// LAYER ASSIGNMENT
  /// ==========================================================================

  void _assignLayers() {
    final roots = _nodes.values.where((n) => n.incoming.isEmpty);

    final queue = <_LayoutNode>[];

    for (final root in roots) {
      root.layer = 0;
      queue.add(root);
    }

    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);

      for (final child in node.outgoing) {
        final newLayer = node.layer + 1;

        if (newLayer > child.layer) {
          child.layer = newLayer;
          queue.add(child);
        }
      }
    }
  }

  /// ==========================================================================
  /// CROSSING MINIMIZATION
  /// ==========================================================================

  void _minimizeCrossings() {
    final layers = _layers();

    for (int iteration = 0;
    iteration < config.crossingIterations;
    iteration++) {
      for (int l = 1; l < layers.length; l++) {
        final layer = layers[l];

        layer.sort((a, b) {
          final ac = _barycenter(a.incoming);
          final bc = _barycenter(b.incoming);

          return ac.compareTo(bc);
        });
      }

      for (int l = layers.length - 2; l >= 0; l--) {
        final layer = layers[l];

        layer.sort((a, b) {
          final ac = _barycenter(a.outgoing);
          final bc = _barycenter(b.outgoing);

          return ac.compareTo(bc);
        });
      }
    }
  }

  double _barycenter(List<_LayoutNode> nodes) {
    if (nodes.isEmpty) return 0;

    double sum = 0;

    for (final n in nodes) {
      sum += n.order.toDouble();
    }

    return sum / nodes.length;
  }

  /// ==========================================================================
  /// INITIAL PLACEMENT
  /// ==========================================================================

  void _assignInitialPositions() {
    final layers = _layers();

    for (int layerIndex = 0;
    layerIndex < layers.length;
    layerIndex++) {
      final layer = layers[layerIndex];

      for (int i = 0; i < layer.length; i++) {
        final node = layer[i];

        node.order = i;

        node.x = layerIndex * config.layerSpacing;
        node.y = i * config.nodeSpacing;
      }

      _centerLayer(layer);
    }
  }

  void _centerLayer(List<_LayoutNode> layer) {
    if (layer.isEmpty) return;

    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final n in layer) {
      minY = min(minY, n.y);
      maxY = max(maxY, n.y);
    }

    final center = (minY + maxY) / 2;

    for (final n in layer) {
      n.y -= center;
    }
  }

  void _assignRadialPositions() {
    final layers = _layers();

    final random = Random(1337);

    for (int depth = 0; depth < layers.length; depth++) {
      final layer = layers[depth];

      final radius =
          depth * config.layerSpacing;

      final step =
          (pi * 2) / layer.length;

      for (int i = 0; i < layer.length; i++) {
        final node = layer[i];

        final angle =
            i * step +
                random.nextDouble() * 0.4;

        node.x = cos(angle) * radius;
        node.y = sin(angle) * radius;
      }
    }
  }

  
  
  
  /// ==========================================================================
  /// SYMMETRY
  /// ==========================================================================

  void _applySymmetry() {
    final layers = _layers();

    for (final layer in layers) {
      if (layer.length < 2) continue;

      layer.sort((a, b) => a.y.compareTo(b.y));

      for (int i = 0; i < layer.length ~/ 2; i++) {
        final top = layer[i];
        final bottom = layer[layer.length - 1 - i];

        final distance =
        (bottom.y - top.y).abs();

        final center =
            (top.y + bottom.y) / 2;

        top.y = center - distance / 2;
        bottom.y = center + distance / 2;
      }
    }
  }

  /// ==========================================================================
  /// HUB CLUSTERS
  /// ==========================================================================

  void _applyHubClusters() {
    for (final hub in _nodes.values) {
      final degree =
          hub.incoming.length +
              hub.outgoing.length;

      if (degree < config.hubMinConnections) {
        continue;
      }

      final connected = {
        ...hub.incoming,
        ...hub.outgoing,
      }.toList();

      for (int i = 0; i < connected.length; i++) {
        final node = connected[i];

        final angle =
            (pi * 2 * i) /
                connected.length;

        final tx =
            hub.x +
                cos(angle) * config.hubRadius;

        final ty =
            hub.y +
                sin(angle) * config.hubRadius;

        node.x = lerpDouble(node.x, tx, 0.18)!;
        node.y = lerpDouble(node.y, ty, 0.18)!;
      }
    }
  }

  /// ==========================================================================
  /// STRAIGHTEN CHAINS
  /// ==========================================================================

  void _straightenChains() {
    for (final node in _nodes.values) {
      if (node.incoming.length == 1 &&
          node.outgoing.length == 1) {
        final a = node.incoming.first;
        final b = node.outgoing.first;

        node.y = (a.y + b.y) / 2;
      }
    }
  }

  /// ==========================================================================
  /// OVERLAP REMOVAL
  /// ==========================================================================

  void _removeOverlaps() {
    final nodes = _nodes.values.toList();

    for (int iteration = 0; iteration < 40; iteration++) {
      for (int i = 0; i < nodes.length; i++) {
        for (int j = i + 1; j < nodes.length; j++) {
          final a = nodes[i];
          final b = nodes[j];

          final overlapX =
              min(a.right, b.right) -
                  max(a.left, b.left);

          final overlapY =
              min(a.bottom, b.bottom) -
                  max(a.top, b.top);

          if (overlapX <= 0 || overlapY <= 0) {
            continue;
          }

          if (overlapX < overlapY) {
            final push = overlapX / 2 + 4;

            if (a.x < b.x) {
              a.x -= push;
              b.x += push;
            } else {
              a.x += push;
              b.x -= push;
            }
          } else {
            final push = overlapY / 2 + 4;

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
    }
  }

  /// ==========================================================================
  /// COMPACT
  /// ==========================================================================

  void _compactLayout() {
    final layers = _layers();

    for (final layer in layers) {
      layer.sort((a, b) => a.y.compareTo(b.y));

      for (int i = 1; i < layer.length; i++) {
        final prev = layer[i - 1];
        final cur = layer[i];

        final desired =
            prev.y + config.nodeSpacing;

        if (cur.y < desired) {
          cur.y = desired;
        }
      }

      _centerLayer(layer);
    }
  }

  /// ==========================================================================
  /// PHYSICS POLISH
  /// ==========================================================================

  void _physicsPolish() {
    final nodes = _nodes.values.toList();

    for (int iteration = 0;
    iteration < config.polishIterations;
    iteration++) {

      for (final node in nodes) {
        double fx = 0;
        double fy = 0;

        // REPULSION
        for (final other in nodes) {
          if (node == other) continue;

          final dx = node.x - other.x;
          final dy = node.y - other.y;

          final distSq =
              dx * dx + dy * dy + 0.01;

          final force =
              90000 / distSq;

          fx += dx * force;
          fy += dy * force;
        }

        // SPRINGS
        for (final neighbor in [
          ...node.incoming,
          ...node.outgoing,
        ]) {
          final dx = neighbor.x - node.x;
          final dy = neighbor.y - node.y;

          fx += dx * 0.015;
          fy += dy * 0.015;
        }

        // RADIAL CONSTRAINT
        final targetRadius =
            node.layer * config.layerSpacing;

        final currentRadius =
        sqrt(node.x * node.x + node.y * node.y);

        final radialForce =
            (targetRadius - currentRadius) * 0.03;

        if (currentRadius > 0.01) {
          fx +=
              (node.x / currentRadius) *
                  radialForce;

          fy +=
              (node.y / currentRadius) *
                  radialForce;
        }

        node.x += fx * 0.01;
        node.y += fy * 0.01;
      }
    }
  }

  /// ==========================================================================
  /// GRID
  /// ==========================================================================

  void _snapToGrid() {
    for (final node in _nodes.values) {
      node.x =
          (node.x / config.gridSize)
              .round() *
              config.gridSize;

      node.y =
          (node.y / config.gridSize)
              .round() *
              config.gridSize;
    }
  }

  /// ==========================================================================
  /// WRITE BACK
  /// ==========================================================================

  void _writeBack(QuestSystem system) {
    for (final node in _nodes.values) {
      final oldQuest =
      system.getQuestById(node.quest.id);

      final updated =
      oldQuest.copyWith(
        posX: node.x,
        posY: node.y,
      );

      system.upsertQuest(updated);
    }
  }

  /// ==========================================================================
  /// HELPERS
  /// ==========================================================================

  List<List<_LayoutNode>> _layers() {
    final map = <int, List<_LayoutNode>>{};

    for (final node in _nodes.values) {
      map.putIfAbsent(
        node.layer,
            () => [],
      );

      map[node.layer]!.add(node);
    }

    final keys =
    map.keys.toList()..sort();

    return keys.map((k) => map[k]!).toList();
  }
}

/// ============================================================================
/// INTERNAL NODE
/// ============================================================================

class _LayoutNode {
  final Quest quest;

  final List<_LayoutNode> incoming = [];
  final List<_LayoutNode> outgoing = [];

  int layer = 0;
  int order = 0;

  double x = 0;
  double y = 0;

  _LayoutNode({
    required this.quest,
  });


  double get left => x - quest.sizeX / 2;
  double get right => x + quest.sizeX / 2;

  double get top => y - quest.sizeY / 2;
  double get bottom => y + quest.sizeY / 2;
  
}