//test app for the quest screen

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumox/logic/quests/quest_layout/quest_layout_config.dart';
import 'package:lumox/logic/repositories/quest_repository.dart';
import 'package:lumox/logic/quests/quest.dart';
import 'package:lumox/logic/quests/quest_system.dart';
import 'package:lumox/tools/quest_generator.dart';
import 'package:lumox/ui/screens/quests/core/pan.dart';
import 'package:lumox/ui/screens/quests/version_management/change_screen.dart';

class QuestScreen extends StatefulWidget {
  final String subject;
  final List<int> focusQuestIds;
  final bool zoomOutIfNeeded;

  const QuestScreen({
    super.key,
    required this.subject,
    this.focusQuestIds = const [],
    this.zoomOutIfNeeded = true,
  });

  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> {
  final GlobalKey<PanWidgetState> _panKey = GlobalKey<PanWidgetState>();
  bool debugMode = false;
  bool hasPendingChanges = false;
  bool isSubjectMenuOpen = false;
  final Set<String> expandedSubjectGroups = {};
  final Set<String> locallyCreatedSubjects = {};
  late Future<List<String>> subjectFuture;

  @override
  initState() {
    super.initState();
    print("Initializing TestQuestScreen with subject: ${widget.subject}");
    questSystemFuture = loadQuestSystem();
    subjectFuture = questRepo.fetchQuestSubjects();
  }

  Future<QuestSystem> loadQuestSystem() async {
    QuestSystem questSystem = QuestSystem();
    print("-- Loading quests for subject: ${widget.subject}");
    await questSystem.loadFromServer(widget.subject);

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (!mounted) return;
      setState(() {
        final focusQuests = widget.focusQuestIds
            .map((id) => questSystem.maybeGetQuestById(id))
            .whereType<Quest>()
            .toList();

        if (focusQuests.isEmpty) {
          _panKey.currentState?.centerOnAllQuests(context.size?.width ?? 1000, context.size?.height ?? 1000);
          return;
        }

        final panState = _panKey.currentState;
        if (panState == null) return;
        (panState as dynamic).focusOnQuests(
          focusQuests,
          context.size?.width ?? 1000,
          context.size?.height ?? 1000,
          zoomOutIfNeeded: widget.zoomOutIfNeeded,
        );
      });
    });

