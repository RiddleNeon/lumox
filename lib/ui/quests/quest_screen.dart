//test app for the quest screen

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumox/logic/quests/quest.dart';
import 'package:lumox/logic/quests/quest_layout/custom/custom_layout_config.dart';
import 'package:lumox/logic/quests/quest_layout/custom/custom_layout_system.dart';
import 'package:lumox/logic/quests/quest_layout/quest_layout_config.dart';
import 'package:lumox/logic/quests/quest_layout/structured/structured_quest_layout_system.dart';
import 'package:lumox/logic/quests/quest_system.dart';
import 'package:lumox/logic/repositories/quest_repository.dart';
import 'package:lumox/tools/quest_generator.dart';
import 'package:lumox/ui/quests/version_management/change_screen.dart';

import 'core/pan.dart';

class QuestScreen extends StatefulWidget {
  final List<int> focusQuestIds;
  final bool zoomOutIfNeeded;
  final String initialSubject;

  const QuestScreen({super.key, required this.initialSubject, this.focusQuestIds = const [], this.zoomOutIfNeeded = true});

  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> {
  final Map<String, GlobalKey<PanWidgetState>> _panKeys = {};
  bool debugMode = false;
  bool hasPendingChanges = false;
  bool isSubjectMenuOpen = false;
  bool _questViewportReady = false;
  int _questSystemLoadToken = 0;
  final Set<String> expandedSubjectGroups = {};
  final Set<String> locallyCreatedSubjects = {};
  late Future<List<String>> subjectFuture;
  
  late String subject = widget.initialSubject;
  
  GlobalKey<PanWidgetState> get _panKey => _panKeys.putIfAbsent(subject, () => GlobalKey<PanWidgetState>());

  @override
  initState() {
    super.initState();
    print("Initializing TestQuestScreen with subject: $subject");
    questSystemFuture = loadQuestSystemFor(subject, _questSystemLoadToken);
    subjectFuture = questRepo.fetchQuestSubjects();
  }

  Future<QuestSystem> loadQuestSystemFor(String subjectToLoad, int loadToken) async {
    QuestSystem questSystem = QuestSystem();
    print("-- Loading quests for subject: $subjectToLoad");
    await questSystem.loadFromServer(subjectToLoad);

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (!mounted || loadToken != _questSystemLoadToken) return;
      setState(() {
        final focusQuests = widget.focusQuestIds.map((id) => questSystem.maybeGetQuestById(id)).whereType<Quest>().toList();

        if (focusQuests.isEmpty) {
          _panKey.currentState?.centerOnAllQuests(context.size?.width ?? 1000, context.size?.height ?? 1000);
          _questViewportReady = true;
          return;
        }

        final panState = _panKey.currentState;
        if (panState == null) {
          _questViewportReady = true;
          return;
        }
        panState.focusOnQuests(focusQuests, context.size?.width ?? 1000, context.size?.height ?? 1000, zoomOutIfNeeded: widget.zoomOutIfNeeded);

        _questViewportReady = true;
      });
    });

