import 'package:flutter/material.dart';
import 'package:lumox/logic/quests/quest_change_manager.dart';

import '../../theme/theme_ui_values.dart';


class QuestChangeScreen extends StatelessWidget {
  final QuestChangeManager changeManager;

  const QuestChangeScreen({super.key, required this.changeManager});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: changeManager,
      builder: (context, _) {
        final pending = changeManager.pendingChanges;
        final skipped = changeManager.skippedChanges;
        final undone = changeManager.redoChanges;

        final conflictedPending = changeManager.allConflictedPending;
        final conflictedSkipped = changeManager.allConflictedSkipped;
        final hasConflicts = conflictedPending.isNotEmpty || conflictedSkipped.isNotEmpty;

        final isEmpty = pending.isEmpty && skipped.isEmpty && undone.isEmpty;

        void showDetails(QuestChange change, _TileState state, DateTime? ts, String? conflict) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => _ChangeDetailsSheet(change: change, state: state, timestamp: ts, conflictReason: conflict, changeManager: changeManager),
          );
        }

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          appBar: AppBar(
            title: Text(pending.isEmpty ? 'Change History' : '${pending.length} Pending'),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
            actions: [
              IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo), onPressed: changeManager.canUndo ? changeManager.undo : null),
              IconButton(tooltip: 'Redo', icon: const Icon(Icons.redo), onPressed: changeManager.canRedo ? changeManager.redo : null),
            ],
          ),
          body: Column(
            children: [
              if (hasConflicts) _ConflictBanner(conflictCount: conflictedPending.length),
              Expanded(
                child: isEmpty
                    ? const _EmptyState()
                    : CustomScrollView(
                        slivers: [
                          if (pending.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                              child: _SectionHeader(label: 'Pending Queue', icon: Icons.pending_actions),
                            ),
                            SliverReorderableList(
                              itemCount: pending.length,
                              onReorder: changeManager.reorderPending,
                              itemBuilder: (context, index) {
                                final change = pending[index];
                                final ts = changeManager.recordedAt(change);
                                final isConflicted = conflictedPending.contains(change);
                                final state = isConflicted ? _TileState.conflict : _TileState.active;

                                return ReorderableDragStartListener(
                                  key: ObjectKey(change),
                                  index: index,
                                  child: _ChangeTimelineTile(
                                    change: change,
                                    timestamp: ts,
                                    state: state,
                                    isFirst: index == 0,
                                    isLast: index == pending.length - 1 && undone.isEmpty && skipped.isEmpty,
                                    conflictReason: isConflicted ? _getConflictReason(change, skipped) : null,
                                    onTap: () => showDetails(change, state, ts, isConflicted ? _getConflictReason(change, skipped) : null),
                                    onToggle: () => changeManager.skipChange(change),
                                  ),
                                );
                              },
                            ),
                          ],
                          if (undone.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                              child: _SectionHeader(label: 'Recently Undone', icon: Icons.history),
                            ),
                            SliverList.builder(
                              itemCount: undone.length,
                              itemBuilder: (context, index) {
                                final change = undone[undone.length - 1 - index];
                                final ts = changeManager.recordedAt(change);
                                return _ChangeTimelineTile(
                                  key: ObjectKey(change),
                                  change: change,
                                  timestamp: ts,
                                  state: _TileState.undone,
                                  isFirst: index == 0 && pending.isEmpty,
                                  isLast: index == undone.length - 1 && skipped.isEmpty,
                                  onTap: () => showDetails(change, _TileState.undone, ts, null),
                                  onToggle: null,
                                );
                              },
                            ),
                          ],
                          if (skipped.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                              child: _SectionHeader(label: 'Skipped Changes', icon: Icons.visibility_off_outlined),
                            ),
                            SliverList.builder(
                              itemCount: skipped.length,
                              itemBuilder: (context, index) {
                                final change = skipped[index];
                                final ts = changeManager.recordedAt(change);
                                final isConflicted = conflictedSkipped.contains(change);
                                final state = isConflicted ? _TileState.conflictSkipped : _TileState.skipped;

                                return _ChangeTimelineTile(
                                  key: ObjectKey(change),
                                  change: change,
                                  timestamp: ts,
                                  state: state,
                                  isFirst: index == 0 && pending.isEmpty && undone.isEmpty,
                                  isLast: index == skipped.length - 1,
                                  conflictReason: isConflicted ? _getConflictCause(change, changeManager.conflictsOf(change)) : null,
                                  onTap: () => showDetails(change, state, ts, null),
                                  onToggle: () => changeManager.unskipChange(change),
                                );
                              },
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 100)),
                        ],
                      ),
              ),
              _buildBottomBar(context, pending, hasConflicts),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context, List<QuestChange> pending, bool hasConflicts) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: hasConflicts ? Theme.of(context).colorScheme.error : null),
        onPressed: pending.isNotEmpty && !hasConflicts ? changeManager.push : null,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: Text(hasConflicts ? 'Resolve Conflicts' : 'Push Changes'),
      ),
    );
  }

  static String _getConflictReason(QuestChange change, List<QuestChange> skippedChanges) {
    for (final skipped in skippedChanges) {
      if (skipped is AddQuestChange) {
        final id = change.affectedQuestIds?.firstWhere((id) => id == skipped.quest.id, orElse: () => -1);
        if (id != null && id == skipped.quest.id) return 'Depends on "${skipped.updateMessage}" (skipped).';
      }
      if (skipped is AddConnectionChange && change is RemoveConnectionChange && change.fromId == skipped.fromId && change.toId == skipped.toId) {
        return 'Connection was skipped – cannot remove.';
      }
    }
    return 'Missing dependency.';
  }

  static String _getConflictCause(QuestChange skipped, List<QuestChange> conflicts) {
    if (conflicts.isEmpty) return '';
    return '${conflicts.length} dependent change(s) blocked.';
  }
}

