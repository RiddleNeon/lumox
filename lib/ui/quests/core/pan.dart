// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math' show max, min;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumox/ui/quests/core/quest_bubbles_overlay.dart';
import 'package:lumox/ui/quests/core/quest_connection_edit_screen.dart';
import 'package:lumox/ui/quests/core/quest_detail_screen.dart';
import 'package:lumox/logic/quests/quest_change_manager.dart';
import 'package:lumox/logic/quests/quest_connection.dart';
import 'package:lumox/logic/quests/quest_system.dart';
import 'package:lumox/logic/repositories/quest_repository.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';
import 'package:lumox/util/extensions/num_distance.dart';

import '../../../../logic/quests/quest.dart';
import 'pan_background.dart';
import 'quest_bubble.dart';

class PanWidget extends StatefulWidget {
  const PanWidget({
    super.key,
    this.controller,
    this.initialTransform,
    this.showBackground = true,
    this.questOverlaySizeOverride,
    this.onTransformChanged,
    required this.questSystem,
  });

  final TransformationController? controller;
  final Matrix4? initialTransform;
  final bool showBackground;
  final Size? questOverlaySizeOverride;
  final ValueChanged<Matrix4>? onTransformChanged;
  final QuestSystem questSystem;

  @override
  State<PanWidget> createState() => PanWidgetState();
}

class PanWidgetState extends State<PanWidget> with TickerProviderStateMixin {
  late final TransformationController _controller = widget.controller ?? TransformationController();
  late final AnimationController _cameraAnimationController = AnimationController(vsync: this);
  int _cameraAnimationToken = 0;

  bool debugMode = false;

  late final _questBubbleOverlayKey = GlobalKey<QuestBubblesOverlayState>();

  Quest? _draggingQuest;
  Offset _dragStartQuestPos = Offset.zero;
  Offset _focalDelta = Offset.zero;

  bool _isConnecting = false;
  Quest? _connectingFromQuest;
  Offset _lastConnectionScene = Offset.zero;

  double _scaleAtGestureStart = 1.0;
  double _txAtGestureStart = 0.0;
  double _tyAtGestureStart = 0.0;
  Offset _focalAtGestureStart = Offset.zero;

  Offset _lastPointerScenePos = Offset.zero;
  Offset _lastPointerLocalPos = Offset.zero;
  bool _hasLatestPointerScenePos = false;

  Timer? _hoverConnectionTimer;

  double get _currentScale => _controller.value.getMaxScaleOnAxis();
  Matrix4 get currentTransform => Matrix4.copy(_controller.value);

  Matrix4 _buildCameraMatrix(double scale, double tx, double ty) {
    return Matrix4.identity()
      ..scale(scale)
      ..translate(tx / scale, ty / scale);
  }

  
  double? lastTx;
  double? lastTy;
  double? lastScale;
  Rect? lastViewportRect;
  void _syncOverlayViewport() {
    if (!mounted) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? context.size;
    if (size == null) return;

    final scale = _currentScale;
    final tx = _controller.value.entry(0, 3);
    final ty = _controller.value.entry(1, 3);
    final viewportRect = Rect.fromLTWH(-tx / scale, -ty / scale, size.width / scale, size.height / scale);
    
    if(lastTx == null || lastTy == null || lastTx!.distanceTo(tx) > (10/scale) || lastTy!.distanceTo(ty) > (10/scale) || lastScale == null || lastScale!.distanceTo(scale) > 0.01 || lastViewportRect == null || lastViewportRect!.width.distanceTo(viewportRect.width) > 1 || lastViewportRect!.height.distanceTo(viewportRect.height) > 1) {
      _questBubbleOverlayKey.currentState?.onScaleChange(scale, viewportRect);
      lastScale = scale;
      lastViewportRect = viewportRect;
      lastTx = tx;
      lastTy = ty;
    }
    
    widget.onTransformChanged?.call(Matrix4.copy(_controller.value));
  }