    questSystem.changeManager.addListener(() {
      if (!mounted) return;
      if (questSystem.changeManager.hasPendingChanges != hasPendingChanges) {
        setState(() {
          hasPendingChanges = questSystem.changeManager.hasPendingChanges;
        });
      }
    });
    return questSystem;
  }

  late Future<QuestSystem> questSystemFuture;

  @override
  void didUpdateWidget(covariant QuestScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject != widget.subject) {
      questSystemFuture = loadQuestSystem();
      setState(() {});
    }
  }

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
    return FutureBuilder(
      future: questSystemFuture,
      builder: (context, asyncSnapshot) {
        final loaded = asyncSnapshot.hasData;
        final questSystem = asyncSnapshot.data;
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => setState(() => isSubjectMenuOpen = !isSubjectMenuOpen),
              tooltip: 'Subjects',
            ),
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
              loaded
                  ? SizedBox.expand(
                      child: PanWidget(key: _panKey, questSystem: questSystem!),
                    )
                  : const Center(child: CircularProgressIndicator()),
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
                currentSubject: widget.subject,
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
                onSelectSubject: (subject) {
                  if (subject == widget.subject) {
                    setState(() => isSubjectMenuOpen = false);
                    return;
                  }
                  setState(() => isSubjectMenuOpen = false);
                  final uri = Uri(path: '/quests', queryParameters: {'subject': subject});
                  context.go(uri.toString());
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
                  clipBehavior: Clip.none,
                  child: const Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.auto_awesome_mosaic), 
                    ],
                  ),
                  onPressed: () async {
                    
                    final config = await showLayoutConfigDialog(context);
                    if(config == null || questSystem == null) return;
                    
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
                  child: const Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.upload_file),
                    ],
                  ),
                  onPressed: () {
                    showDialog(
                      context: context, // shows a small screen for you to type in a path of a json file to import quests from, then calls the import function from quest_generator.dart with that path
                      builder: (context) => AlertDialog(
                        title: const Text("Import Quests from JSON"),
                        content: TextField(
                          decoration: const InputDecoration(hintText: "Enter file path"),
                          onSubmitted: (value) async {
                            Navigator.of(context).pop();
                            if(!mounted || questSystem == null) return;
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
  const defaultVerticalSpacing = 80.0;
  const defaultLayerSpacing = 350.0;
  const defaultNodeRepulsion = 90000.0;
  const defaultEdgeSpringStrength = 0.02;
  const defaultCrossingPenalty = 1000.0;
  const defaultIdealEdgeLength = 320.0;
  const defaultCrossingMinimizationPasses = 12;
  const defaultForceIterations = 250;
  const defaultCollisionIterations = 8;
  const defaultCenterGraph = true;
  const defaultAllowCycles = true;

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

  void _applyPreset(_LayoutPreset preset) {
    setState(() {
      switch (preset) {
        case _LayoutPreset.low:
          horizontal = 120;
          vertical = 80;
          layer = 350;
          nodeRepulsion = 90000;
          edgeSpringStrength = 0.02;
          crossingPenalty = 1000;
          idealEdgeLength = 320;
          crossingPasses = 8;
          forceIterations = 6000;
          collisionIterations = 10;
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
          break;
        case _LayoutPreset.high:
          horizontal = 120;
          vertical = 80;
          layer = 350;
          nodeRepulsion = 90000;
          edgeSpringStrength = 0.02;
          crossingPenalty = 5000;
          idealEdgeLength = 320;
          crossingPasses = 16;
          forceIterations = 100000;
          collisionIterations = 80;
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
    super.dispose();
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
          constraints: const BoxConstraints(minWidth: 400),
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
                'Low = schnell, Balanced = guter Standard, High = genauer aber langsamer',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
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
                },
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
                },
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
                },
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
                },
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
                },
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
                },
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
                },
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
              SwitchListTile(
                title: const Text('Center graph'),
                value: centerGraph,
                onChanged: (v) => setState(() => centerGraph = v),
              ),
              SwitchListTile(
                title: const Text('Allow cycles'),
                value: allowCycles,
                onChanged: (v) => setState(() => allowCycles = v),
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
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
            );

            Navigator.of(context).pop(config);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  _LayoutPreset _currentPreset() {
    final matchesLow = horizontal == 96 && vertical == 64 && layer == 280 && nodeRepulsion == 42000 && edgeSpringStrength == 0.012 && crossingPenalty == 520 && idealEdgeLength == 250 && crossingPasses == 4 && forceIterations == 80 && collisionIterations == 3 && centerGraph && allowCycles;
    if (matchesLow) return _LayoutPreset.low;

    final matchesHigh = horizontal == 140 && vertical == 92 && layer == 390 && nodeRepulsion == 135000 && edgeSpringStrength == 0.03 && crossingPenalty == 1800 && idealEdgeLength == 340 && crossingPasses == 16 && forceIterations == 420 && collisionIterations == 10 && centerGraph && allowCycles;
    if (matchesHigh) return _LayoutPreset.high;

    return _LayoutPreset.balanced;
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: value.toStringAsFixed(0),
                onChanged: onChanged,
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
}

enum _LayoutPreset { low, balanced, high }


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
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Create subject',
                          onPressed: onCreateSubject,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: onToggleOpen,
                        ),
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
                          children: _buildSubjectNodes(
                            context,
                            root,
                            0,
                            currentSubject,
                            expandedGroups,
                            colorScheme,
                            onToggleGroup,
                            onSelectSubject,
                          ),
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
  final children = node.children.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return children.map((child) {
    final isSelected = child.path.toLowerCase() == currentSubject.toLowerCase();
    final hasChildren = child.children.isNotEmpty;
    final titleStyle = TextStyle(
      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
    );

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
            if (child.isSelectable)
              TextButton(
                onPressed: () => onSelectSubject(child.path),
                child: const Text('Open'),
              ),
          ],
        ),
        children: _buildSubjectNodes(
          context,
          child,
          depth + 1,
          currentSubject,
          expandedGroups,
          colorScheme,
          onToggleGroup,
          onSelectSubject,
        ),
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