class _ChangeTimelineTile extends StatelessWidget {
  final QuestChange change;
  final DateTime? timestamp;
  final _TileState state;
  final bool isFirst;
  final bool isLast;
  final String? conflictReason;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  const _ChangeTimelineTile({
    super.key,
    required this.change,
    required this.timestamp,
    required this.state,
    required this.isFirst,
    required this.isLast,
    this.conflictReason,
    required this.onTap,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDimmed = state == _TileState.skipped || state == _TileState.undone;
    final isError = state == _TileState.conflict || state == _TileState.conflictSkipped;
    final color = isError
        ? cs.error
        : isDimmed
        ? cs.outline
        : cs.primary;

    return Material(
      //to prevent a 'no material widget found' error when this is used inside a ReorderableList
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(
              children: [
                SizedBox(
                  width: 45,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      timestamp != null ? "${timestamp!.hour}:${timestamp!.minute.toString().padLeft(2, '0')}" : "--:--",
                      style: theme.textTheme.labelSmall?.copyWith(color: isDimmed ? cs.outline : cs.onSurfaceVariant, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Expanded(child: Container(width: 2, color: isFirst ? Colors.transparent : color.withValues(alpha: 0.3))),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(color: cs.surface, width: 2),
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(width: 2, color: isLast ? Colors.transparent : color.withValues(alpha: 0.3)),
                            if (isLast) Positioned(top: -4, left: -7, child: Icon(Icons.arrow_downward_rounded, size: 16, color: color.withValues(alpha: 0.7))),
                          ],
                        ),
                      ), //display an arrow if it's the last item to indicate the current state, otherwise fade out
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isError ? cs.errorContainer.withValues(alpha: 0.2) : cs.surface,
                        borderRadius: BorderRadius.circular(context.uiRadiusMd),
                        border: isError ? Border.all(color: cs.error.withValues(alpha: 0.5)) : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  change.updateMessage,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    decoration: isDimmed ? TextDecoration.lineThrough : null,
                                    color: isError ? cs.error : (isDimmed ? cs.outline : null),
                                  ),
                                ),
                                if (isError && conflictReason != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(conflictReason!, style: theme.textTheme.bodySmall?.copyWith(color: cs.error, fontSize: 10)),
                                  ),
                              ],
                            ),
                          ),
                          if (onToggle != null)
                            IconButton(
                              tooltip: state == _TileState.active ? 'Skip' : 'Include',
                              icon: Icon(
                                state == _TileState.active || state == _TileState.conflict ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              ),
                              onPressed: onToggle,
                              visualDensity: VisualDensity.compact,
                            ),
                          const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChangeDetailsSheet extends StatelessWidget {
  final QuestChange change;
  final _TileState state;
  final DateTime? timestamp;
  final String? conflictReason;
  final QuestChangeManager changeManager;

  const _ChangeDetailsSheet({required this.change, required this.state, this.timestamp, this.conflictReason, required this.changeManager});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(context.uiRadiusLg)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(context.uiRadiusSm)),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _getIconForChange(context, change, cs),
              const SizedBox(width: 12),
              Expanded(
                child: Text(change.updateMessage, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(context, Icons.access_time, "Recorded at", timestamp?.toLocal().toString().split('.')[0] ?? "Unknown"),
          _buildInfoRow(context, Icons.category_outlined, "Change Type", change.runtimeType.toString()),
          if (conflictReason != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(context.uiRadiusSm)),
              child: Row(
                children: [
                  Icon(Icons.warning, color: cs.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(conflictReason!, style: TextStyle(color: cs.onErrorContainer, fontSize: 12)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Text(
            "TECHNICAL DETAILS",
            style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildPrettyTechnicalData(context),
        ],
      ),
    );
  }

  Widget _buildPrettyTechnicalData(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (change is UpdateQuestChange) {
      final update = change as UpdateQuestChange;
      final patch = update.patch;
      final reversePatch = update.reversePatch;

      // Map of fields to display
      final Map<String, dynamic> fields = {
        "Name": patch.name,
        "Description": patch.description,
        "Subject": patch.subject,
        "Pos X": patch.posX,
        "Pos Y": patch.posY,
        "Difficulty": patch.difficulty,
        "Size X": patch.sizeX,
        "Size Y": patch.sizeY,
        "Completed": patch.isCompleted,
      };

      final Map<String, dynamic> reversedFields = {
        "Name": reversePatch.name,
        "Description": reversePatch.description,
        "Subject": reversePatch.subject,
        "Pos X": reversePatch.posX,
        "Pos Y": reversePatch.posY,
        "Difficulty": reversePatch.difficulty,
        "Size X": reversePatch.sizeX,
        "Size Y": reversePatch.sizeY,
        "Completed": reversePatch.isCompleted,
      };

      final Map<String, (dynamic oldValue, dynamic newValue)> activeFields = Map.fromEntries(
        fields.entries
            .where((e) {
              return e.value != null;
            })
            .map((e) => MapEntry(e.key, (reversedFields[e.key], e.value))),
      );

      final detailDiffRows = activeFields.entries.map((e) => _buildDetailDiffRow(context, e.key, e.value.$2.toString(), e.value.$1.toString())).toList();

      return Column(children: detailDiffRows);
    } else if(change is UpdateConnectionChange) {
      final update = change as UpdateConnectionChange;
      final patch = update.patch;
      final reversePatch = update.reversePatch;

      final Map<String, dynamic> fields = {
        "Type": patch.type,
        "XP Requirement": patch.xpRequirement,
      };

      final Map<String, dynamic> reversedFields = {
        "Type": reversePatch.type,
        "XP Requirement": reversePatch.xpRequirement,
      };

      final Map<String, (dynamic oldValue, dynamic newValue)> activeFields = Map.fromEntries(
        fields.entries
            .where((e) {
              return e.value != null;
            })
            .map((e) => MapEntry(e.key, (reversedFields[e.key], e.value))),
      );

      final detailDiffRows = activeFields.entries.map((e) => _buildDetailDiffRow(context, e.key, e.value.$2.toString(), e.value.$1.toString())).toList();

      return Column(children: detailDiffRows);
    }

    if (change is AddConnectionChange || change is RemoveConnectionChange) {
      final dynamic conn = change;
      return Column(children: [_buildDetailRow("Source ID", conn.fromId.toString()), _buildDetailRow("Target ID", conn.toId.toString())]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(context.uiRadiusSm)),
      child: Text(change.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
    );
  }

  Widget _buildDetailDiffRow(BuildContext context, String label, String oldValue, String newValue) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text("$label:", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  oldValue,
                  style: TextStyle(color: cs.outline, decoration: TextDecoration.lineThrough),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, size: 12)),
                Text(
                  newValue,
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Text(value),
        ],
      ),
    );
  }

  Widget _getIconForChange(BuildContext context, QuestChange change, ColorScheme cs) {
    IconData icon = Icons.edit_note;
    if (change is AddQuestChange) icon = Icons.add_circle_outline;
    if (change is DeleteQuestChange) icon = Icons.delete_outline;
    if (change is AddConnectionChange || change is RemoveConnectionChange) icon = Icons.link;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(context.uiRadiusSm)),
      child: Icon(icon, color: cs.onPrimaryContainer),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(val, style: const TextStyle(overflow: TextOverflow.ellipsis)),
          ),
        ],
      ),
    );
  }
}

enum _TileState { active, skipped, conflict, conflictSkipped, undone }

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.1),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(child: Text("Everything is up to date!"));
}

class _ConflictBanner extends StatelessWidget {
  final int conflictCount;

  const _ConflictBanner({required this.conflictCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.errorContainer,
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      child: Text(
        "⚠️ Resolve $conflictCount conflict(s) before pushing!",
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.bold),
      ),
    );
  }
}
