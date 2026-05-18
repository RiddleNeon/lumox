import 'package:flutter/material.dart';
import 'package:lumox/logic/quests/quest.dart';
import 'package:lumox/logic/quests/quest_system.dart';
import 'package:lumox/ui/quests/core/quest_line_connection_painter.dart';

import 'quest_bubble.dart';
import 'quest_color_propagator.dart';

class QuestBubblesOverlay extends StatefulWidget {
  final bool debugMode;
  final QuestSystem questSystem;

  const QuestBubblesOverlay(
      {super.key, required this.debugMode, required this.questSystem});

  @override
  State<QuestBubblesOverlay> createState() => QuestBubblesOverlayState();
}
Map<int, Color> derivedQuestColors = {};
class QuestBubblesOverlayState extends State<QuestBubblesOverlay>
    with TickerProviderStateMixin {
  late final QuestLineConnectionPainter _connectionPainter;
  late Size _worldBounds;

  QuestSystem get questSystem => widget.questSystem;

  final _dragNotifier =
  ValueNotifier<({int? id, Offset? pos})>((id: null, pos: null));

  final _connectionNotifier = ValueNotifier<
      ({
      int? sourceId,
      int? targetId,
      Offset? previewPos,
      })>((sourceId: null, targetId: null, previewPos: null));

  late final AnimationController _lineAnimCtrl;


  @override
  void initState() {
    super.initState();
    
    print("NEW STATE!!!! subject: ${questSystem.subject}, current quest connections: ${questSystem.getConnections().length}, quests: ${questSystem.quests.length}");

    _lineAnimCtrl =
    AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();

    _connectionPainter = QuestLineConnectionPainter(
      questSystem: questSystem,
      animation: _lineAnimCtrl,
      pixelSpacing: 30,
      lineWidth: 10,
      arrowSize: 8.0,
    );

    _worldBounds = _computeWorldBounds();

    questSystem.addListener(_onQuestSystemChanged);

    _connectionPainter.rebuildCache();
    _recomputeColors();
  }
  
  void _recomputeColors() {
    final adjacency = QuestColorPropagator.buildAdjacency(
      quests: questSystem.quests,
      prerequisiteResolver: questSystem.prerequisitesOf,
    );

    derivedQuestColors = QuestColorPropagator.compute(
      quests: questSystem.quests,
      adjacency: adjacency,
    );
    _connectionPainter.recomputeGlowColors();
  }
  
  void _onQuestSystemChanged() {
    print("Quest system changed, recomputing world bounds and colors...");
    final newBounds = _computeWorldBounds();
    final boundsChanged = newBounds != _worldBounds;

    _connectionPainter.rebuildCache();
    _recomputeColors();

    if (boundsChanged) {
      setState(() => _worldBounds = newBounds);
    } else {
      setState(() {});
    }
  }

  void setDragState({required int? questId, required Offset? position}) {
    _dragNotifier.value = (id: questId, pos: position);
    _connectionPainter
      ..currentDraggedQuestId = questId
      ..currentDraggedQuestPos = position;
  }

  void setConnectionState({
    required int? sourceId,
    required int? targetId,
    required Offset? previewPos,
  }) {
    _connectionNotifier.value =
    (sourceId: sourceId, targetId: targetId, previewPos: previewPos);
    _connectionPainter
      ..connectionSourceId = sourceId
      ..connectionPreviewEnd = previewPos;
  }

  void refresh() => setState(() {});

  void onScaleChange(double newScale, Rect viewportRect) {
    setState(() {
      _connectionPainter.scale = newScale;
      _connectionPainter.viewportRect = viewportRect;
    });
  }

  ({int fromId, int toId, Offset midpoint})? hitTestConnection(Offset scenePos, double scale) {
    return _connectionPainter.hitTestConnection(scenePos, scale: scale);
  }

  @override
  Widget build(BuildContext context) {
    const padding = 500.0;

    return SizedBox(
      width: _worldBounds.width + padding,
      height: _worldBounds.height + padding,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(size: _worldBounds, painter: _connectionPainter),
          for (final quest in questSystem.quests) _positionedBubble(quest),
        ],
      ),
    );
  }

  Widget _positionedBubble(Quest quest) {
    return ValueListenableBuilder(
      valueListenable: _dragNotifier,
      builder: (context, drag, _) {
        final isDragged = quest.id == drag.id && drag.pos != null;

        return ValueListenableBuilder(
          valueListenable: _connectionNotifier,
          builder: (context, conn, _) {
            final effectiveColor =
                derivedQuestColors[quest.id] ?? quest.color;
            
            return Positioned(
              left: isDragged ? drag.pos!.dx : quest.posX,
              top: isDragged ? drag.pos!.dy : quest.posY,
              child: QuestBubble(
                quest: quest,
                effectiveColor: effectiveColor,
                isConnectionSource: conn.sourceId == quest.id,
                isConnectionTarget: conn.targetId == quest.id,
                debugMode: widget.debugMode,
                cs: Theme.of(context).colorScheme,
              ),
            );
          },
        );
      },
    );
  }

  Size _computeWorldBounds() {
    double maxX = 0, maxY = 0;
    for (final quest in questSystem.quests) {
      if (quest.posX + quest.sizeX > maxX) maxX = quest.posX + quest.sizeX;
      if (quest.posY + quest.sizeY > maxY) maxY = quest.posY + quest.sizeY;
    }
    return Size(maxX, maxY);
  }

  void revalidateWorldBounds() => _onQuestSystemChanged();

  @override
  void dispose() {
    _dragNotifier.dispose();
    _connectionNotifier.dispose();
    questSystem.removeListener(_onQuestSystemChanged);
    _lineAnimCtrl.dispose();
    super.dispose();
  }
}