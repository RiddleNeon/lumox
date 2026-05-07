import 'dart:math';
import 'dart:ui';

import 'package:lumox/logic/quests/quest_layout/quest_layout_config.dart';
import 'package:lumox/logic/quests/quest_layout/quest_layout_edge.dart';
import 'package:lumox/logic/quests/quest_layout/quest_layout_node.dart';

import '../quest_change_manager.dart';
import '../quest_system.dart';

class QuestGraphLayoutEngine {
  final QuestLayoutConfig config;

  QuestGraphLayoutEngine({this.config = const QuestLayoutConfig()});

  void layout(QuestSystem system) {
    final nodes = _buildNodes(system);
    final edges = _buildEdges(system, nodes);

    _breakCycles(nodes, edges);
    _assignLayers(nodes);
    _minimizeCrossings(nodes, edges);
    _assignCoordinates(nodes);

    _forceOptimize(nodes, edges);
    _resolveCollisions(nodes);
    _normalize(nodes);

    _writeBack(system, nodes);
  }

  Map<int, LayoutNode> _buildNodes(QuestSystem system) {
    final map = <int, LayoutNode>{};

    for (final q in system.quests) {
      map[q.id] = LayoutNode(id: q.id, width: q.sizeX, height: q.sizeY);
    }

    return map;
  }

  List<LayoutEdge> _buildEdges(QuestSystem system, Map<int, LayoutNode> nodes) {
    final result = <LayoutEdge>[];

    for (final q in system.quests) {
      final prereqs = system.prerequisiteIds(q.id);

      for (final prereqId in prereqs) {
        final from = nodes[prereqId];
        final to = nodes[q.id];

        if (from == null || to == null) continue;

        from.outgoing.add(to);
        to.incoming.add(from);

        result.add(LayoutEdge(from: from, to: to));
      }
    }

    return result;
  }

  void _breakCycles(Map<int, LayoutNode> nodes, List<LayoutEdge> edges) {
    final visited = <int>{};
    final stack = <int>{};

    bool dfs(LayoutNode node) {
      visited.add(node.id);
      stack.add(node.id);

      for (final next in List<LayoutNode>.from(node.outgoing)) {
        if (!visited.contains(next.id)) {
          dfs(next);
        } else if (stack.contains(next.id)) {
          final edge = edges.firstWhere((e) => e.from == node && e.to == next);

          edge.reversed = true;

          node.outgoing.remove(next);
          next.incoming.remove(node);

          next.outgoing.add(node);
          node.incoming.add(next);
        }
      }

      stack.remove(node.id);
      return true;
    }

    for (final node in nodes.values) {
      if (!visited.contains(node.id)) {
        dfs(node);
      }
    }
  }

  void _assignLayers(Map<int, LayoutNode> nodes) {
    final indegree = <LayoutNode, int>{};

    for (final n in nodes.values) {
      indegree[n] = n.incoming.length;
    }

    final queue = <LayoutNode>[];

    for (final entry in indegree.entries) {
      if (entry.value == 0) {
        queue.add(entry.key);
      }
    }

    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);