  Future<void> animateToTransform(Matrix4 target, {Duration duration = const Duration(milliseconds: 520), Curve curve = Curves.easeOutCubic}) async {
    if (!mounted) return;

    final begin = Matrix4.copy(_controller.value);
    if (begin == target) {
      _controller.value = target;
      return;
    }

    final token = ++_cameraAnimationToken;
    _cameraAnimationController.stop();
    _cameraAnimationController.duration = duration;

    final animation = Matrix4Tween(begin: begin, end: target).animate(CurvedAnimation(parent: _cameraAnimationController, curve: curve));

    void listener() {
      if (!mounted || token != _cameraAnimationToken) return;
      _controller.value = animation.value;
    }

    _cameraAnimationController.addListener(listener);
    try {
      await _cameraAnimationController.forward(from: 0);
      if (mounted && token == _cameraAnimationToken) {
        _controller.value = target;
      }
    } finally {
      _cameraAnimationController.removeListener(listener);
    }
  }

  QuestSystem get questSystem => widget.questSystem;

  QuestChangeManager get changeManager => widget.questSystem.changeManager;

  bool get _isMobile {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  }

  void _updatePointerScenePosition(Offset localPos) {
    _lastPointerLocalPos = localPos;
    _lastPointerScenePos = _controller.toScene(localPos);
    _hasLatestPointerScenePos = true;
  }

  ({int fromId, int toId, Offset midpoint})? _hitTestConnectionAtScenePos(Offset scenePos) {
    if (!debugMode) return null;
    return _questBubbleOverlayKey.currentState?.hitTestConnection(scenePos, _currentScale);
  }

  void _refreshHoveredConnection() {
    if (!mounted) return;

    if (!debugMode || !_hasLatestPointerScenePos || _isConnecting || _draggingQuest != null) {
      if (_hoveredConnection != null) {
        setState(() => _hoveredConnection = null);
      }
      return;
    }

    final scenePos = _controller.toScene(_lastPointerLocalPos);
    _lastPointerScenePos = scenePos;

    final hovered = _hitTestConnectionAtScenePos(scenePos);
    if (hovered != _hoveredConnection) {
      setState(() => _hoveredConnection = hovered);
    }
  }

  Quest? _findQuestAt(Offset scenePos) {
    for (final quest in questSystem.quests) {
      if (quest.rect.contains(scenePos)) return quest;
    }
    return null;
  }