    questSystem.changeManager.addListener(() {
      if (!mounted || loadToken != _questSystemLoadToken) return;
      if (questSystem.changeManager.hasPendingChanges != hasPendingChanges) {
        setState(() {
          hasPendingChanges = questSystem.changeManager.hasPendingChanges;
        });
      }
    });
    return questSystem;
  }
  
  Future<QuestSystem> reloadQuestSystem() async {
    return loadQuestSystemFor(subject, _questSystemLoadToken);
  }

  late Future<QuestSystem> questSystemFuture;

  Future<void> _showCreateSubjectDialog() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create subject'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. General/Test'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Create')),
        ],
      ),
    );

    final raw = result?.trim() ?? '';
    if (raw.isEmpty) return;

    setState(() {
      locallyCreatedSubjects.add(raw);
      isSubjectMenuOpen = false;
    });

    final uri = Uri(path: '/quests', queryParameters: {'subject': raw});
    if (!mounted) return;
    context.go(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    if(subject.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('No subject selected')),
        body: const Center(child: Text('Please select a subject to view quests.')),
      );
    }
    return FutureBuilder(
      key: ValueKey(subject),
      future: questSystemFuture,
      builder: (context, asyncSnapshot) {
        final loaded = asyncSnapshot.connectionState == ConnectionState.done && asyncSnapshot.hasData;
        final questSystem = asyncSnapshot.data;
        final colorScheme = Theme.of(context).colorScheme;
        final questView = loaded && questSystem != null
            ? IgnorePointer(
                ignoring: !_questViewportReady,
                child: Opacity(
                  opacity: _questViewportReady ? 1 : 0,
                  child: SizedBox.expand(
                    child: PanWidget(key: _panKey, questSystem: questSystem),
                  ),
                ),
              )
            : const Center(child: CircularProgressIndicator());

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.menu), onPressed: () => setState(() => isSubjectMenuOpen = !isSubjectMenuOpen), tooltip: 'Subjects'),
            title: InkWell(
              onTap: () {
                debugMode = !debugMode;
                _panKey.currentState?.debugMode = debugMode;
                setState(() {});
              },
              child: const Text('Quest Screen'),
            ),
            centerTitle: true,
          ),
          body: Stack(
            children: [
              questView,
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !isSubjectMenuOpen,
                  child: AnimatedOpacity(
                    opacity: isSubjectMenuOpen ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: GestureDetector(
                      onTap: () => setState(() => isSubjectMenuOpen = false),
                      child: Container(color: Colors.black.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ),
              _SubjectMenu(
                isOpen: isSubjectMenuOpen,
                currentSubject: subject,
                subjectFuture: subjectFuture,
                expandedGroups: expandedSubjectGroups,
                colorScheme: colorScheme,
                createdSubjects: locallyCreatedSubjects,
                onToggleOpen: () => setState(() => isSubjectMenuOpen = !isSubjectMenuOpen),
                onCreateSubject: _showCreateSubjectDialog,
                onToggleGroup: (group, expanded) {
                  setState(() {
                    if (expanded) {
                      expandedSubjectGroups.add(group);
                    } else {
                      expandedSubjectGroups.remove(group);
                    }
                  });
                },
                onSelectSubject: (selectedSubject) async {
                  if (selectedSubject == subject) {
                    setState(() => isSubjectMenuOpen = false);
                    return;
                  }
                  final loadToken = ++_questSystemLoadToken;
                  setState(() {
                    subject = selectedSubject;
                    isSubjectMenuOpen = false;
                    hasPendingChanges = false;
                    _questViewportReady = false;
                    questSystemFuture = loadQuestSystemFor(selectedSubject, loadToken);
                  });
                },
              ),
            ],
          ),
          floatingActionButton: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AnimatedSlide(
                offset: debugMode && loaded ? Offset.zero : const Offset(0, 2),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCirc,
                child: FloatingActionButton(
                  heroTag: null,
                  child: const Icon(Icons.print),
                  onPressed: () {
                    CustomLayoutSystem layoutSystem = CustomLayoutSystem(questSystem!, CustomLayoutConfig());

                    layoutSystem.layout();
                  },
                ),
              ),
              const SizedBox(width: 16),
              AnimatedSlide(
                offset: debugMode && loaded ? Offset.zero : const Offset(0, 2),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCirc,
                child: FloatingActionButton(
                  heroTag: null,
                  clipBehavior: Clip.none,
                  child: const Stack(clipBehavior: Clip.none, children: [Icon(Icons.auto_awesome_mosaic)]),
                  onPressed: () async {
                    final config = await showLayoutConfigDialog(context);
                    if (config == null || questSystem == null) return;

                    questSystem.layoutQuests(config: config);
                  },
                ),
              ),
              const SizedBox(width: 16),
              AnimatedSlide(
                offset: debugMode && loaded ? Offset.zero : const Offset(0, 2),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCirc,
                child: FloatingActionButton(
                  heroTag: null,
                  clipBehavior: Clip.none,
                  child: const Stack(clipBehavior: Clip.none, children: [Icon(Icons.upload_file)]),
                  onPressed: () {
                    showDialog(
                      context: context,
                      // shows a small screen for you to type in a path of a json file to import quests from, then calls the import function from quest_generator.dart with that path
                      builder: (context) => AlertDialog(
                        title: const Text("Import Quests from JSON"),
                        content: TextField(
                          decoration: const InputDecoration(hintText: "Enter file path"),
                          onSubmitted: (value) async {
                            Navigator.of(context).pop();
                            if (!mounted || questSystem == null) return;
                            await importWithChangeManager(path: value, system: questSystem);
                          },
                        ),
                      ),
                    ); //show change screen
                  },
                ),
              ),
              const SizedBox(width: 16),
              AnimatedSlide(
                offset: debugMode && loaded ? Offset.zero : const Offset(0, 2),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCirc,
                child: FloatingActionButton(
                  heroTag: null,
                  clipBehavior: Clip.none,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.commit),
                      if (loaded)
                        Positioned(
                          top: -kFloatingActionButtonMargin * 1.5,
                          right: -kFloatingActionButtonMargin * 1.5,
                          child: AnimatedScale(
                            scale: questSystem!.changeManager.hasPendingChanges ? 1 : 0,
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutBack,
                            child: AnimatedSlide(
                              offset: questSystem.changeManager.hasPendingChanges ? Offset.zero : const Offset(0, 0.35),
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                              child: const Icon(Icons.circle, color: Colors.red), //red dot
                            ),
                          ), //red dot to indicate changes
                        ),
                    ],
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => QuestChangeScreen(changeManager: questSystem!.changeManager),
                    ); //show change screen
                  },
                ),
              ),
              const SizedBox(width: 16),
              FloatingActionButton(
                heroTag: null,
                child: const Icon(Icons.filter_center_focus),
                onPressed: () {
                  _panKey.currentState?.centerOnAllQuests(context.size?.width ?? 100, context.size?.height ?? 100, autoZoom: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<QuestLayoutConfig?> showLayoutConfigDialog(BuildContext context) {
  const defaultHorizontalSpacing = 120.0;
  const defaultVerticalSpacing = 120.0;
  const defaultLayerSpacing = 350.0;
  const defaultNodeRepulsion = 80000.0;
  const defaultEdgeSpringStrength = 0.005;
  const defaultCrossingPenalty = 1000.0;
  const defaultIdealEdgeLength = 320.0;
  const defaultCrossingMinimizationPasses = 8;
  const defaultForceIterations = 2500;
  const defaultCollisionIterations = 12;
  const defaultCenterGraph = true;
  const defaultAllowCycles = true;

  const defaultEnableHubLayouts = true;
  const defaultEnableCircularClusters = true;
  const defaultEnableSymmetryForces = true;
  const defaultEnableOrganicShapes = true;
  const defaultHubMinConnections = 4;
  const defaultHubOrbitSpacing = 240.0;
  const defaultSymmetryStrength = 0.08;
  const defaultShapeStrength = 0.04;

  return showDialog<QuestLayoutConfig>(
    context: context,
    builder: (context) {
      return const _LayoutConfigDialog(
        horizontal: defaultHorizontalSpacing,
        vertical: defaultVerticalSpacing,
        layer: defaultLayerSpacing,
        nodeRepulsion: defaultNodeRepulsion,
        edgeSpringStrength: defaultEdgeSpringStrength,
        crossingPenalty: defaultCrossingPenalty,
        idealEdgeLength: defaultIdealEdgeLength,
        crossingPasses: defaultCrossingMinimizationPasses,
        forceIterations: defaultForceIterations,
        collisionIterations: defaultCollisionIterations,
        centerGraph: defaultCenterGraph,
        allowCycles: defaultAllowCycles,
        hubMinConnections: defaultHubMinConnections,
        hubOrbitSpacing: defaultHubOrbitSpacing,
        symmetryStrength: defaultSymmetryStrength,
        shapeStrength: defaultShapeStrength,
        enableCircularClusters: defaultEnableCircularClusters,
        enableHubLayouts: defaultEnableHubLayouts,
        enableSymmetryForces: defaultEnableSymmetryForces,
        enableOrganicShapes: defaultEnableOrganicShapes,
      );
    },
  );
}

Future<RadialQuestLayoutConfig?> showStructuredLayoutConfigDialog(BuildContext context) {

  return showDialog<RadialQuestLayoutConfig>(
    context: context,
    builder: (context) {
      return const _RadialLayoutConfigDialog(
        config: RadialQuestLayoutConfig(
          layerSpacing: 420,
          nodeSpacing: 80,
          physicsIterations: 160,
          repulsionStrength: 120000,
          springStrength: 0.018,
          radialStrength: 0.05,
          seed: 1337,
          angleJitter: 0.55,
          snapToGrid: false,
          gridSize: 40,
        ),
      );
    },
  );
}

class _LayoutConfigDialog extends StatefulWidget {
  final double horizontal;
  final double vertical;
  final double layer;
  final double nodeRepulsion;
  final double edgeSpringStrength;
  final double crossingPenalty;
  final double idealEdgeLength;
  final int crossingPasses;
  final int forceIterations;
  final int collisionIterations;
  final bool centerGraph;
  final bool allowCycles;

  final bool enableHubLayouts;
  final bool enableCircularClusters;
  final bool enableSymmetryForces;
  final bool enableOrganicShapes;

  final int hubMinConnections;

  final double hubOrbitSpacing;
  final double symmetryStrength;
  final double shapeStrength;

  const _LayoutConfigDialog({
    required this.horizontal,
    required this.vertical,
    required this.layer,
    required this.nodeRepulsion,
    required this.edgeSpringStrength,
    required this.crossingPenalty,
    required this.idealEdgeLength,
    required this.crossingPasses,
    required this.forceIterations,
    required this.collisionIterations,
    required this.centerGraph,
    required this.allowCycles,
    required this.hubMinConnections,
    required this.hubOrbitSpacing,
    required this.symmetryStrength,
    required this.shapeStrength,
    required this.enableHubLayouts,
    required this.enableCircularClusters,
    required this.enableSymmetryForces,
    required this.enableOrganicShapes,
  });

  @override
  State<_LayoutConfigDialog> createState() => _LayoutConfigDialogState();
}

class _LayoutConfigDialogState extends State<_LayoutConfigDialog> {
  late double horizontal;
  late double vertical;
  late double layer;
  late double nodeRepulsion;
  late double edgeSpringStrength;
  late double crossingPenalty;
  late double idealEdgeLength;
  late int crossingPasses;
  late int forceIterations;
  late int collisionIterations;
  late bool centerGraph;
  late bool allowCycles;

  late bool enableHubLayouts;
  late bool enableCircularClusters;
  late bool enableSymmetryForces;
  late bool enableOrganicShapes;

  late int hubMinConnections;

  late double hubOrbitSpacing;
  late double symmetryStrength;
  late double shapeStrength;

  late TextEditingController horizontalCtrl;
  late TextEditingController verticalCtrl;
  late TextEditingController layerCtrl;
  late TextEditingController nodeRepulsionCtrl;
  late TextEditingController edgeSpringStrengthCtrl;
  late TextEditingController crossingPenaltyCtrl;
  late TextEditingController idealEdgeLengthCtrl;
  late TextEditingController crossingPassesCtrl;
  late TextEditingController forceIterationsCtrl;
  late TextEditingController collisionIterationsCtrl;

  late TextEditingController hubMinConnectionsCtrl;
  late TextEditingController hubOrbitSpacingCtrl;
  late TextEditingController symmetryStrengthCtrl;
  late TextEditingController shapeStrengthCtrl;

  void _applyPreset(_LayoutPreset preset) {
    setState(() {
      switch (preset) {
        case _LayoutPreset.low:
          horizontal = 100;
          vertical = 90;
          layer = 260;

          nodeRepulsion = 40000;
          edgeSpringStrength = 0.010;
          crossingPenalty = 300;
          idealEdgeLength = 220;

          crossingPasses = 8;
          forceIterations = 3600;
          collisionIterations = 8;

          enableHubLayouts = false;
          enableCircularClusters = false;
          enableSymmetryForces = false;
          enableOrganicShapes = false;

          hubMinConnections = 6;

          hubOrbitSpacing = 180;
          symmetryStrength = 0.02;
          shapeStrength = 0.01;

          centerGraph = true;
          allowCycles = true;
          break;
        case _LayoutPreset.balanced:
          horizontal = widget.horizontal;
          vertical = widget.vertical;
          layer = widget.layer;
          nodeRepulsion = widget.nodeRepulsion;
          edgeSpringStrength = widget.edgeSpringStrength;
          crossingPenalty = widget.crossingPenalty;
          idealEdgeLength = widget.idealEdgeLength;
          crossingPasses = widget.crossingPasses;
          forceIterations = widget.forceIterations;
          collisionIterations = widget.collisionIterations;
          centerGraph = widget.centerGraph;
          allowCycles = widget.allowCycles;
          enableHubLayouts = widget.enableHubLayouts;
          enableCircularClusters = widget.enableCircularClusters;
          enableSymmetryForces = widget.enableSymmetryForces;
          enableOrganicShapes = widget.enableOrganicShapes;
          hubMinConnections = widget.hubMinConnections;
          hubOrbitSpacing = widget.hubOrbitSpacing;
          symmetryStrength = widget.symmetryStrength;
          shapeStrength = widget.shapeStrength;
          break;
        case _LayoutPreset.high:
          horizontal = 140;
          vertical = 130;
          layer = 420;

          nodeRepulsion = 140000;
          edgeSpringStrength = 0.010;
          crossingPenalty = 6500;
          idealEdgeLength = 380;

          crossingPasses = 18;
          forceIterations = 300_000;
          collisionIterations = 60;

          enableHubLayouts = true;
          enableCircularClusters = true;
          enableSymmetryForces = true;
          enableOrganicShapes = true;

          hubMinConnections = 4;

          hubOrbitSpacing = 260;
          symmetryStrength = 0.21;
          shapeStrength = 0.17;

          centerGraph = true;
          allowCycles = true;
          break;
      }

      horizontalCtrl.text = horizontal.toStringAsFixed(0);
      verticalCtrl.text = vertical.toStringAsFixed(0);
      layerCtrl.text = layer.toStringAsFixed(0);
      nodeRepulsionCtrl.text = nodeRepulsion.toStringAsFixed(0);
      edgeSpringStrengthCtrl.text = edgeSpringStrength.toStringAsFixed(4);
      crossingPenaltyCtrl.text = crossingPenalty.toStringAsFixed(0);
      idealEdgeLengthCtrl.text = idealEdgeLength.toStringAsFixed(0);
      crossingPassesCtrl.text = crossingPasses.toString();
      forceIterationsCtrl.text = forceIterations.toString();
      collisionIterationsCtrl.text = collisionIterations.toString();
      hubMinConnectionsCtrl.text = hubMinConnections.toString();

      hubOrbitSpacingCtrl.text = hubOrbitSpacing.toStringAsFixed(0);

      symmetryStrengthCtrl.text = symmetryStrength.toStringAsFixed(3);

      shapeStrengthCtrl.text = shapeStrength.toStringAsFixed(3);
    });
  }

  @override
  void initState() {
    super.initState();
    horizontal = widget.horizontal;
    vertical = widget.vertical;
    layer = widget.layer;
    nodeRepulsion = widget.nodeRepulsion;
    edgeSpringStrength = widget.edgeSpringStrength;
    crossingPenalty = widget.crossingPenalty;
    idealEdgeLength = widget.idealEdgeLength;
    crossingPasses = widget.crossingPasses;
    forceIterations = widget.forceIterations;
    collisionIterations = widget.collisionIterations;
    centerGraph = widget.centerGraph;
    allowCycles = widget.allowCycles;

    horizontalCtrl = TextEditingController(text: horizontal.toStringAsFixed(0));
    verticalCtrl = TextEditingController(text: vertical.toStringAsFixed(0));
    layerCtrl = TextEditingController(text: layer.toStringAsFixed(0));
    nodeRepulsionCtrl = TextEditingController(text: nodeRepulsion.toStringAsFixed(0));
    edgeSpringStrengthCtrl = TextEditingController(text: edgeSpringStrength.toString());
    crossingPenaltyCtrl = TextEditingController(text: crossingPenalty.toStringAsFixed(0));
    idealEdgeLengthCtrl = TextEditingController(text: idealEdgeLength.toStringAsFixed(0));
    crossingPassesCtrl = TextEditingController(text: crossingPasses.toString());
    forceIterationsCtrl = TextEditingController(text: forceIterations.toString());
    collisionIterationsCtrl = TextEditingController(text: collisionIterations.toString());

    enableHubLayouts = widget.enableHubLayouts;
    enableCircularClusters = widget.enableCircularClusters;
    enableSymmetryForces = widget.enableSymmetryForces;
    enableOrganicShapes = widget.enableOrganicShapes;

    hubMinConnections = widget.hubMinConnections;

    hubOrbitSpacing = widget.hubOrbitSpacing;
    symmetryStrength = widget.symmetryStrength;
    shapeStrength = widget.shapeStrength;

    hubMinConnectionsCtrl = TextEditingController(text: hubMinConnections.toString());

    hubOrbitSpacingCtrl = TextEditingController(text: hubOrbitSpacing.toStringAsFixed(0));

    symmetryStrengthCtrl = TextEditingController(text: symmetryStrength.toStringAsFixed(3));

    shapeStrengthCtrl = TextEditingController(text: shapeStrength.toStringAsFixed(3));
  }

  @override
  void dispose() {
    horizontalCtrl.dispose();
    verticalCtrl.dispose();
    layerCtrl.dispose();
    nodeRepulsionCtrl.dispose();
    edgeSpringStrengthCtrl.dispose();
    crossingPenaltyCtrl.dispose();
    idealEdgeLengthCtrl.dispose();
    crossingPassesCtrl.dispose();
    forceIterationsCtrl.dispose();
    collisionIterationsCtrl.dispose();
    hubMinConnectionsCtrl.dispose();
    hubOrbitSpacingCtrl.dispose();
    symmetryStrengthCtrl.dispose();
    shapeStrengthCtrl.dispose();
    super.dispose();
  }

  

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onSubmitted,
    String? suffix,
    TextInputType keyboardType = TextInputType.number,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(labelText: label, suffixText: suffix),
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Reset',
          onPressed: () {
            setState(() {
              switch (label) {
                case 'Horizontal':
                  horizontal = widget.horizontal;
                  horizontalCtrl.text = horizontal.toStringAsFixed(0);
                  break;
                case 'Vertical':
                  vertical = widget.vertical;
                  verticalCtrl.text = vertical.toStringAsFixed(0);
                  break;
                case 'Layer':
                  layer = widget.layer;
                  layerCtrl.text = layer.toStringAsFixed(0);
                  break;
                case 'Node repulsion':
                  nodeRepulsion = widget.nodeRepulsion;
                  nodeRepulsionCtrl.text = nodeRepulsion.toStringAsFixed(0);
                  break;
                case 'Edge spring':
                  edgeSpringStrength = widget.edgeSpringStrength;
                  edgeSpringStrengthCtrl.text = edgeSpringStrength.toString();
                  break;
                case 'Crossing penalty':
                  crossingPenalty = widget.crossingPenalty;
                  crossingPenaltyCtrl.text = crossingPenalty.toStringAsFixed(0);
                  break;
                case 'Ideal edge':
                  idealEdgeLength = widget.idealEdgeLength;
                  idealEdgeLengthCtrl.text = idealEdgeLength.toStringAsFixed(0);
                  break;
                case 'Crossing passes':
                  crossingPasses = widget.crossingPasses;
                  crossingPassesCtrl.text = crossingPasses.toString();
                  break;
                case 'Force iterations':
                  forceIterations = widget.forceIterations;
                  forceIterationsCtrl.text = forceIterations.toString();
                  break;
                case 'Collision iterations':
                  collisionIterations = widget.collisionIterations;
                  collisionIterationsCtrl.text = collisionIterations.toString();
                  break;
                default:
              }
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Layout-Settings'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 500, maxWidth: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<_LayoutPreset>(
                segments: const [
                  ButtonSegment(value: _LayoutPreset.low, label: Text('Low'), icon: Icon(Icons.speed)),
                  ButtonSegment(value: _LayoutPreset.balanced, label: Text('Balanced'), icon: Icon(Icons.balance)),
                  ButtonSegment(value: _LayoutPreset.high, label: Text('High'), icon: Icon(Icons.precision_manufacturing)),
                ],
                selected: {_currentPreset()},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  _applyPreset(selection.first);
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Low = fast, Balanced = good default, High = more precice but slower (about 20 seconds for ~50 quests)',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              _section(
                icon: Icons.format_line_spacing,
                title: 'Spacing',
                children: [
                  _labeledSlider(
                    label: 'Horizontal spacing',
                    value: horizontal,
                    min: 20,
                    max: 500,
                    divisions: 48,
                    onChanged: (v) {
                      setState(() {
                        horizontal = v;
                        horizontalCtrl.text = v.toStringAsFixed(0);
                      });
                    },
                    controller: horizontalCtrl,
                    onSubmitted: () {
                      final v = _parseDouble(horizontalCtrl, 20, 500, horizontal);
                      setState(() {
                        horizontal = v;
                        horizontalCtrl.text = v.toStringAsFixed(0);
                      });
                    }, context: context,
                  ),
                  _labeledSlider(
                    label: 'Vertical spacing',
                    value: vertical,
                    min: 10,
                    max: 400,
                    divisions: 39,
                    onChanged: (v) {
                      setState(() {
                        vertical = v;
                        verticalCtrl.text = v.toStringAsFixed(0);
                      });
                    },
                    controller: verticalCtrl,
                    onSubmitted: () {
                      final v = _parseDouble(verticalCtrl, 10, 400, vertical);
                      setState(() {
                        vertical = v;
                        verticalCtrl.text = v.toStringAsFixed(0);
                      });
                    }, context: context,
                  ),
                  _labeledSlider(
                    label: 'Layer spacing',
                    value: layer,
                    min: 100,
                    max: 1000,
                    divisions: 90,
                    onChanged: (v) {
                      setState(() {
                        layer = v;
                        layerCtrl.text = v.toStringAsFixed(0);
                      });
                    },
                    controller: layerCtrl,
                    onSubmitted: () {
                      final v = _parseDouble(layerCtrl, 100, 1000, layer);
                      setState(() {
                        layer = v;
                        layerCtrl.text = v.toStringAsFixed(0);
                      });
                    }, context: context,
                  ),
                ], context: context,
              ),
              const Divider(),
              _labeledSlider(
                label: 'Node repulsion',
                value: nodeRepulsion,
                min: 1000,
                max: 200000,
                divisions: 199,
                onChanged: (v) {
                  setState(() {
                    nodeRepulsion = v;
                    nodeRepulsionCtrl.text = v.toStringAsFixed(0);
                  });
                },
                controller: nodeRepulsionCtrl,
                onSubmitted: () {
                  final v = _parseDouble(nodeRepulsionCtrl, 1000, 200000, nodeRepulsion);
                  setState(() {
                    nodeRepulsion = v;
                    nodeRepulsionCtrl.text = v.toStringAsFixed(0);
                  });
                }, context: context,
              ),
              _labeledSlider(
                label: 'Edge spring strength',
                value: edgeSpringStrength,
                min: 0.001,
                max: 0.2,
                divisions: 199,
                onChanged: (v) {
                  setState(() {
                    edgeSpringStrength = v;
                    edgeSpringStrengthCtrl.text = v.toStringAsFixed(4);
                  });
                },
                controller: edgeSpringStrengthCtrl,
                onSubmitted: () {
                  final v = _parseDouble(edgeSpringStrengthCtrl, 0.001, 0.2, edgeSpringStrength);
                  setState(() {
                    edgeSpringStrength = v;
                    edgeSpringStrengthCtrl.text = v.toString();
                  });
                }, context: context,
              ),
              _labeledSlider(
                label: 'Crossing penalty',
                value: crossingPenalty,
                min: 0,
                max: 5000,
                divisions: 100,
                onChanged: (v) {
                  setState(() {
                    crossingPenalty = v;
                    crossingPenaltyCtrl.text = v.toStringAsFixed(0);
                  });
                },
                controller: crossingPenaltyCtrl,
                onSubmitted: () {
                  final v = _parseDouble(crossingPenaltyCtrl, 0, 5000, crossingPenalty);
                  setState(() {
                    crossingPenalty = v;
                    crossingPenaltyCtrl.text = v.toStringAsFixed(0);
                  });
                }, context: context,
              ),
              _labeledSlider(
                label: 'Ideal edge length',
                value: idealEdgeLength,
                min: 50,
                max: 1000,
                divisions: 95,
                onChanged: (v) {
                  setState(() {
                    idealEdgeLength = v;
                    idealEdgeLengthCtrl.text = v.toStringAsFixed(0);
                  });
                },
                controller: idealEdgeLengthCtrl,
                onSubmitted: () {
                  final v = _parseDouble(idealEdgeLengthCtrl, 50, 1000, idealEdgeLength);
                  setState(() {
                    idealEdgeLength = v;
                    idealEdgeLengthCtrl.text = v.toStringAsFixed(0);
                  });
                }, context: context,
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: _numberField(
                      label: 'Crossing passes',
                      controller: crossingPassesCtrl,
                      onSubmitted: () {
                        final v = _parseInt(crossingPassesCtrl, 0, 100, crossingPasses);
                        setState(() {
                          crossingPasses = v;
                          crossingPassesCtrl.text = v.toString();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _numberField(
                      label: 'Force iterations',
                      controller: forceIterationsCtrl,
                      onSubmitted: () {
                        final v = _parseInt(forceIterationsCtrl, 0, 5000, forceIterations);
                        setState(() {
                          forceIterations = v;
                          forceIterationsCtrl.text = v.toString();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _numberField(
                      label: 'Collision iterations',
                      controller: collisionIterationsCtrl,
                      onSubmitted: () {
                        final v = _parseInt(collisionIterationsCtrl, 0, 100, collisionIterations);
                        setState(() {
                          collisionIterations = v;
                          collisionIterationsCtrl.text = v.toString();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Container()),
                ],
              ),
              const Divider(),
              SwitchListTile(title: const Text('Center graph'), value: centerGraph, onChanged: (v) => setState(() => centerGraph = v)),
              SwitchListTile(title: const Text('Allow cycles'), value: allowCycles, onChanged: (v) => setState(() => allowCycles = v)),
              const Divider(),
              _section(
                icon: Icons.auto_awesome,
                title: 'Advanced Layout',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hub layouts'),
                    subtitle: const Text('Creates orbit structures around important nodes'),
                    value: enableHubLayouts,
                    onChanged: (v) => setState(() => enableHubLayouts = v),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Circular clusters'),
                    subtitle: const Text('Groups related nodes in circular formations'),
                    value: enableCircularClusters,
                    onChanged: (v) => setState(() => enableCircularClusters = v),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Symmetry forces'),
                    subtitle: const Text('Improves visual balance'),
                    value: enableSymmetryForces,
                    onChanged: (v) => setState(() => enableSymmetryForces = v),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Organic shapes'),
                    subtitle: const Text('Adds more natural graph structures'),
                    value: enableOrganicShapes,
                    onChanged: (v) => setState(() => enableOrganicShapes = v),
                  ),

                  const SizedBox(height: 8),

                  _labeledSlider(
                    label: 'Hub orbit spacing',
                    value: hubOrbitSpacing,
                    min: 80,
                    max: 500,
                    divisions: 42,
                    onChanged: (v) {
                      setState(() {
                        hubOrbitSpacing = v;
                        hubOrbitSpacingCtrl.text = v.toStringAsFixed(0);
                      });
                    },
                    controller: hubOrbitSpacingCtrl,
                    onSubmitted: () {
                      final v = _parseDouble(hubOrbitSpacingCtrl, 80, 500, hubOrbitSpacing);

                      setState(() {
                        hubOrbitSpacing = v;
                        hubOrbitSpacingCtrl.text = v.toStringAsFixed(0);
                      });
                    }, context: context,
                  ),

                  _labeledSlider(
                    label: 'Symmetry strength',
                    value: symmetryStrength,
                    min: 0.0,
                    max: 0.2,
                    divisions: 200,
                    onChanged: (v) {
                      setState(() {
                        symmetryStrength = v;
                        symmetryStrengthCtrl.text = v.toStringAsFixed(3);
                      });
                    },
                    controller: symmetryStrengthCtrl,
                    onSubmitted: () {
                      final v = _parseDouble(symmetryStrengthCtrl, 0, 0.2, symmetryStrength);

                      setState(() {
                        symmetryStrength = v;
                        symmetryStrengthCtrl.text = v.toStringAsFixed(3);
                      });
                    }, context: context,
                  ),

                  _labeledSlider(
                    label: 'Organic shape strength',
                    value: shapeStrength,
                    min: 0.0,
                    max: 0.15,
                    divisions: 150,
                    onChanged: (v) {
                      setState(() {
                        shapeStrength = v;
                        shapeStrengthCtrl.text = v.toStringAsFixed(3);
                      });
                    },
                    controller: shapeStrengthCtrl,
                    onSubmitted: () {
                      final v = _parseDouble(shapeStrengthCtrl, 0, 0.15, shapeStrength);

                      setState(() {
                        shapeStrength = v;
                        shapeStrengthCtrl.text = v.toStringAsFixed(3);
                      });
                    }, context: context,
                  ),

                  _numberField(
                    label: 'Hub min connections',
                    controller: hubMinConnectionsCtrl,
                    onSubmitted: () {
                      final v = _parseInt(hubMinConnectionsCtrl, 2, 30, hubMinConnections);

                      setState(() {
                        hubMinConnections = v;
                        hubMinConnectionsCtrl.text = v.toString();
                      });
                    },
                  ),
                ], context: context,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to Defaults'),
                    onPressed: () {
                      setState(() {
                        horizontal = widget.horizontal;
                        vertical = widget.vertical;
                        layer = widget.layer;
                        nodeRepulsion = widget.nodeRepulsion;
                        edgeSpringStrength = widget.edgeSpringStrength;
                        crossingPenalty = widget.crossingPenalty;
                        idealEdgeLength = widget.idealEdgeLength;
                        crossingPasses = widget.crossingPasses;
                        forceIterations = widget.forceIterations;
                        collisionIterations = widget.collisionIterations;
                        centerGraph = widget.centerGraph;
                        allowCycles = widget.allowCycles;

                        horizontalCtrl.text = horizontal.toStringAsFixed(0);
                        verticalCtrl.text = vertical.toStringAsFixed(0);
                        layerCtrl.text = layer.toStringAsFixed(0);
                        nodeRepulsionCtrl.text = nodeRepulsion.toStringAsFixed(0);
                        edgeSpringStrengthCtrl.text = edgeSpringStrength.toString();
                        crossingPenaltyCtrl.text = crossingPenalty.toStringAsFixed(0);
                        idealEdgeLengthCtrl.text = idealEdgeLength.toStringAsFixed(0);
                        crossingPassesCtrl.text = crossingPasses.toString();
                        forceIterationsCtrl.text = forceIterations.toString();
                        collisionIterationsCtrl.text = collisionIterations.toString();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Container()),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final finalHorizontal = _parseDouble(horizontalCtrl, 0, 10000, horizontal);
            final finalVertical = _parseDouble(verticalCtrl, 0, 10000, vertical);
            final finalLayer = _parseDouble(layerCtrl, 0, 10000, layer);
            final finalNodeRepulsion = _parseDouble(nodeRepulsionCtrl, 0, 1e9, nodeRepulsion);
            final finalEdgeSpring = _parseDouble(edgeSpringStrengthCtrl, 0.0, 10.0, edgeSpringStrength);
            final finalCrossingPenalty = _parseDouble(crossingPenaltyCtrl, 0, 1e7, crossingPenalty);
            final finalIdealEdge = _parseDouble(idealEdgeLengthCtrl, 0, 1e6, idealEdgeLength);
            final finalCrossingPasses = _parseInt(crossingPassesCtrl, 0, 10000, crossingPasses);
            final finalForceIterations = _parseInt(forceIterationsCtrl, 0, 100000, forceIterations);
            final finalCollisionIterations = _parseInt(collisionIterationsCtrl, 0, 10000, collisionIterations);

            final finalHubMinConnections = _parseInt(hubMinConnectionsCtrl, 2, 100, hubMinConnections);

            final finalHubOrbitSpacing = _parseDouble(hubOrbitSpacingCtrl, 0, 10000, hubOrbitSpacing);

            final finalSymmetryStrength = _parseDouble(symmetryStrengthCtrl, 0, 1, symmetryStrength);

            final finalShapeStrength = _parseDouble(shapeStrengthCtrl, 0, 1, shapeStrength);

            final config = QuestLayoutConfig(
              horizontalSpacing: finalHorizontal,
              verticalSpacing: finalVertical,
              layerSpacing: finalLayer,
              nodeRepulsion: finalNodeRepulsion,
              edgeSpringStrength: finalEdgeSpring,
              crossingPenalty: finalCrossingPenalty,
              idealEdgeLength: finalIdealEdge,
              crossingMinimizationPasses: finalCrossingPasses,
              forceIterations: finalForceIterations,
              collisionIterations: finalCollisionIterations,
              centerGraph: centerGraph,
              allowCycles: allowCycles,
              hubMinConnections: finalHubMinConnections,
              hubOrbitSpacing: finalHubOrbitSpacing,
              symmetryStrength: finalSymmetryStrength,
              shapeStrength: finalShapeStrength,
              enableHubLayouts: enableHubLayouts,
              enableCircularClusters: enableCircularClusters,
              enableSymmetryForces: enableSymmetryForces,
              enableOrganicShapes: enableOrganicShapes,
            );

            Navigator.of(context).pop(config);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  _LayoutPreset _currentPreset() {
    final matchesLow =
        horizontal == 96 &&
        vertical == 64 &&
        layer == 280 &&
        nodeRepulsion == 42000 &&
        edgeSpringStrength == 0.012 &&
        crossingPenalty == 520 &&
        idealEdgeLength == 250 &&
        crossingPasses == 4 &&
        forceIterations == 80 &&
        collisionIterations == 3 &&
        centerGraph &&
        allowCycles;
    if (matchesLow) return _LayoutPreset.low;

    final matchesHigh =
        horizontal == 140 &&
        vertical == 92 &&
        layer == 390 &&
        nodeRepulsion == 135000 &&
        edgeSpringStrength == 0.03 &&
        crossingPenalty == 1800 &&
        idealEdgeLength == 340 &&
        crossingPasses == 16 &&
        forceIterations == 420 &&
        collisionIterations == 10 &&
        centerGraph &&
        allowCycles;
    if (matchesHigh) return _LayoutPreset.high;

    return _LayoutPreset.balanced;
  }
}

Widget _labeledSlider({
  required String label,
  required double value,
  required double min,
  required double max,
  required int divisions,
  required ValueChanged<double> onChanged,
  required TextEditingController controller,
  required VoidCallback onSubmitted,
  required BuildContext context,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
              child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: value.toStringAsFixed(0), onChanged: onChanged),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(isDense: true),
              onSubmitted: (_) => onSubmitted(),
            ),
          ),
        ],
      ),
    ],
  );
}

Widget _section({required IconData icon, required String title, required List<Widget> children, required BuildContext context}) {
  return Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

enum _LayoutPreset { low, balanced, high }

enum _RadialPreset {
  fast,
  balanced,
  quality,
}

class _RadialLayoutConfigDialog extends StatefulWidget {
  final RadialQuestLayoutConfig config;

  const _RadialLayoutConfigDialog({
    required this.config,
  });

  @override
  State<_RadialLayoutConfigDialog> createState() =>
      _RadialLayoutConfigDialogState();
}

class _RadialLayoutConfigDialogState
    extends State<_RadialLayoutConfigDialog> {
  late double layerSpacing;
  late double nodeSpacing;

  late int physicsIterations;

  late double repulsionStrength;
  late double springStrength;
  late double radialStrength;

  late int seed;
  late double angleJitter;

  late bool snapToGrid;
  late double gridSize;

  late TextEditingController layerSpacingCtrl;
  late TextEditingController nodeSpacingCtrl;

  late TextEditingController physicsIterationsCtrl;

  late TextEditingController repulsionStrengthCtrl;
  late TextEditingController springStrengthCtrl;
  late TextEditingController radialStrengthCtrl;

  late TextEditingController seedCtrl;
  late TextEditingController angleJitterCtrl;

  late TextEditingController gridSizeCtrl;

  @override
  void initState() {
    super.initState();

    final c = widget.config;

    layerSpacing = c.layerSpacing;
    nodeSpacing = c.nodeSpacing;

    physicsIterations = c.physicsIterations;

    repulsionStrength = c.repulsionStrength;
    springStrength = c.springStrength;
    radialStrength = c.radialStrength;

    seed = c.seed;
    angleJitter = c.angleJitter;

    snapToGrid = c.snapToGrid;
    gridSize = c.gridSize;

    layerSpacingCtrl =
        TextEditingController(text: layerSpacing.toStringAsFixed(0));

    nodeSpacingCtrl =
        TextEditingController(text: nodeSpacing.toStringAsFixed(0));

    physicsIterationsCtrl =
        TextEditingController(text: physicsIterations.toString());

    repulsionStrengthCtrl =
        TextEditingController(text: repulsionStrength.toStringAsFixed(0));

    springStrengthCtrl =
        TextEditingController(text: springStrength.toStringAsFixed(3));

    radialStrengthCtrl =
        TextEditingController(text: radialStrength.toStringAsFixed(3));

    seedCtrl =
        TextEditingController(text: seed.toString());

    angleJitterCtrl =
        TextEditingController(text: angleJitter.toStringAsFixed(2));

    gridSizeCtrl =
        TextEditingController(text: gridSize.toStringAsFixed(0));
  }

  @override
  void dispose() {
    layerSpacingCtrl.dispose();
    nodeSpacingCtrl.dispose();

    physicsIterationsCtrl.dispose();

    repulsionStrengthCtrl.dispose();
    springStrengthCtrl.dispose();
    radialStrengthCtrl.dispose();

    seedCtrl.dispose();
    angleJitterCtrl.dispose();

    gridSizeCtrl.dispose();

    super.dispose();
  }

  void _applyPreset(_RadialPreset preset) {
    setState(() {
      switch (preset) {
        case _RadialPreset.fast:
          layerSpacing = 320;
          nodeSpacing = 60;

          physicsIterations = 50;

          repulsionStrength = 60000;
          springStrength = 0.012;
          radialStrength = 0.025;

          seed = 1337;
          angleJitter = 0.25;

          snapToGrid = false;
          gridSize = 32;
          break;

        case _RadialPreset.balanced:
          final c = widget.config;

          layerSpacing = c.layerSpacing;
          nodeSpacing = c.nodeSpacing;

          physicsIterations = c.physicsIterations;

          repulsionStrength = c.repulsionStrength;
          springStrength = c.springStrength;
          radialStrength = c.radialStrength;

          seed = c.seed;
          angleJitter = c.angleJitter;

          snapToGrid = c.snapToGrid;
          gridSize = c.gridSize;
          break;

        case _RadialPreset.quality:
          layerSpacing = 520;
          nodeSpacing = 110;

          physicsIterations = 420;

          repulsionStrength = 220000;
          springStrength = 0.028;
          radialStrength = 0.11;

          seed = 1337;
          angleJitter = 0.85;

          snapToGrid = false;
          gridSize = 48;
          break;
      }

      layerSpacingCtrl.text =
          layerSpacing.toStringAsFixed(0);

      nodeSpacingCtrl.text =
          nodeSpacing.toStringAsFixed(0);

      physicsIterationsCtrl.text =
          physicsIterations.toString();

      repulsionStrengthCtrl.text =
          repulsionStrength.toStringAsFixed(0);

      springStrengthCtrl.text =
          springStrength.toStringAsFixed(3);

      radialStrengthCtrl.text =
          radialStrength.toStringAsFixed(3);

      seedCtrl.text = seed.toString();

      angleJitterCtrl.text =
          angleJitter.toStringAsFixed(2);

      gridSizeCtrl.text =
          gridSize.toStringAsFixed(0);
    });
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Radial Layout Settings'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 560,
            maxWidth: 720,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<_RadialPreset>(
                segments: const [
                  ButtonSegment(
                    value: _RadialPreset.fast,
                    label: Text('Fast'),
                    icon: Icon(Icons.speed),
                  ),
                  ButtonSegment(
                    value: _RadialPreset.balanced,
                    label: Text('Balanced'),
                    icon: Icon(Icons.balance),
                  ),
                  ButtonSegment(
                    value: _RadialPreset.quality,
                    label: Text('Quality'),
                    icon: Icon(Icons.auto_awesome),
                  ),
                ],
                selected: {_RadialPreset.balanced},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  _applyPreset(selection.first);
                },
              ),

              const SizedBox(height: 20),

              _section(
                title: 'Radial Structure',
                icon: Icons.radar,
                children: [
                  _labeledSlider(
                    label: 'Layer spacing',
                    value: layerSpacing,
                    min: 100,
                    max: 1000,
                    divisions: 90,
                    controller: layerSpacingCtrl,
                    onChanged: (v) {
                      setState(() {
                        layerSpacing = v;
                        layerSpacingCtrl.text =
                            v.toStringAsFixed(0);
                      });
                    },
                    onSubmitted: () {
                      final v = _parseDouble(
                        layerSpacingCtrl,
                        100,
                        1000,
                        layerSpacing,
                      );

                      setState(() {
                        layerSpacing = v;
                      });
                    }, context: context,
                  ),

                  _labeledSlider(
                    label: 'Node spacing',
                    value: nodeSpacing,
                    min: 20,
                    max: 240,
                    divisions: 110,
                    controller: nodeSpacingCtrl,
                    onChanged: (v) {
                      setState(() {
                        nodeSpacing = v;
                        nodeSpacingCtrl.text =
                            v.toStringAsFixed(0);
                      });
                    },
                    onSubmitted: () {
                      final v = _parseDouble(
                        nodeSpacingCtrl,
                        20,
                        240,
                        nodeSpacing,
                      );

                      setState(() {
                        nodeSpacing = v;
                      });
                    }, context: context,
                  ),

                  _labeledSlider(
                    label: 'Radial strength',
                    value: radialStrength,
                    min: 0.0,
                    max: 0.2,
                    divisions: 200,
                    controller: radialStrengthCtrl,
                    onChanged: (v) {
                      setState(() {
                        radialStrength = v;
                        radialStrengthCtrl.text =
                            v.toStringAsFixed(3);
                      });
                    },
                    onSubmitted: () {
                      final v = _parseDouble(
                        radialStrengthCtrl,
                        0,
                        0.2,
                        radialStrength,
                      );

                      setState(() {
                        radialStrength = v;
                      });
                    }, context: context,
                  ),
                ],
              ),

              _section(
                title: 'Physics',
                icon: Icons.blur_on,
                children: [
                  _numberField(
                    label: 'Physics iterations',
                    controller:
                    physicsIterationsCtrl,
                    onSubmitted: () {
                      final v = _parseInt(
                        physicsIterationsCtrl,
                        0,
                        10000,
                        physicsIterations,
                      );

                      setState(() {
                        physicsIterations = v;
                      });
                    },
                  ),

                  const SizedBox(height: 12),

                  _labeledSlider(
                    label: 'Repulsion strength',
                    value: repulsionStrength,
                    min: 1000,
                    max: 400000,
                    divisions: 200,
                    controller:
                    repulsionStrengthCtrl,
                    onChanged: (v) {
                      setState(() {
                        repulsionStrength = v;
                        repulsionStrengthCtrl.text =
                            v.toStringAsFixed(0);
                      });
                    },
                    onSubmitted: () {
                      final v = _parseDouble(
                        repulsionStrengthCtrl,
                        1000,
                        400000,
                        repulsionStrength,
                      );

                      setState(() {
                        repulsionStrength = v;
                      });
                    }, context: context,
                  ),

                  _labeledSlider(
                    label: 'Spring strength',
                    value: springStrength,
                    min: 0.001,
                    max: 0.08,
                    divisions: 200,
                    controller:
                    springStrengthCtrl,
                    onChanged: (v) {
                      setState(() {
                        springStrength = v;
                        springStrengthCtrl.text =
                            v.toStringAsFixed(3);
                      });
                    },
                    onSubmitted: () {
                      final v = _parseDouble(
                        springStrengthCtrl,
                        0.001,
                        0.08,
                        springStrength,
                      );

                      setState(() {
                        springStrength = v;
                      });
                    }, context: context,
                  ),
                ],
              ),

              _section(
                title: 'Distribution',
                icon: Icons.scatter_plot,
                children: [
                  _labeledSlider(
                    label: 'Angle jitter',
                    value: angleJitter,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    controller: angleJitterCtrl,
                    onChanged: (v) {
                      setState(() {
                        angleJitter = v;
                        angleJitterCtrl.text =
                            v.toStringAsFixed(2);
                      });
                    },
                    onSubmitted: () {
                      final v = _parseDouble(
                        angleJitterCtrl,
                        0,
                        1,
                        angleJitter,
                      );

                      setState(() {
                        angleJitter = v;
                      });
                    }, context: context,
                  ),

                  _numberField(
                    label: 'Random seed',
                    controller: seedCtrl,
                    onSubmitted: () {
                      final v = _parseInt(
                        seedCtrl,
                        0,
                        999999999,
                        seed,
                      );

                      setState(() {
                        seed = v;
                      });
                    },
                  ),
                ],
              ),

              _section(
                title: 'Grid',
                icon: Icons.grid_4x4,
                children: [
                  SwitchListTile(
                    contentPadding:
                    EdgeInsets.zero,
                    title: const Text(
                      'Snap to grid',
                    ),
                    value: snapToGrid,
                    onChanged: (v) {
                      setState(() {
                        snapToGrid = v;
                      });
                    },
                  ),

                  _labeledSlider(
                    label: 'Grid size',
                    value: gridSize,
                    min: 8,
                    max: 128,
                    divisions: 60,
                    controller: gridSizeCtrl,
                    onChanged: (v) {
                      setState(() {
                        gridSize = v;
                        gridSizeCtrl.text =
                            v.toStringAsFixed(0);
                      });
                    },
                    onSubmitted: () {
                      final v = _parseDouble(
                        gridSizeCtrl,
                        8,
                        128,
                        gridSize,
                      );

                      setState(() {
                        gridSize = v;
                      });
                    }, context: context,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
          onPressed: () {
            Navigator.of(context).pop(
              RadialQuestLayoutConfig(
                layerSpacing: layerSpacing,
                nodeSpacing: nodeSpacing,

                physicsIterations:
                physicsIterations,

                repulsionStrength:
                repulsionStrength,

                springStrength:
                springStrength,

                radialStrength:
                radialStrength,

                seed: seed,
                angleJitter: angleJitter,

                snapToGrid: snapToGrid,
                gridSize: gridSize,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onSubmitted,
    String? suffix,
    TextInputType keyboardType = TextInputType.number,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(labelText: label, suffixText: suffix),
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Reset',
          onPressed: () {
            setState(() {
              switch (label) {
                case 'Physics iterations':
                  physicsIterations = widget.config.physicsIterations;
                  physicsIterationsCtrl.text = physicsIterations.toStringAsFixed(0);
                  break;
                case 'Random seed':
                  seed = widget.config.seed;
                  seedCtrl.text = seed.toStringAsFixed(0);
                  break;
                default:
              }
            });
          },
        ),
      ],
    );
  }
}

double _parseDouble(TextEditingController c, double min, double max, double fallback) {
  final v = double.tryParse(c.text.replaceAll(',', '.'));
  if (v == null) return fallback;
  return v.clamp(min, max);
}

int _parseInt(TextEditingController c, int min, int max, int fallback) {
  final v = int.tryParse(c.text);
  if (v == null) return fallback;
  return v.clamp(min, max);
}

class _SubjectNode {
  _SubjectNode({required this.name, required this.path});

  final String name;
  final String path;
  final Map<String, _SubjectNode> children = {};
  bool isSelectable = false;
}

class _SubjectMenu extends StatelessWidget {
  const _SubjectMenu({
    required this.isOpen,
    required this.currentSubject,
    required this.subjectFuture,
    required this.expandedGroups,
    required this.colorScheme,
    required this.createdSubjects,
    required this.onToggleOpen,
    required this.onCreateSubject,
    required this.onToggleGroup,
    required this.onSelectSubject,
  });

  static const double menuWidth = 280;

  final bool isOpen;
  final String currentSubject;
  final Future<List<String>> subjectFuture;
  final Set<String> expandedGroups;
  final ColorScheme colorScheme;
  final Set<String> createdSubjects;
  final VoidCallback onToggleOpen;
  final VoidCallback onCreateSubject;
  final void Function(String group, bool expanded) onToggleGroup;
  final void Function(String subject) onSelectSubject;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      top: 0,
      bottom: 0,
      left: isOpen ? 0 : -menuWidth,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !isOpen,
        child: SizedBox(
          width: menuWidth,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(4, 0))],
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Subjects',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colorScheme.onSurface),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.add), tooltip: 'Create subject', onPressed: onCreateSubject),
                        IconButton(icon: const Icon(Icons.chevron_left), onPressed: onToggleOpen),
                      ],
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<List<String>>(
                      future: subjectFuture,
                      builder: (context, snapshot) {
                        final subjects = <String>{...createdSubjects, ...(snapshot.data ?? [])};
                        if (currentSubject.trim().isNotEmpty) subjects.add(currentSubject.trim());
                        final list = subjects.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                        final root = _buildSubjectTree(list);

                        return ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: _buildSubjectNodes(context, root, 0, currentSubject, expandedGroups, colorScheme, onToggleGroup, onSelectSubject),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

_SubjectNode _buildSubjectTree(List<String> subjects) {
  final root = _SubjectNode(name: '', path: '');

  for (final subject in subjects) {
    final parts = subject.split('/').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) continue;

    var node = root;
    final pathParts = <String>[];

    for (final part in parts) {
      pathParts.add(part);
      node = node.children.putIfAbsent(part, () => _SubjectNode(name: part, path: pathParts.join('/')));
    }

    node.isSelectable = true;
  }

  return root;
}

List<Widget> _buildSubjectNodes(
  BuildContext context,
  _SubjectNode node,
  int depth,
  String currentSubject,
  Set<String> expandedGroups,
  ColorScheme colorScheme,
  void Function(String group, bool expanded) onToggleGroup,
  void Function(String subject) onSelectSubject,
) {
  final children = node.children.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return children.map((child) {
    final isSelected = child.path.toLowerCase() == currentSubject.toLowerCase();
    final hasChildren = child.children.isNotEmpty;
    final titleStyle = TextStyle(color: isSelected ? colorScheme.primary : colorScheme.onSurface, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500);

    if (hasChildren) {
      return ExpansionTile(
        key: PageStorageKey<String>('subject:${child.path}'),
        initiallyExpanded: expandedGroups.contains(child.path),
        tilePadding: EdgeInsets.only(left: 12 + depth * 14.0, right: 12),
        childrenPadding: EdgeInsets.only(left: 8 + depth * 14.0, right: 12),
        onExpansionChanged: (expanded) => onToggleGroup(child.path, expanded),
        title: Row(
          children: [
            Expanded(child: Text(child.name, style: titleStyle)),
            if (child.isSelectable) TextButton(onPressed: () => onSelectSubject(child.path), child: const Text('Open')),
          ],
        ),
        children: _buildSubjectNodes(context, child, depth + 1, currentSubject, expandedGroups, colorScheme, onToggleGroup, onSelectSubject),
      );
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 20 + depth * 14.0, right: 12),
      title: Text(child.name, style: titleStyle),
      onTap: () => onSelectSubject(child.path),
    );
  }).toList();
}