      for (final out in node.outgoing) {
        out.layer = max(out.layer, node.layer + 1);

        indegree[out] = indegree[out]! - 1;

        if (indegree[out] == 0) {
          queue.add(out);
        }
      }
    }
  }

  void _minimizeCrossings(Map<int, LayoutNode> nodes, List<LayoutEdge> edges) {
    final layers = _buildLayers(nodes);

    for (int pass = 0; pass < config.crossingMinimizationPasses; pass++) {
      for (int i = 1; i < layers.length; i++) {
        final layer = layers[i];

        layer.sort((a, b) {
          final ma = _medianIncoming(a);
          final mb = _medianIncoming(b);
          return ma.compareTo(mb);
        });

        for (int j = 0; j < layer.length; j++) {
          layer[j].order = j;
        }
      }

      for (int i = layers.length - 2; i >= 0; i--) {
        final layer = layers[i];

        layer.sort((a, b) {
          final ma = _medianOutgoing(a);
          final mb = _medianOutgoing(b);
          return ma.compareTo(mb);
        });

        for (int j = 0; j < layer.length; j++) {
          layer[j].order = j;
        }
      }
    }
  }

  List<List<LayoutNode>> _buildLayers(Map<int, LayoutNode> nodes) {
    final map = <int, List<LayoutNode>>{};

    for (final n in nodes.values) {
      map.putIfAbsent(n.layer, () => []);
      map[n.layer]!.add(n);
    }

    final keys = map.keys.toList()..sort();

    return keys.map((k) => map[k]!).toList();
  }

  double _medianIncoming(LayoutNode node) {
    if (node.incoming.isEmpty) return node.order.toDouble();

    final values = node.incoming.map((n) => n.order.toDouble()).toList()..sort();

    return values[values.length ~/ 2];
  }

  double _medianOutgoing(LayoutNode node) {
    if (node.outgoing.isEmpty) return node.order.toDouble();

    final values = node.outgoing.map((n) => n.order.toDouble()).toList()..sort();

    return values[values.length ~/ 2];
  }

  void _assignCoordinates(
      Map<int, LayoutNode> nodes,
      ) {
    final layers = _buildLayers(nodes);

    for (int layerIndex = 0;
    layerIndex < layers.length;
    layerIndex++) {

      final layer = layers[layerIndex];

      layer.sort((a, b) => a.order.compareTo(b.order));

      final density = _layerDensity(layer);

      final dynamicVerticalSpacing =
          config.verticalSpacing + density * 35;

      final dynamicLayerSpacing =
          config.layerSpacing + density * 50;

      double y = 0;

      for (final node in layer) {
        final nodeDensity = _nodeDensity(node);

        final nodeSpacing =
            dynamicVerticalSpacing + nodeDensity * 25;

        node.x = layerIndex * dynamicLayerSpacing;
        node.y = y;

        y += node.height + nodeSpacing;
      }

      final height = y;

      for (final node in layer) {
        node.y -= height / 2;
      }
    }
  }

  double _nodeDensity(LayoutNode node) {
    return (
        node.incoming.length +
            node.outgoing.length
    ).toDouble();
  }

  double _layerDensity(List<LayoutNode> layer) {
    if (layer.isEmpty) return 0;

    double total = 0;

    for (final node in layer) {
      total += _nodeDensity(node);
    }

    return total / layer.length;
  }

  void _forceOptimize(Map<int, LayoutNode> nodes, List<LayoutEdge> edges) {
    final nodeList = nodes.values.toList();

    for (int iter = 0; iter < config.forceIterations; iter++) {
      final forces = <LayoutNode, Offset>{};

      for (final n in nodeList) {
        forces[n] = Offset.zero;
      }

      for (int i = 0; i < nodeList.length; i++) {
        for (int j = i + 1; j < nodeList.length; j++) {
          final a = nodeList[i];
          final b = nodeList[j];

          final dx = b.center.dx - a.center.dx;
          final dy = b.center.dy - a.center.dy;

          final distSq = dx * dx + dy * dy + 0.01;
          final dist = sqrt(distSq);

          final degreeA =
              a.incoming.length + a.outgoing.length;

          final degreeB =
              b.incoming.length + b.outgoing.length;

          final degreeFactor =
              1 + (degreeA + degreeB) * 0.15;

          final localBoost = dist < 250 ? 4.0 : 1.0;

          final force =
              (config.nodeRepulsion * degreeFactor * localBoost)
                  / distSq;

          final fx = dx / dist * force;
          final fy = dy / dist * force;

          forces[a] = forces[a]! - Offset(fx, fy);
          forces[b] = forces[b]! + Offset(fx, fy);
        }
      }

      for (final edge in edges) {
        final a = edge.from;
        final b = edge.to;

        final dx = b.center.dx - a.center.dx;
        final dy = b.center.dy - a.center.dy;

        final dist = sqrt(dx * dx + dy * dy) + 0.01;

        final stretch = dist - config.idealEdgeLength;

        final force = stretch * config.edgeSpringStrength;

        final fx = dx / dist * force;
        final fy = dy / dist * force;

        forces[a] = forces[a]! + Offset(fx, fy);
        forces[b] = forces[b]! - Offset(fx, fy);
      }

      for (final node in nodeList) {
        final f = forces[node]!;

        node.x += f.dx * 0.003;

        node.y += f.dy * 0.025;
      }
    }
  }

  void _resolveCollisions(Map<int, LayoutNode> nodes) {
    final list = nodes.values.toList();

    for (int iter = 0; iter < config.collisionIterations; iter++) {
      for (int i = 0; i < list.length; i++) {
        for (int j = i + 1; j < list.length; j++) {
          final a = list[i];
          final b = list[j];

          final rectA = a.rect.inflate(24);
          final rectB = b.rect.inflate(24);

          if (!rectA.overlaps(rectB)) continue;

          final overlap = rectA.intersect(rectB);

          if (overlap.width < overlap.height) {
            final push = overlap.width / 2;

            if (a.center.dx < b.center.dx) {
              a.x -= push;
              b.x += push;
            } else {
              a.x += push;
              b.x -= push;
            }
          } else {
            final push = overlap.height / 2;

            if (a.center.dy < b.center.dy) {
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

  void _normalize(Map<int, LayoutNode> nodes) {
    if (nodes.isEmpty) return;

    double minX = double.infinity;
    double minY = double.infinity;

    for (final n in nodes.values) {
      minX = min(minX, n.x);
      minY = min(minY, n.y);
    }

    for (final n in nodes.values) {
      n.x -= minX;
      n.y -= minY;
    }
  }

  void _writeBack(
      QuestSystem system,
      Map<int, LayoutNode> nodes,
      ) {
    final manager = system.changeManager;

    for (final quest in system.quests) {
      final node = nodes[quest.id]!;

      final newX = node.x.roundToDouble();
      final newY = node.y.roundToDouble();

      if ((quest.posX - newX).abs() < 0.5 &&
          (quest.posY - newY).abs() < 0.5) {
        continue;
      }

      final updated = quest.copyWith(
        posX: newX,
        posY: newY,
      );

      final change = UpdateQuestChange.fromDiff(
        before: quest,
        after: updated,
        updateMessage: 'auto-arranged quest layout',
      );

      manager.record(change);
    }
  }
}