import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:lumox/logic/dictionary/dictionary_entry.dart';
import 'package:lumox/logic/quests/quest.dart';
import 'package:lumox/logic/quests/quest_change_manager.dart';
import 'package:lumox/logic/quests/quest_system.dart';
import 'package:lumox/logic/repositories/dictionary_repository.dart';
import 'package:lumox/logic/repositories/quest_title_alias_repository.dart';
import 'package:lumox/ui/widgets/dictionary/dictionary_linkifier.dart';
import 'package:lumox/util/extensions/num_distance.dart';

import '../../../theme/theme_ui_values.dart';

class QuestDetailScreen extends StatefulWidget {
  final Quest quest;
  final bool debugMode;
  final bool editMode;
  final void Function(QuestPatch questPatch, [String? changeMessage])? onDoneEditing;
  final void Function(Quest quest)? onDelete;
  final String? recommendedChangeMessage;

  final QuestSystem questSystem;

  const QuestDetailScreen({
    super.key,
    required this.quest,
    required this.debugMode,
    required this.editMode,
    this.onDoneEditing,
    this.recommendedChangeMessage,
    this.onDelete,
    required this.questSystem,
  });

  @override
  State<QuestDetailScreen> createState() => _QuestDetailScreenState();
}

class _QuestDetailScreenState extends State<QuestDetailScreen> {
  late bool _editMode;
  late Quest _editedQuest;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _posXCtrl;
  late final TextEditingController _posYCtrl;
  late final TextEditingController _sizeXCtrl;
  late final TextEditingController _sizeYCtrl;
  late double _difficulty;
  Color? _newColor;

  QuestSystem get questSystem => widget.questSystem;

  @override
  void initState() {
    super.initState();
    _editMode = widget.editMode;
    _editedQuest = widget.quest;
    _nameCtrl = TextEditingController(text: widget.quest.name);
    _descriptionCtrl = TextEditingController(text: widget.quest.description);
    _posXCtrl = TextEditingController(text: widget.quest.posX.toStringAsFixed(0));
    _posYCtrl = TextEditingController(text: widget.quest.posY.toStringAsFixed(0));
    _sizeXCtrl = TextEditingController(text: widget.quest.sizeX.toStringAsFixed(0));
    _sizeYCtrl = TextEditingController(text: widget.quest.sizeY.toStringAsFixed(0));
    _difficulty = widget.quest.difficulty.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _posXCtrl.dispose();
    _posYCtrl.dispose();
    _sizeXCtrl.dispose();
    _sizeYCtrl.dispose();
    super.dispose();
  }

  /// Reads all controllers and builds an updated [Quest].
  /// Requires Quest to have a copyWith method.
  QuestPatch _buildUpdatedQuestPatch() {
    String newNameRaw = _nameCtrl.text.trim();
    String? newName = (newNameRaw.isEmpty || newNameRaw == widget.quest.name) ? null : newNameRaw;
    String newDescriptionRaw = _descriptionCtrl.text.trim();
    String? newDescription = (newDescriptionRaw.isEmpty || newDescriptionRaw == widget.quest.description) ? null : newDescriptionRaw;

    double? newPosXRaw = double.tryParse(_posXCtrl.text);
    double? newPosX = (newPosXRaw == null || newPosXRaw.distanceTo(widget.quest.posX) < 1) ? null : newPosXRaw;
    double? newPosYRaw = double.tryParse(_posYCtrl.text);
    double? newPosY = (newPosYRaw == null || newPosYRaw.distanceTo(widget.quest.posY) < 1) ? null : newPosYRaw;
    double? newSizeXRaw = double.tryParse(_sizeXCtrl.text);
    double? newSizeX = (newSizeXRaw == null || newSizeXRaw == widget.quest.sizeX) ? null : newSizeXRaw;
    double? newSizeYRaw = double.tryParse(_sizeYCtrl.text);
    double? newSizeY = (newSizeYRaw == null || newSizeYRaw == widget.quest.sizeY) ? null : newSizeYRaw;

    double? newDifficulty = (_difficulty == widget.quest.difficulty) ? null : _difficulty;

    Color? newColor = (_newColor == null || _newColor == widget.quest.color) ? null : _newColor;

    print(
      "Built QuestPatch with values: name=$newName, description=$newDescription, posX=$newPosX, posY=$newPosY, sizeX=$newSizeX, sizeY=$newSizeY, difficulty=$newDifficulty, color=$newColor",
    );

    return QuestPatch(
      name: newName,
      description: newDescription,
      posX: newPosX,
      posY: newPosY,
      sizeX: newSizeX,
      sizeY: newSizeY,
      difficulty: newDifficulty,
      color: newColor,
    );
  }