  Quest? _findQuestInConnectZone(Offset scenePos) {
    final double hitRadius;
    if (_isMobile) {
      const minScreenPx = 44.0;
      hitRadius = max(kConnectionHandleRadius * 2.5, minScreenPx / _currentScale);
    } else {
      hitRadius = kConnectionHandleRadius * 1.6;
    }

    for (final quest in questSystem.quests) {
      final handleCenter = Offset(quest.posX + quest.sizeX, quest.posY + quest.sizeY / 2);
      if ((scenePos - handleCenter).distance <= hitRadius) return quest;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controller.value = widget.initialTransform ?? Matrix4.identity();
    _controller.addListener(_syncOverlayViewport);
    questSystem.addListener(revalidateBoundaries);
    revalidateBoundaries();

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlayViewport());

    _hoverConnectionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _refreshHoveredConnection();
    });
    
  }

  @override
  void didUpdateWidget(covariant PanWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.questSystem != widget.questSystem) {
      oldWidget.questSystem.removeListener(revalidateBoundaries);
      questSystem.addListener(revalidateBoundaries);
      revalidateBoundaries();
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlayViewport());
    }
  }

  @override
  void dispose() {
    _hoverConnectionTimer?.cancel();
    questSystem.removeListener(revalidateBoundaries);
    _controller.removeListener(_syncOverlayViewport);
    _cameraAnimationController.dispose();
    super.dispose();
  }

  Offset _boundaryMax = Offset.zero;
  Offset _boundaryMin = Offset.zero;
  static const double _boundaryPadding = 200.0;

  void revalidateBoundaries() {
    if (!mounted) return;

    if (questSystem.quests.isEmpty) {
      setState(() {
        _boundaryMax = const Offset(_boundaryPadding, _boundaryPadding);
        _boundaryMin = const Offset(-_boundaryPadding, -_boundaryPadding);
      });
      return;
    }

    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    double minX = double.infinity;
    double minY = double.infinity;
    for (final quest in questSystem.quests) {
      double questX = quest.posX + (quest.sizeX / 2);
      double questY = quest.posY + (quest.sizeY / 2);
      if (questX > maxX) maxX = questX;
      if (questY > maxY) maxY = questY;
      if (questX < minX) minX = questX;
      if (questY < minY) minY = questY;
    }

    setState(() {
      _boundaryMax = Offset(maxX + _boundaryPadding, maxY + _boundaryPadding);
      _boundaryMin = Offset(minX - _boundaryPadding, minY - _boundaryPadding);
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _focalDelta = Offset.zero;
    _scaleAtGestureStart = _currentScale;
    _txAtGestureStart = _controller.value.entry(0, 3);
    _tyAtGestureStart = _controller.value.entry(1, 3);
    _focalAtGestureStart = details.localFocalPoint;

    final scenePos = _controller.toScene(details.localFocalPoint);
    _lastPointerScenePos = scenePos;
    _lastPointerLocalPos = details.localFocalPoint;
    _hasLatestPointerScenePos = true;

    if (debugMode && details.pointerCount == 1) {
      if (_isTapOnConnectionHandle()) {
        return;
      }

      if (!_isConnecting) {
        final connectQuest = _findQuestInConnectZone(scenePos);
        if (connectQuest != null) {
          _isConnecting = true;
          _connectingFromQuest = connectQuest;
          _lastConnectionScene = scenePos;
          _questBubbleOverlayKey.currentState?.setConnectionState(sourceId: connectQuest.id, targetId: null, previewPos: scenePos);
          return;
        }
      }

      if (!_isConnecting) {
        _draggingQuest = _findQuestAt(scenePos);
        _dragStartQuestPos = _draggingQuest?.position ?? Offset.zero;
        _questBubbleOverlayKey.currentState?.setDragState(questId: _draggingQuest?.id, position: _draggingQuest != null ? _dragStartQuestPos : null);
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _focalDelta += details.focalPointDelta;
    _updatePointerScenePosition(details.localFocalPoint);

    if (_isConnecting && _connectingFromQuest != null) {
      final scenePos = _controller.toScene(details.localFocalPoint);
      _lastConnectionScene = scenePos;

      final hoveredQuest = _findQuestAt(scenePos);
      final targetId = (hoveredQuest != null && hoveredQuest.id != _connectingFromQuest!.id) ? hoveredQuest.id : null;

      _questBubbleOverlayKey.currentState?.setConnectionState(sourceId: _connectingFromQuest!.id, targetId: targetId, previewPos: scenePos);
      return;
    }

    if (_draggingQuest != null) {
      final newPos = snap(_dragStartQuestPos);
      _questBubbleOverlayKey.currentState?.setDragState(questId: _draggingQuest!.id, position: newPos);
      return;
    }

    final s = (_scaleAtGestureStart * details.scale).clamp(minScale, maxScale);

    var tx = details.localFocalPoint.dx - s * (_focalAtGestureStart.dx - _txAtGestureStart) / _scaleAtGestureStart;
    var ty = details.localFocalPoint.dy - s * (_focalAtGestureStart.dy - _tyAtGestureStart) / _scaleAtGestureStart;

    _controller.value = _buildCameraMatrix(s, tx, ty);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isConnecting && _connectingFromQuest != null) {
      final targetQuest = _findQuestAt(_lastConnectionScene);
      if (targetQuest != null && targetQuest.id != _connectingFromQuest!.id) {
        _addConnection(sourceId: _connectingFromQuest!.id, targetId: targetQuest.id);
      }
      _isConnecting = false;
      _connectingFromQuest = null;
      _questBubbleOverlayKey.currentState?.setConnectionState(sourceId: null, targetId: null, previewPos: null);
      return;
    }

    if (_draggingQuest != null) {
      QuestPatch before = QuestPatch(posX: _draggingQuest!.posX, posY: _draggingQuest!.posY);

      final newPos = snap(_dragStartQuestPos);
      QuestPatch after = QuestPatch(posX: newPos.dx, posY: newPos.dy);

      _draggingQuest = after.applyTo(_draggingQuest!);

      changeManager.record(UpdateQuestChange(questId: _draggingQuest!.id, patch: after, reversePatch: before, updateMessage: 'moved quest'));

      questSystem.upsertQuest(_draggingQuest!);
    }
    _questBubbleOverlayKey.currentState?.setDragState(questId: null, position: null);
    setState(() => _draggingQuest = null);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (!debugMode) return;

    final localPos = details.localPosition;
    final scenePos = _controller.toScene(localPos);

    _lastPointerLocalPos = localPos;
    _lastPointerScenePos = scenePos;
    _hasLatestPointerScenePos = true;

    _draggingQuest = null;
    _questBubbleOverlayKey.currentState?.setDragState(questId: null, position: null);

    final quest = _findQuestAt(scenePos);
    if (quest != null) {
      _isConnecting = true;
      _connectingFromQuest = quest;
      _lastConnectionScene = scenePos;
      _questBubbleOverlayKey.currentState?.setConnectionState(sourceId: quest.id, targetId: null, previewPos: scenePos);

      HapticFeedback.mediumImpact();
    }
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isConnecting || _connectingFromQuest == null) return;

    final scenePos = _controller.toScene(details.localPosition);
    _lastConnectionScene = scenePos;
    _lastPointerScenePos = scenePos;
    _lastPointerLocalPos = details.localPosition;
    _hasLatestPointerScenePos = true;

    final hoveredQuest = _findQuestAt(scenePos);
    final targetId = (hoveredQuest != null && hoveredQuest.id != _connectingFromQuest!.id) ? hoveredQuest.id : null;

    _questBubbleOverlayKey.currentState?.setConnectionState(sourceId: _connectingFromQuest!.id, targetId: targetId, previewPos: scenePos);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isConnecting || _connectingFromQuest == null) return;

    final targetQuest = _findQuestAt(_lastConnectionScene);
    if (targetQuest != null && targetQuest.id != _connectingFromQuest!.id) {
      _addConnection(sourceId: _connectingFromQuest!.id, targetId: targetQuest.id);
      HapticFeedback.lightImpact();
    }

    _isConnecting = false;
    _connectingFromQuest = null;
    _questBubbleOverlayKey.currentState?.setConnectionState(sourceId: null, targetId: null, previewPos: null);
  }

  void _onLongPressCancel() {
    if (!_isConnecting) return;
    _isConnecting = false;
    _connectingFromQuest = null;
    _questBubbleOverlayKey.currentState?.setConnectionState(sourceId: null, targetId: null, previewPos: null);
  }

  Offset snap(Offset before) {
    final currentScale = _currentScale;
    final worldDelta = _focalDelta / currentScale;

    final rawPos = before + worldDelta;

    final snappedX = ((rawPos.dx / gridSize + 0.5).round()) * gridSize;
    final snappedY = ((rawPos.dy / gridSize + 0.5).round()) * gridSize;

    final Offset newPos;
    if (isGridSnappingEnabled) {
      newPos = Offset(snappedX, snappedY);
    } else {
      newPos = rawPos;
    }
    return newPos;
  }

  void _onPointerScroll(PointerScrollEvent event) {
    if (_draggingQuest != null || _isConnecting) return;

    const zoomSensitivity = 0.0010;

    _updatePointerScenePosition(event.localPosition);

    final currentScale = _currentScale;
    final newScale = (currentScale * (1.0 - event.scrollDelta.dy * zoomSensitivity)).clamp(minScale, maxScale);

    final currentTx = _controller.value.entry(0, 3);
    final currentTy = _controller.value.entry(1, 3);
    final focal = event.localPosition;

    var tx = focal.dx - newScale * (focal.dx - currentTx) / currentScale;
    var ty = focal.dy - newScale * (focal.dy - currentTy) / currentScale;

    _controller.value = _buildCameraMatrix(newScale, tx, ty);
  }

  ({int fromId, int toId, Offset midpoint})? _hoveredConnection;

  void _onPointerHover(PointerHoverEvent event) {
    if (event.down) return;

    _updatePointerScenePosition(event.localPosition);
    if (debugMode) {
      _refreshHoveredConnection();
    }
  }

  void _onPointerExit(PointerExitEvent event) {
    _hasLatestPointerScenePos = false;
    if (_hoveredConnection != null) {
      setState(() => _hoveredConnection = null);
    }
  }

  void _removeConnection(int fromId, int toId) {
    changeManager.record(RemoveConnectionChange(fromId: fromId, toId: toId));
    setState(() => _hoveredConnection = null);
  }

  void _addConnection({required int sourceId, required int targetId}) {
    final target = questSystem.maybeGetQuestById(targetId);
    if (target == null || questSystem.prerequisitesOf(targetId).any((p) => p.id == sourceId)) {
      return;
    }

    final source = questSystem.maybeGetQuestById(sourceId);
    if (source == null) {
      return;
    }

    try {
      changeManager.record(AddConnectionChange(fromId: sourceId, toId: targetId, updateMessage: 'connection drawn'));
    } catch (e) {
      questSystem.addConnection(targetId, sourceId);
      questRepo.addConnection(targetId, sourceId);
    }
    _questBubbleOverlayKey.currentState?.refresh();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _updatePointerScenePosition(details.localPosition);
  }

  void _onDoubleTap() {
    if (!debugMode) {
      return;
    }

    final quest = _findQuestAt(_lastPointerScenePos);
    if (quest == null) {
      showQuestAddOverlay(_lastPointerScenePos);
      return;
    }
  }

  void _onTap() {
    final quest = _findQuestAt(_lastPointerScenePos);
    final connection = _hitTestConnectionAtScenePos(_lastPointerScenePos) ?? _hoveredConnection;

    if (quest == null && connection != null && debugMode) {
      if (_isMobile) {
        _showConnectionOptionsSheet(connection.fromId, connection.toId);
      } else {
        if (_isTapOnConnectionHandle()) {
          _removeConnection(connection.fromId, connection.toId);
        } else {
          showQuestConnectionEditOverlay(connection.fromId, connection.toId);
        }
      }
      return;
    }

    
    if (quest == null) return;
    showDialog(
      context: context,
      builder: (context) => FractionallySizedBox(
        widthFactor: 0.8,
        heightFactor: 0.8,
        child: Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uiRadiusLg)),
          child: QuestDetailScreen(
            quest: quest,
            debugMode: debugMode,
            editMode: false,
            onDoneEditing: (updatedQuest, [changeMessage]) async {
              changeManager.record(
                UpdateQuestChange(
                  patch: updatedQuest,
                  reversePatch: QuestPatch.fromQuest(quest),
                  questId: quest.id,
                  updateMessage: changeMessage ?? 'no message provided',
                ),
              );
              if (context.mounted) Navigator.of(context).pop();
            },
            onDelete: (q) async {
              await questRepo.deleteQuest(q);
              changeManager.record(DeleteQuestChange(quest: q));
              if (context.mounted) Navigator.of(context).pop();
            },
            questSystem: questSystem,
          ),
        ),
      ),
    );
  }

  bool _isTapOnConnectionHandle() {
    if (_hoveredConnection == null) return false;

    final screenPos = MatrixUtils.transformPoint(_controller.value, _hoveredConnection!.midpoint);

    const radius = 10.0;

    return (_lastPointerLocalPos - screenPos).distance <= radius;
  }

  void _showConnectionOptionsSheet(int fromId, int toId) {
    showModalBottomSheet<void>(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(context.uiRadiusLg))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(context.uiRadiusSm)),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Connection'),
                onTap: () {
                  Navigator.pop(ctx);
                  showQuestConnectionEditOverlay(fromId, toId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete Connection', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeConnection(fromId, toId);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void showQuestConnectionEditOverlay(int fromId, int toId) async {
    final fromQuest = questSystem.maybeGetQuestById(fromId);
    final toQuest = questSystem.maybeGetQuestById(toId);
    if (fromQuest == null || toQuest == null) return;

    QuestConnection connection = questSystem.getConnection(fromId, toId)!;

    showDialog(
      context: context,
      builder: (context) => QuestConnectionEditScreen(
        connection: QuestConnection(fromQuestId: fromId, toQuestId: toId, type: connection.type, xpRequirement: connection.xpRequirement),
        questSystem: questSystem,
      ),
    );
  }

  void showQuestAddOverlay(Offset scenePos) {
    final snappedPos = snap(scenePos);
    Quest quest = Quest(
      id: DateTime.now().millisecondsSinceEpoch,
      name: 'No name provided',
      description: 'No description provided',
      subject: questSystem.subject,
      posX: snappedPos.dx,
      posY: snappedPos.dy,
    );
    showDialog(
      context: context,
      builder: (context) {
        return Center(
          child: FractionallySizedBox(
            widthFactor: 0.9,
            heightFactor: 0.9,
            child: Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uiRadiusLg)),
              child: QuestDetailScreen(
                quest: quest,
                debugMode: true,
                editMode: true,
                recommendedChangeMessage: 'Initial version',
                onDoneEditing: (updatedQuest, [changeMessage]) async {
                  changeManager.record(AddQuestChange(quest: updatedQuest.applyTo(quest), updateMessage: changeMessage ?? 'no message provided'));
                  if (context.mounted) Navigator.of(context).pop();
                },
                onDelete: (q) async {
                  await questRepo.deleteQuest(q);
                  changeManager.record(DeleteQuestChange(quest: q));
                  if (context.mounted) Navigator.of(context).pop();
                },
                questSystem: questSystem,
              ),
            ),
          ),
        );
      },
    );
  }

  void focusOnQuest(Quest quest) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final viewSize = renderBox.size;
    final scale = _currentScale;

    final targetX = -(quest.posX * scale) + viewSize.width / 2 - (quest.sizeX * scale / 2);
    final targetY = -(quest.posY * scale) + viewSize.height / 2 - (quest.sizeY * scale / 2);

    _controller.value = _buildCameraMatrix(scale, targetX, targetY);
  }

  void focusOnQuests(List<Quest> quests, double screenWidth, double screenHeight, {bool zoomOutIfNeeded = true}) {
    if (quests.isEmpty) {
      centerOnAllQuests(screenWidth, screenHeight, autoZoom: true);
      return;
    }

    if (quests.length == 1 && !zoomOutIfNeeded) {
      focusOnQuest(quests.first);
      return;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final quest in quests) {
      minX = min(minX, quest.posX);
      minY = min(minY, quest.posY);
      maxX = max(maxX, quest.posX + quest.sizeX);
      maxY = max(maxY, quest.posY + quest.sizeY);
    }

    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final boundsWidth = (maxX - minX).abs() + 1;
    final boundsHeight = (maxY - minY).abs() + 1;
    final scaleX = screenWidth / boundsWidth;
    final scaleY = screenHeight / boundsHeight;

    double targetScale = _currentScale;
    if (zoomOutIfNeeded) {
      targetScale = min(scaleX, scaleY) * 0.85;
      targetScale = min(targetScale, _currentScale);
    }

    final targetTx = screenWidth / 2 - center.dx * targetScale;
    final targetTy = screenHeight / 2 - center.dy * targetScale;

    _controller.value = _buildCameraMatrix(targetScale, targetTx, targetTy);
  }

  void centerOnAllQuests(double screenWidth, double screenHeight, {bool autoZoom = true}) {
    final boundaryCenter = Offset((_boundaryMin.dx + _boundaryMax.dx) / 2, (_boundaryMin.dy + _boundaryMax.dy) / 2);

    double scaleX = screenWidth / (_boundaryMax.dx - _boundaryMin.dx + 1);
    double scaleY = screenHeight / (_boundaryMax.dy - _boundaryMin.dy + 1);
    double targetScale = autoZoom ? (scaleX < scaleY ? scaleX : scaleY) * 0.95 : _currentScale;

    final targetTx = screenWidth / 2 - boundaryCenter.dx * (targetScale);
    final targetTy = screenHeight / 2 - boundaryCenter.dy * (targetScale);

    _controller.value = _buildCameraMatrix(targetScale, targetTx, targetTy);
  }

  static const double minScale = 0.000000001;
  static const double maxScale = 3000.0;

  bool isGridSnappingEnabled = true;
  double gridSize = 25.0;

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode(
        onKey: (node, event) {
          if (event.logicalKey == LogicalKeyboardKey.keyZ && event is RawKeyDownEvent && (event.isMetaPressed || event.isControlPressed)) {
            setState(() {
              changeManager.undo();
              _controller.value.rotateX(0.0000000000001);
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyY && event is RawKeyDownEvent && (event.isMetaPressed || event.isControlPressed)) {
            setState(() {
              changeManager.redo();
              _controller.value.rotateX(0.0000000000001);
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyC && !HardwareKeyboard.instance.isShiftPressed) {
            centerOnAllQuests(context.size?.width ?? 100, context.size?.height ?? 100, autoZoom: false);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyC && HardwareKeyboard.instance.isShiftPressed) {
            centerOnAllQuests(context.size?.width ?? 100, context.size?.height ?? 100, autoZoom: true);
            return KeyEventResult.handled;
          }

          if (HardwareKeyboard.instance.isShiftPressed) {
            isGridSnappingEnabled = false;
          } else {
            isGridSnappingEnabled = true;
          }
          return KeyEventResult.ignored;
        },
        canRequestFocus: true,
      )..requestFocus(),
      child: MouseRegion(
        onExit: _onPointerExit,
        child: Listener(
          onPointerHover: _onPointerHover,
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _onPointerScroll(e);
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(context.uiRadiusLg),
            child: DecoratedBox(
              decoration: BoxDecoration(color: widget.showBackground ? const Color(0xFF0A1218) : Colors.transparent),
              child: Stack(
                children: [
                  if (widget.showBackground) Positioned.fill(child: InfiniteDotsBackground(controller: _controller)),
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => Transform(transform: _controller.value, alignment: Alignment.topLeft, child: child),
                       child: QuestBubblesOverlay(
                         key: _questBubbleOverlayKey,
                         debugMode: debugMode,
                         questSystem: questSystem,
                         worldSizeOverride: widget.questOverlaySizeOverride,
                       ),
                    ),
                  ),

                  if (_hoveredConnection != null && debugMode && !_isMobile)
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final screenPos = MatrixUtils.transformPoint(_controller.value, _hoveredConnection!.midpoint);

                        return Positioned(
                          left: screenPos.dx - 15,
                          top: screenPos.dy - 15,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: InkWell(
                              onTap: () => _removeConnection(_hoveredConnection!.fromId, _hoveredConnection!.toId),
                              child: Container(
                                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.close, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: _onScaleEnd,
                      onDoubleTapDown: _onDoubleTapDown,
                      onDoubleTap: _onDoubleTap,
                      onTap: _onTap,
                      onTapDown: _onDoubleTapDown,
                      onLongPressStart: _onLongPressStart,
                      onLongPressMoveUpdate: _onLongPressMoveUpdate,
                      onLongPressEnd: _onLongPressEnd,
                      onLongPressCancel: _onLongPressCancel,
                    ),
                  ),
                  /*if (debugMode)
                    QuestDebugPanel(key: _debugPanelKey, onChanged: () => _questBubbleOverlayKey.currentState?.refresh(), onFocusQuest: _focusOnQuest),*/
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