  void _saveAndExit() {
    final updated = _buildUpdatedQuestPatch();
    setState(() {
      _editedQuest = updated.applyTo(_editedQuest);
      _editMode = false;
    });
    final smartMessage = widget.recommendedChangeMessage ?? updated.generateChangeMessage();
    showChangeMessageDialog(smartMessage).then((message) {
      widget.onDoneEditing?.call(updated, message.isEmpty ? null : message);
    });
  }

  ///asks the user what he changed and returns the message, or null if the user cancels
  Future<String> showChangeMessageDialog(String? recommendedChangeMessage) async {
    String? message;
    await showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: recommendedChangeMessage ?? '')
          ..selection = TextSelection(baseOffset: 0, extentOffset: recommendedChangeMessage?.length ?? 0);
        return AlertDialog(
          title: const Text('Describe your changes'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'What did you change?'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                message = controller.text.trim();
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    return message ?? '';
  }

  void _toggleEditMode() => setState(() => _editMode = !_editMode);

  void onDelete() {
    setState(() {
      widget.onDelete?.call(widget.quest);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          _QuestSliverAppBar(
            quest: _editedQuest,
            colorScheme: colorScheme,
            debugMode: widget.debugMode,
            editMode: _editMode,
            nameController: _nameCtrl,
            onToggleEditMode: widget.debugMode ? _toggleEditMode : null,
            onColorChanged: (newColor) {
              setState(() {
                _newColor = newColor;
              });
            },
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _StatusRow(quest: _editedQuest, colorScheme: colorScheme, questSystem: questSystem),
                const SizedBox(height: 24),
                _SectionCard(
                  colorScheme: colorScheme,
                  child: _DescriptionSection(
                    colorScheme: colorScheme,
                    editMode: _editMode,
                    controller: _descriptionCtrl,
                    description: _editedQuest.description,
                    subject: _editedQuest.subject,
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  colorScheme: colorScheme,
                  child: _AliasesSection(questId: _editedQuest.id, colorScheme: colorScheme, editMode: _editMode),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  colorScheme: colorScheme,
                  child: _DifficultySection(
                    colorScheme: colorScheme,
                    editMode: _editMode,
                    initialDifficulty: _difficulty,
                    onDifficultyChanged: (v) => setState(() => _difficulty = v),
                  ),
                ),
                if (questSystem.prerequisiteIds(_editedQuest.id).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    colorScheme: colorScheme,
                    child: _PrerequisitesSection(
                      quest: _editedQuest,
                      colorScheme: colorScheme,
                      debugMode: widget.debugMode,
                      editMode: _editMode,
                      questSystem: questSystem,
                    ),
                  ),
                ],
                if (widget.debugMode && _editMode) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    colorScheme: colorScheme,
                    child: _MetaSection(
                      quest: _editedQuest,
                      colorScheme: colorScheme,
                      posXCtrl: _posXCtrl,
                      posYCtrl: _posYCtrl,
                      sizeXCtrl: _sizeXCtrl,
                      sizeYCtrl: _sizeYCtrl,
                    ),
                  ),
                ],
                if (_editMode) ...[
                  const SizedBox(height: 28),
                  _SaveButton(colorScheme: colorScheme, onSave: _saveAndExit),
                  _DeleteButton(colorScheme: colorScheme, onDelete: onDelete),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _AliasesSection extends StatefulWidget {
  final int questId;
  final ColorScheme colorScheme;
  final bool editMode;

  const _AliasesSection({required this.questId, required this.colorScheme, required this.editMode});

  @override
  State<_AliasesSection> createState() => _AliasesSectionState();
}

class _AliasesSectionState extends State<_AliasesSection> {
  final TextEditingController _aliasController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  List<String> _aliases = const [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAliases();
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  Future<void> _loadAliases() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final aliases = await questTitleAliasRepository.fetchAliases(questId: widget.questId);
      if (!mounted) return;
      setState(() {
        _aliases = aliases;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Failed to load aliases.';
      });
    }
  }

  Future<void> _addAlias() async {
    final alias = _aliasController.text.trim();
    if (alias.isEmpty || _aliases.contains(alias)) {
      _aliasController.clear();
      return;
    }

    setState(() => _saving = true);
    try {
      await questTitleAliasRepository.addAlias(questId: widget.questId, alias: alias);
      _aliasController.clear();
      await _loadAliases();
    } finally {
      if (mounted) setState(() => _saving = false);
    }

  }

  Future<void> _removeAlias(String alias) async {
    setState(() => _saving = true);
    try {
      await questTitleAliasRepository.removeAlias(questId: widget.questId, alias: alias);
      await _loadAliases();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'Aliases', colorScheme: cs),
          const SizedBox(height: 10),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_aliases.isEmpty)
            Text('No aliases yet', style: TextStyle(color: cs.onSurfaceVariant))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _aliases
                  .map(
                    (alias) => InputChip(
                  label: Text(alias),
                  onDeleted: _saving ? null : () => _removeAlias(alias),
                ),
              )
                  .toList(),
            ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(_errorMessage!, style: TextStyle(color: cs.error, fontSize: 12)),
          ],
          if(widget.editMode) const SizedBox(height: 12),
          if(widget.editMode) Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _aliasController,
                  decoration: _editInputDecoration(context, cs, hint: 'Add alias…'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _addAlias,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Difficulty ────────────────────────────────────────────────────────────────

class _DifficultySection extends StatefulWidget {
  final ColorScheme colorScheme;
  final bool editMode;
  final double initialDifficulty;
  final ValueChanged<double> onDifficultyChanged;

  const _DifficultySection({required this.colorScheme, required this.editMode, required this.initialDifficulty, required this.onDifficultyChanged});

  @override
  State<_DifficultySection> createState() => _DifficultySectionState();
}

class _DifficultySectionState extends State<_DifficultySection> {
  late double _difficulty;

  @override
  initState() {
    super.initState();
    _difficulty = widget.initialDifficulty.clamp(0.0, 1.0);
  }

  String _difficultyLabel(double d) {
    if (d < 0.2) return 'Beginner';
    if (d < 0.4) return 'Novice';
    if (d < 0.6) return 'Intermediate';
    if (d < 0.8) return 'Advanced';
    return 'Expert';
  }

  Color _difficultyColor(double d, ColorScheme cs) {
    if (d < 0.4) return cs.tertiary;
    if (d < 0.7) return cs.primary;
    return cs.error;
  }

  @override
  Widget build(BuildContext context) {
    final color = _difficultyColor(_difficulty, widget.colorScheme);
    const segments = 10;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionLabel(label: 'Difficulty', colorScheme: widget.colorScheme),
              ),
              // Label + percentage animate as the slider moves.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                child: Text(
                  key: ValueKey('${_difficultyLabel(_difficulty)}-${(_difficulty * 100).round()}'),
                  '${_difficultyLabel(_difficulty)}  ·  ${(_difficulty * 100).round()}%',
                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.editMode)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.15),
                inactiveTrackColor: widget.colorScheme.surfaceContainerHighest,
                valueIndicatorColor: color,
                trackHeight: 8,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value: _difficulty,
                onChanged: (v) {
                  setState(() {
                    _difficulty = v;
                  });
                },
                onChangeEnd: (value) => widget.onDifficultyChanged(value),
                divisions: 20,
                label: '${(_difficulty * 100).round()}%',
              ),
            )
          else ...[
            Row(
              children: [
                Icon(Icons.bar_chart_rounded, size: 16, color: widget.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('${(_difficulty * 100).round()}%', style: TextStyle(color: widget.colorScheme.onSurfaceVariant, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: List.generate(segments, (i) {
                final filled = i < (_difficulty * segments).round();
                return Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(right: i < segments - 1 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: filled ? color : widget.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(context.uiRadiusSm),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Prerequisites ─────────────────────────────────────────────────────────────

class _PrerequisitesSection extends StatelessWidget {
  final Quest quest;
  final ColorScheme colorScheme;
  final bool debugMode;
  final bool editMode;

  final QuestSystem questSystem;

  const _PrerequisitesSection({required this.quest, required this.colorScheme, required this.debugMode, required this.editMode, required this.questSystem});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'Requirements', colorScheme: colorScheme),
          const SizedBox(height: 12),
          ...questSystem.prerequisitesOf(quest.id).asMap().entries.map((entry) {
            final prereq = entry.value;
            final isLast = entry.key == questSystem.prerequisiteIds(quest.id).length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: prereq.isCompleted ? colorScheme.tertiaryContainer : colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      prereq.isCompleted ? Icons.check_rounded : Icons.hourglass_empty_rounded,
                      size: 16,
                      color: prereq.isCompleted ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prereq.name,
                          style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text(prereq.subject, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (debugMode)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(context.uiRadiusSm)),
                      child: Text(
                        '#${prereq.id}',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
// ── App Bar ───────────────────────────────────────────────────────────────────

class _QuestSliverAppBar extends StatelessWidget {
  final Quest quest;
  final ColorScheme colorScheme;
  final bool debugMode;
  final bool editMode;
  final TextEditingController nameController;
  final VoidCallback? onToggleEditMode;
  final void Function(Color newColor)? onColorChanged;

  const _QuestSliverAppBar({
    required this.quest,
    required this.colorScheme,
    required this.debugMode,
    required this.editMode,
    required this.nameController,
    this.onToggleEditMode,
    this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      stretch: true,
      backgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onPrimaryContainer,
      actions: [
        if (debugMode && onToggleEditMode != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: IconButton(
                key: ValueKey(editMode),
                icon: Icon(editMode ? Icons.edit_off_rounded : Icons.edit_rounded),
                tooltip: editMode ? 'Exit Edit Mode' : 'Edit Mode',
                onPressed: onToggleEditMode,
                style: IconButton.styleFrom(backgroundColor: editMode ? colorScheme.onPrimaryContainer.withValues(alpha: 0.18) : Colors.transparent),
              ),
            ),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
        // Extra right padding in debug mode to avoid overlap with the action icon.
        titlePadding: EdgeInsets.fromLTRB(60, 0, debugMode ? 56 : 20, 16),
        title: editMode
            ? TextField(
                controller: nameController,
                style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 20, height: 1.2),
                maxLines: 1,
                cursorColor: colorScheme.onPrimaryContainer,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Quest-Name',
                  filled: false,
                  hintStyle: TextStyle(color: colorScheme.onPrimaryContainer.withValues(alpha: 0.35), fontSize: 20),
                ),
              )
            : Text(
                quest.name,
                style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 20, height: 1.2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colorScheme.primaryContainer, colorScheme.secondaryContainer],
                ),
              ),
            ),
            CustomPaint(painter: _GridPatternPainter(colorScheme.onPrimaryContainer.withValues(alpha: 0.06))),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, colorScheme.primaryContainer.withValues(alpha: 0.85)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 60,
              right: 16,
              child: _SubjectBadge(subject: quest.subject, colorScheme: colorScheme),
            ),
            if (debugMode)
              Positioned(
                top: 64,
                left: 20,
                child: Text(
                  '#${quest.id}',
                  style: TextStyle(color: colorScheme.onPrimaryContainer.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5),
                ),
              ),
            if (editMode)
              IconButton(
                hoverColor: Colors.transparent,
                onPressed: () async {
                  Color? temp;
                  await showDialog<void>(
                    context: context,
                    builder: (c2) => AlertDialog(
                      title: const Text('Primary Seed'),
                      content: SizedBox(
                        width: 300,
                        child: SingleChildScrollView(
                          child: ColorPicker(
                            pickerColor: quest.color,
                            onColorChanged: (c) => temp = c,
                            enableAlpha: false,
                            portraitOnly: true,
                            labelTypes: const [ColorLabelType.hex],
                          ),
                        ),
                      ),
                      actions: [FilledButton(onPressed: () => Navigator.pop(c2), child: const Text('OK'))],
                    ),
                  );
                  if (temp != null) {
                    onColorChanged?.call(temp!);
                  }
                },
                icon: const Icon(Icons.colorize_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _GridPatternPainter extends CustomPainter {
  final Color color;

  _GridPatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPatternPainter old) => old.color != color;
}

class _SubjectBadge extends StatelessWidget {
  final String subject;
  final ColorScheme colorScheme;

  const _SubjectBadge({required this.subject, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        boxShadow: [BoxShadow(color: colorScheme.primary.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Text(
            subject.toUpperCase(),
            style: TextStyle(color: colorScheme.onPrimary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

// ── Status Row ────────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final Quest quest;
  final ColorScheme colorScheme;

  final QuestSystem questSystem;

  const _StatusRow({required this.quest, required this.colorScheme, required this.questSystem});

  @override
  Widget build(BuildContext context) {
    final isCompleted = quest.isCompleted;

    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isCompleted ? colorScheme.tertiaryContainer : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(context.uiRadiusLg),
            border: Border.all(color: isCompleted ? colorScheme.tertiary : colorScheme.outline.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: isCompleted ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                isCompleted ? 'Done' : 'Open',
                style: TextStyle(
                  color: isCompleted ? colorScheme.onTertiaryContainer : colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (questSystem.prerequisiteIds(quest.id).isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(context.uiRadiusLg),
              border: Border.all(color: colorScheme.outline.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 15, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${questSystem.prerequisiteIds(quest.id).length} Prerequisite${questSystem.prerequisiteIds(quest.id).length > 1 ? 's' : ''}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Section Card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  final ColorScheme colorScheme;

  const _SectionCard({required this.child, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

// ── Description ───────────────────────────────────────────────────────────────

class _DescriptionSection extends StatefulWidget {
  final ColorScheme colorScheme;
  final bool editMode;
  final TextEditingController controller;
  final String description;
  final String subject;

  const _DescriptionSection({required this.colorScheme, required this.editMode, required this.controller, required this.description, required this.subject});

  @override
  State<_DescriptionSection> createState() => _DescriptionSectionState();
}

enum _DescriptionEditView { raw, linked, preview }

class _LinkHit {
  final TextRange range;
  final String linkText;
  final String linkTarget;

  const _LinkHit({required this.range, required this.linkText, required this.linkTarget});
}

class _DescriptionSectionState extends State<_DescriptionSection> {
  _DescriptionEditView _viewMode = _DescriptionEditView.raw;
  late final _LinkedTextController _linkController;
  bool _syncingControllers = false;

  @override
  void initState() {
    super.initState();
    _linkController = _LinkedTextController();
    _linkController.value = widget.controller.value;
    widget.controller.addListener(_syncFromRawController);
    _linkController.addListener(_syncFromLinkController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromRawController);
    _linkController.removeListener(_syncFromLinkController);
    _linkController.dispose();
    super.dispose();
  }

  void _syncFromRawController() {
    if (_syncingControllers) return;
    _syncingControllers = true;
    if (_linkController.value != widget.controller.value) {
      _linkController.value = widget.controller.value;
    }
    _syncingControllers = false;
  }

  void _syncFromLinkController() {
    if (_syncingControllers) return;
    _syncingControllers = true;
    if (widget.controller.value != _linkController.value) {
      widget.controller.value = _linkController.value;
    }
    _syncingControllers = false;
  }

  TextEditingController get _activeController => _viewMode == _DescriptionEditView.linked ? _linkController : widget.controller;

  TextRange? _wordRangeAtCursor(String text, int cursorOffset) {
    if (cursorOffset < 0 || cursorOffset > text.length) return null;
    final wordRegex = RegExp(r'[A-Za-z0-9_]+');
    for (final match in wordRegex.allMatches(text)) {
      if (cursorOffset >= match.start && cursorOffset <= match.end) {
        return TextRange(start: match.start, end: match.end);
      }
    }
    return null;
  }

  Future<void> _autoLinkDescription() async {
    final normalizedSubject = widget.subject.trim();
    if (normalizedSubject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a subject before auto-linking.')));
      return;
    }

    final currentText = _activeController.text;
    final entries = await dictionaryRepository.fetchEntries(subject: normalizedSubject);
    final aliasIndex = await dictionaryRepository.fetchAliasIndex();
    if (!mounted) return;

    final titleIndex = dictionaryRepository.buildTitleAliasIndex(entries, aliasIndex);
    final updated = linkifyDictionaryEntriesForSubject(data: currentText, entriesByTitle: titleIndex, subject: normalizedSubject);

    if (updated == currentText) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No new links added for this subject.')));
      return;
    }

    _activeController.text = updated;
  }

  Future<void> _linkSelectionToEntry({TextRange? overrideRange, String? overrideText}) async {
    final normalizedSubject = widget.subject.trim();
    if (normalizedSubject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a subject before linking.')));
      return;
    }

    final activeController = _activeController;
    final selection = activeController.selection;
    final text = activeController.text;
    TextRange? targetRange = overrideRange;
    if (targetRange == null) {
      if (selection.isValid && !selection.isCollapsed) {
        targetRange = TextRange(start: selection.start, end: selection.end);
      } else if (selection.isValid && selection.isCollapsed) {
        targetRange = _wordRangeAtCursor(text, selection.baseOffset);
      }
    }

    if (targetRange == null || targetRange.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a word to link.')));
      return;
    }

    final selectedText = overrideText ?? text.substring(targetRange.start, targetRange.end);
    final selectedEntry = await showModalBottomSheet<DictionaryEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _DictionaryPickerSheet(
        entriesFuture: dictionaryRepository.fetchEntries(subject: normalizedSubject),
        onSelect: (entry) => Navigator.of(ctx).pop(entry),
      ),
    );

    if (!mounted || selectedEntry == null) return;

    final link = '[$selectedText](${selectedEntry.subject}:${selectedEntry.questId})';
    final updated = text.replaceRange(targetRange.start, targetRange.end, link);
    activeController.value = activeController.value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: targetRange.start + link.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _editLinkAtRange({required TextRange range, required String linkText, required String linkTarget}) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text('Linked to $linkTarget'), subtitle: const Text('Choose an action')),
              ListTile(leading: const Icon(Icons.link_rounded), title: const Text('Change link'), onTap: () => Navigator.of(ctx).pop('change')),
              ListTile(leading: const Icon(Icons.link_off_rounded), title: const Text('Remove link'), onTap: () => Navigator.of(ctx).pop('remove')),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || result == null) return;
    final controller = _linkController;
    final text = controller.text;
    if (result == 'remove') {
      final updated = text.replaceRange(range.start, range.end, linkText);
      controller.value = controller.value.copyWith(
        text: updated,
        selection: TextSelection.collapsed(offset: range.start + linkText.length),
        composing: TextRange.empty,
      );
      return;
    }
    if (result == 'change') {
      await _linkSelectionToEntry(overrideRange: range, overrideText: linkText);
    }
  }

  _LinkHit? _linkAtOffset(String text, int offset) {
    final linkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    for (final match in linkRegex.allMatches(text)) {
      final linkText = match.group(1) ?? '';
      final linkTarget = match.group(2) ?? '';
      final linkTextStart = match.start + 1;
      final linkTextEnd = linkTextStart + linkText.length;
      if (offset >= linkTextStart && offset <= linkTextEnd) {
        return _LinkHit(
          range: TextRange(start: match.start, end: match.end),
          linkText: linkText,
          linkTarget: linkTarget,
        );
      }
    }
    return null;
  }

  Future<void> _handleLinkedEditorTap() async {
    await Future<void>.delayed(Duration.zero);
    final selection = _linkController.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final hit = _linkAtOffset(_linkController.text, selection.baseOffset);
    if (hit == null) return;
    await _editLinkAtRange(range: hit.range, linkText: hit.linkText, linkTarget: hit.linkTarget);
  }
  
  Widget _buildLinkedEditor() {
    return TextField(
      controller: _linkController,
      onTap: _handleLinkedEditorTap,
      style: TextStyle(color: widget.colorScheme.onSurface, fontSize: 15, height: 1.6),
      maxLines: null,
      minLines: 3,
      decoration: _editInputDecoration(context, widget.colorScheme, hint: 'Quest description…'),
    );
  }

  Widget _buildPreview() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([dictionaryRepository.fetchEntries(), dictionaryRepository.fetchAliasIndex()]),
      builder: (context, snapshot) {
        final entries = snapshot.data != null ? snapshot.data![0] as List<DictionaryEntry> : const <DictionaryEntry>[];
        final aliasIndex = snapshot.data != null ? snapshot.data![1] as Map<String, int> : const <String, int>{};
        if (entries.isEmpty) {
          return MarkdownBody(
            data: _activeController.text,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(code: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          );
        }

        return DictionaryMarkdownBody(
          data: _activeController.text,
          entries: entries,
          titleIndex: dictionaryRepository.buildTitleAliasIndex(entries, aliasIndex),
          linkColor: widget.colorScheme.primary,
          onTapEntry: (entry) => showDictionaryEntryPreviewSheet(
            context,
            entry: entry,
            onOpenQuest: () => context.go(entry.questRoute),
            onOpenDictionary: () => context.go(entry.route),
          ),
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(code: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const viewChoices = <_DescriptionEditView>[_DescriptionEditView.raw, _DescriptionEditView.linked, _DescriptionEditView.preview];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionLabel(label: 'Description', colorScheme: widget.colorScheme),
              ),
              if (widget.editMode)
                ToggleButtons(
                  isSelected: viewChoices.map((v) => v == _viewMode).toList(),
                  onPressed: (index) => setState(() => _viewMode = viewChoices[index]),
                  borderRadius: BorderRadius.circular(999),
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 70),
                  children: const [Text('Raw'), Text('Links'), Text('Preview')],
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.editMode)
            Row(
              children: [
                TextButton.icon(onPressed: () => _linkSelectionToEntry(), icon: const Icon(Icons.link_rounded, size: 18), label: const Text('Link word')),
                TextButton.icon(onPressed: _autoLinkDescription, icon: const Icon(Icons.auto_fix_high_rounded, size: 18), label: const Text('Auto-link')),
              ],
            ),
          if (widget.editMode) const SizedBox(height: 6),
          if (widget.editMode)
            Builder(
              builder: (context) {
                if (_viewMode == _DescriptionEditView.raw) {
                  return TextField(
                    controller: widget.controller,
                    style: TextStyle(color: widget.colorScheme.onSurface, fontSize: 15, height: 1.6),
                    maxLines: null,
                    minLines: 3,
                    decoration: _editInputDecoration(context, widget.colorScheme, hint: 'Quest description…'),
                  );
                }
                if (_viewMode == _DescriptionEditView.linked) {
                  return _buildLinkedEditor();
                }
                return _buildPreview();
              },
            )
          else
            FutureBuilder<List<dynamic>>(
              future: Future.wait([dictionaryRepository.fetchEntries(), dictionaryRepository.fetchAliasIndex()]),
              builder: (context, snapshot) {
                final entries = snapshot.data != null ? snapshot.data![0] as List<DictionaryEntry> : const <DictionaryEntry>[];
                final aliasIndex = snapshot.data != null ? snapshot.data![1] as Map<String, int> : const <String, int>{};
                if (entries.isEmpty) {
                  return MarkdownBody(
                    data: widget.description,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(code: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  );
                }

                return DictionaryMarkdownBody(
                  data: widget.description,
                  entries: entries,
                  titleIndex: dictionaryRepository.buildTitleAliasIndex(entries, aliasIndex),
                  linkColor: widget.colorScheme.primary,
                  onTapEntry: (entry) => showDictionaryEntryPreviewSheet(
                    context,
                    entry: entry,
                    onOpenQuest: () => context.go(entry.questRoute),
                    onOpenDictionary: () => context.go(entry.route),
                  ),
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(code: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                );
              },
            ),
          //Text(description, style: TextStyle(color: colorScheme.onSurface, fontSize: 15, height: 1.6)),
        ],
      ),
    );
  }
}

class _DictionaryPickerSheet extends StatefulWidget {
  final Future<List<DictionaryEntry>> entriesFuture;
  final void Function(DictionaryEntry entry) onSelect;

  const _DictionaryPickerSheet({required this.entriesFuture, required this.onSelect});

  @override
  State<_DictionaryPickerSheet> createState() => _DictionaryPickerSheetState();
}

class _DictionaryPickerSheetState extends State<_DictionaryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedSubject;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text.trim()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search dictionary…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.primary, width: 1.4)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<DictionaryEntry>>(
                    future: widget.entriesFuture,
                    builder: (context, snapshot) {
                      final entries = snapshot.data ?? const <DictionaryEntry>[];
                      final subjects = <String>{for (final entry in entries) if (entry.subject.trim().isNotEmpty) entry.subject}.toList()
                        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                      if (_selectedSubject != null && !subjects.contains(_selectedSubject)) {
                        _selectedSubject = null;
                      }

                      return DropdownButtonFormField<String?>(
                        initialValue: _selectedSubject,
                        decoration: InputDecoration(
                          labelText: 'Subject',
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All subjects')),
                          ...subjects.map((subject) => DropdownMenuItem<String?>(value: subject, child: Text(subject))),
                        ],
                        onChanged: (value) => setState(() => _selectedSubject = value),
                      );
                    },
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<DictionaryEntry>>(
                future: widget.entriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final entries = snapshot.data ?? const <DictionaryEntry>[];
                  final filtered = entries.where((entry) {
                    if (_selectedSubject != null && entry.subject != _selectedSubject) return false;
                    if (_searchQuery.isEmpty) return true;
                    final haystack = '${entry.title}\n${entry.subject}\n${entry.description}'.toLowerCase();
                    return haystack.contains(_searchQuery.toLowerCase());
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        entries.isEmpty ? 'No dictionary entries found' : 'No entries match your filter',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      return ListTile(
                        onTap: () => widget.onSelect(entry),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        tileColor: cs.surfaceContainerLow,
                        title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(entry.previewSummary, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.send_rounded),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Meta / Details ────────────────────────────────────────────────────────────

class _MetaSection extends StatelessWidget {
  final Quest quest;
  final ColorScheme colorScheme;
  final TextEditingController posXCtrl;
  final TextEditingController posYCtrl;
  final TextEditingController sizeXCtrl;
  final TextEditingController sizeYCtrl;

  const _MetaSection({
    required this.quest,
    required this.colorScheme,
    required this.posXCtrl,
    required this.posYCtrl,
    required this.sizeXCtrl,
    required this.sizeYCtrl,
  });

  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(20), child: _buildEditLayout());
  }

  Widget _buildEditLayout() {
    return Column(
      children: [
        _MetaReadOnlyRow(icon: Icons.tag_rounded, label: 'Quest ID', value: '#${quest.id}', colorScheme: colorScheme),
        const SizedBox(height: 12),
        _MetaReadOnlyRow(icon: Icons.tag_rounded, label: 'Subject', value: quest.subject, colorScheme: colorScheme),
        const SizedBox(height: 12),
        _MetaCoordRow(
          icon: Icons.place_outlined,
          label: 'Position',
          firstLabel: 'X',
          secondLabel: 'Y',
          firstCtrl: posXCtrl,
          secondCtrl: posYCtrl,
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 12),
        _MetaCoordRow(
          icon: Icons.aspect_ratio_rounded,
          label: 'Size',
          firstLabel: 'W',
          secondLabel: 'H',
          firstCtrl: sizeXCtrl,
          secondCtrl: sizeYCtrl,
          colorScheme: colorScheme,
        ),
      ],
    );
  }
}

class _LinkedTextController extends TextEditingController {
  _LinkedTextController();

  String _mask(String value) => List.filled(value.length, String.fromCharCode(0x200B)).join();

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final textValue = text;
    final linkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    final spans = <InlineSpan>[];
    var cursor = 0;
    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );

    for (final match in linkRegex.allMatches(textValue)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: textValue.substring(cursor, match.start), style: style));
      }
      final linkText = match.group(1) ?? '';
      final linkTarget = match.group(2) ?? '';

      spans.add(TextSpan(text: _mask('['), style: style));
      spans.add(TextSpan(text: linkText, style: linkStyle ?? style));
      spans.add(TextSpan(text: _mask(']('), style: style));
      spans.add(TextSpan(text: _mask(linkTarget), style: style));
      spans.add(TextSpan(text: _mask(')'), style: style));
      cursor = match.end;
    }

    if (cursor < textValue.length) {
      spans.add(TextSpan(text: textValue.substring(cursor), style: style));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: textValue, style: style));
    }

    return TextSpan(style: style, children: spans);
  }
}



class _MetaReadOnlyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _MetaReadOnlyRow({required this.icon, required this.label, required this.value, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(context.uiRadiusSm),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                ),
                Text(
                  value,
                  style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.45), fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline_rounded, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}

class _MetaCoordRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String firstLabel;
  final String secondLabel;
  final TextEditingController firstCtrl;
  final TextEditingController secondCtrl;
  final ColorScheme colorScheme;

  const _MetaCoordRow({
    required this.icon,
    required this.label,
    required this.firstLabel,
    required this.secondLabel,
    required this.firstCtrl,
    required this.secondCtrl,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Icon(icon, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.5),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _NumericField(prefixLabel: firstLabel, controller: firstCtrl, colorScheme: colorScheme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumericField(prefixLabel: secondLabel, controller: secondCtrl, colorScheme: colorScheme),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumericField extends StatelessWidget {
  final String prefixLabel;
  final TextEditingController controller;
  final ColorScheme colorScheme;

  const _NumericField({required this.prefixLabel, required this.controller, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      style: TextStyle(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w700),
      decoration: _editInputDecoration(context, colorScheme).copyWith(
        prefixText: '$prefixLabel  ',
        prefixStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final ColorScheme colorScheme;
  final VoidCallback onSave;

  const _SaveButton({required this.colorScheme, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onSave,
        icon: const Icon(Icons.save_rounded),
        label: const Text('Save Changes'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uiRadiusMd)),
        ),
      ),
    );
  }
}

///delete quest button
class _DeleteButton extends StatelessWidget {
  final ColorScheme colorScheme;
  final VoidCallback onDelete;

  const _DeleteButton({required this.colorScheme, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline_rounded),
        label: const Text('Delete Quest'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uiRadiusMd)),
          side: BorderSide(color: colorScheme.error, width: 1.5),
          foregroundColor: colorScheme.error,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;

  const _SectionLabel({required this.label, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(color: colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4),
    );
  }
}

InputDecoration _editInputDecoration(BuildContext context, ColorScheme cs, {String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.45)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    filled: true,
    fillColor: cs.surfaceContainerHighest,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(context.uiRadiusSm),
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(context.uiRadiusSm),
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(context.uiRadiusSm),
      borderSide: BorderSide(color: cs.primary, width: 1.5),
    ),
  );
}
