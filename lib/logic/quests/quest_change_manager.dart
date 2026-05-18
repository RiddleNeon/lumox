import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:lumox/logic/quests/quest.dart';
import 'package:lumox/logic/quests/quest_connection.dart';
import 'package:lumox/logic/quests/quest_system.dart';
import 'package:lumox/logic/repositories/quest_repository.dart';

/// Tracks quest changes locally with full undo/redo support.
/// Changes are applied to [QuestSystem] immediately when recorded.
/// Call [push] to sync all pending changes to the server as a single "commit",
/// collapsing redundant operations (e.g. multiple moves of the same quest)
/// before sending.
class QuestChangeManager with ChangeNotifier {
  final QuestSystem questSystem;
  final QuestRepository repo;
  final String subject;

  /// Changes that have been applied locally and will be pushed to the server.
  final List<QuestChange> _pendingChanges = [];

  /// Changes that have been locally undone by the user and excluded from push.
  /// Re-enabling one re-applies it locally and moves it back to [_pendingChanges].
  final List<QuestChange> _skippedChanges = [];

  /// Stack of applied changes available for global undo.
  final List<QuestChange> _undoStack = [];

  /// Stack of undone changes available for global redo.
  final List<QuestChange> _redoStack = [];

  bool _isPushing = false;

  List<QuestChange> _pushBatch = [];

  int _pushCompleted = 0;
  
  QuestChange? _currentPushChange;

  bool get hasPendingChanges => _pendingChanges.isNotEmpty;

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  int get pendingCount => _pendingChanges.length;

  bool get isPushing => _isPushing;

  List<QuestChange> get pushingChanges => List.unmodifiable(_pushBatch);

  int get pushTotalCount => _pushBatch.length;

  int get pushCompletedCount => _pushCompleted;

  int get pushRemainingCount => _pushBatch.length - _pushCompleted;

  double get pushProgress => _pushBatch.isEmpty ? 0 : _pushCompleted / _pushBatch.length;

  QuestChange? get currentPushChange => _currentPushChange;

  /// Stores the wall-clock time at which each change was recorded.
  /// Using an Expando avoids touching the QuestChange class hierarchy.
  final Expando<DateTime> _recordedAt = Expando();

  QuestChangeManager({required this.questSystem, required this.repo, required this.subject});

  /// Returns the timestamp at which [change] was originally recorded,
  /// or `null` for changes created before timestamp tracking was added.
  DateTime? recordedAt(QuestChange change) => _recordedAt[change];

  // ── Public read-only views ─────────────────────────────────────────────────

  List<QuestChange> get pendingChanges => List.unmodifiable(_pendingChanges);

  List<QuestChange> get skippedChanges => List.unmodifiable(_skippedChanges);

  /// Read-only view of the redo stack (globally undone, newest last).
  List<QuestChange> get redoChanges => List.unmodifiable(_redoStack);

  // ── Record / undo / redo ───────────────────────────────────────────────────

  /// Applies [change] locally and adds it to the pending queue.
  /// Clears the redo stack (new change invalidates undone history).
  ///
  /// Uses [applyLocally] (not [_applyAndRebase]) on purpose: the caller
  /// constructs the change via [UpdateQuestChange.fromDiff], which already
  /// captures the correct reversePatch from the real before-state.  If we
  /// called _applyAndRebase here and the caller pre-applied the change to the
  /// system (e.g. a drag that updates posX/posY live), we would read the
  /// already-updated state as "before" and overwrite reversePatch with the
  /// new position instead of the old one — breaking all subsequent undos and
  /// reorders for that change.
  void record(QuestChange change) {
    change.applyLocally(questSystem);
    _recordedAt[change] = DateTime.now();
    _pendingChanges.add(change);
    _undoStack.add(change);
    _redoStack.clear();
    notifyListeners();
  }

  /// Global undo: reverts the last applied change and moves it to the redo stack.
  void undo() {
    if (!canUndo) return;
    final change = _undoStack.removeLast();
    change.undoLocally(questSystem);
    _pendingChanges.remove(change);
    _skippedChanges.remove(change);
    _redoStack.add(change);
    notifyListeners();
  }

  /// Global redo: re-applies the last undone change.
  ///
  /// The reversePatch is rebased to the actual "before" state at the current
  /// tip of the sequence so that a subsequent undo restores the right values.
  void redo() {
    if (!canRedo) return;
    final change = _redoStack.removeLast();
    _applyAndRebase(change);
    _pendingChanges.add(change);
    _undoStack.add(change);
    notifyListeners();
  }

  // ── Per-change skip / unskip ───────────────────────────────────────────────

  /// Removes [change] from the pending queue and excludes it from the next push.
  ///
  /// Because later changes may have been applied on top of [change], we cannot
  /// simply call [QuestChange.undoLocally] in isolation – that would revert the
  /// world to the state *before* [change] while all subsequent changes are still
  /// "applied", leaving the local state inconsistent.
  ///
  /// Instead we:
  ///   1. Temporarily undo every pending change that comes *after* [change]
  ///      (in reverse application order).
  ///   2. Undo [change] itself.
  ///   3. Re-apply all the changes that were temporarily undone in step 1,
  ///      rebasing each reversePatch as we go.
  ///
  /// This guarantees the local [QuestSystem] reflects exactly the pending
  /// changes minus [change], regardless of its position in the queue.
  void skipChange(QuestChange change) {
    final idx = _pendingChanges.indexOf(change);
    if (idx == -1) return;

    // Step 1 – temporarily undo everything after [change] (newest first).
    final after = _pendingChanges.sublist(idx + 1);
    for (final c in after.reversed) {
      c.undoLocally(questSystem);
    }

    // Step 2 – undo [change] itself.
    change.undoLocally(questSystem);

    // Update bookkeeping.
    _pendingChanges.removeAt(idx);
    _undoStack.remove(change);
    _skippedChanges.add(change);

    // Step 3 – re-apply the later changes on top of the new base state,
    // rebasing each reversePatch so subsequent undos stay correct.
    for (final c in after) {
      _applyAndRebase(c);
    }

    notifyListeners();
  }

  /// Re-applies [change] locally and appends it to the end of the pending queue.
  ///
  /// The reversePatch is rebased to the actual "before" state at the current
  /// tip of the sequence.
  void unskipChange(QuestChange change) {
    if (!_skippedChanges.contains(change)) return;
    _applyAndRebase(change);
    _skippedChanges.remove(change);
    _pendingChanges.add(change);
    _undoStack.add(change);
    notifyListeners();
  }

  /// Moves a pending change from [oldIndex] to [newIndex] and keeps the local
  /// [QuestSystem] consistent.
  ///
  /// Two bugs are avoided here that would otherwise silently corrupt state:
  ///
  /// 1. **Wrong undo range**: when moving a change *up* (insertAt < oldIndex),
  ///    we must undo from `min(insertAt, oldIndex)`, not just from `oldIndex`.
  ///    If we only undo from `oldIndex`, the changes between `insertAt` and
  ///    `oldIndex-1` are never undone but ARE included in the replay range,
  ///    so they get applied twice — corrupting non-idempotent changes like
  ///    [AddQuestChange].
  ///
  /// 2. **Stale reversePatch**: [UpdateQuestChange.reversePatch] is set once
  ///    at record time. After a reorder, each change is replayed at a new
  ///    position in the sequence, so the actual "before" state differs from
  ///    what was captured originally. Without rebasing, a subsequent reorder
  ///    or undo applies the stale reversePatch, puts the quest in the wrong
  ///    intermediate state, and then replays later patches on top of garbage.
  ///    [_applyAndRebase] fixes this by capturing the real before-state and
  ///    updating reversePatch immediately after each replay step.
  void reorderPending(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _pendingChanges.length) return;
    if (newIndex < 0 || newIndex > _pendingChanges.length) return;

    // ReorderableListView passes newIndex *before* removal, so we adjust.
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (insertAt == oldIndex) return;

    final change = _pendingChanges[oldIndex];

    // Step 1 – undo all changes from the earliest affected index onward.
    //
    // BUG FIX: use min(insertAt, oldIndex), not just oldIndex.
    // When moving up, changes between insertAt and oldIndex-1 must also be
    // undone, otherwise they appear in the replay range but were never undone
    // and end up applied twice.
    final undoFrom = insertAt < oldIndex ? insertAt : oldIndex;
    final tail = _pendingChanges.sublist(undoFrom);
    for (final c in tail.reversed) {
      c.undoLocally(questSystem);
    }

    // Step 2 – rebuild _pendingChanges with [change] at its new position.
    _pendingChanges.removeAt(oldIndex);
    _pendingChanges.insert(insertAt, change);

    // Sync _undoStack order: remove affected items, re-add in new list order.
    for (final c in tail) {
      _undoStack.remove(c);
    }
    for (final c in _pendingChanges.sublist(undoFrom)) {
      if (tail.contains(c)) _undoStack.add(c);
    }

    // Step 3 – re-apply in new order from the earliest affected index.
    //
    // BUG FIX: use _applyAndRebase instead of applyLocally so that each
    // UpdateQuestChange has its reversePatch updated to the real "before"
    // state at its new position. Without this, the next reorder/undo would
    // read a stale reversePatch and restore the wrong field values.
    for (final c in _pendingChanges.sublist(undoFrom)) {
      _applyAndRebase(c);
    }

    notifyListeners();
  }

  // ── Conflict detection ─────────────────────────────────────────────────────

  /// Returns the pending changes that are broken because [skipped] was excluded.
  ///
  /// Conflicts arise when a pending change targets an entity that no longer
  /// exists because its originating change was skipped:
  /// - Skipping [AddQuestChange] for quest X → any Update/Delete for X is dangling.
  /// - Skipping [AddConnectionChange] for (from→to) → any Remove for (from→to)
  ///   is dangling.
  List<QuestChange> conflictsOf(QuestChange skipped) {
    return _pendingChanges.where((pending) {
      if (skipped is AddQuestChange) {
        for (var e in pending.affectedQuestIds?.whereType<int>() ?? []) {
          if (e == skipped.quest.id) return true;
        }
      }
      if (skipped is AddConnectionChange && pending is RemoveConnectionChange && pending.fromId == skipped.fromId && pending.toId == skipped.toId) {
        return true;
      }
      return false;
    }).toList();
  }

  Set<QuestChange> get allConflictedPending {
    final result = <QuestChange>{};

    for (final skipped in _skippedChanges) {
      result.addAll(conflictsOf(skipped));
    }

    final createdIdsInOrder = <int>{};
    for (final pending in _pendingChanges) {
      if (pending is AddQuestChange) {
        createdIdsInOrder.add(pending.questId);
      } else if (pending is _QuestTargetedChange) {
        final idsToVerify = [pending.questId, if (pending.otherQuestId != null) pending.otherQuestId!];

        for (final id in idsToVerify) {
          //final existsGlobally = questSystem.maybeGetQuestById(id) != null;
          final isCreatedLater = _pendingChanges.any(
            (c) => c is AddQuestChange && c.questId == id && _pendingChanges.indexOf(c) > _pendingChanges.indexOf(pending),
          );

          if (isCreatedLater) {
            result.add(pending);
          }
        }
      }
    }

    return result;
  }

  /// All skipped changes that cause at least one conflict in pending.
  Set<QuestChange> get allConflictedSkipped {
    return _skippedChanges.where((s) => conflictsOf(s).isNotEmpty).toSet();
  }

  // ── Push ──────────────────────────────────────────────────────────────────

  /// Collapses and pushes all pending changes to the server.
  /// Skipped changes are NOT pushed – their local effect has already been undone.
  ///
  /// Pending list and skipped list are cleared optimistically before network
  /// calls begin. If a push fails the caller is responsible for error handling.
  Future<void> push() async {
    if (_pendingChanges.isEmpty || _isPushing) return;

    final batch = List<QuestChange>.from(_pendingChanges);
    final collapsed = _collapse(batch);
    _pendingChanges.clear();
    _undoStack.clear();
    _redoStack.clear();

    _isPushing = true;
    _pushBatch = collapsed;
    _pushCompleted = 0;
    _currentPushChange = null;

    notifyListeners();

    try {
      for (var i = 0; i < collapsed.length; i++) {
        final change = collapsed[i];
        _currentPushChange = change;
        notifyListeners();

        await change.push(repo, questSystem);

        _pushCompleted = i + 1;
        notifyListeners();
      }
    } catch (_) {
      final remaining = collapsed.sublist(_pushCompleted);
      if (remaining.isNotEmpty) {
        _pendingChanges.addAll(remaining);
        _undoStack.addAll(remaining);
      }
      rethrow;
    } finally {
      _isPushing = false;
      _pushBatch = [];
      _pushCompleted = 0;
      _currentPushChange = null;
      notifyListeners();
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  /// Applies [c] locally and — for [UpdateQuestChange] — immediately rebases
  /// [reversePatch] to the actual quest state seen just before application.
  ///
  /// This keeps reversePatch in sync with the change's current position in the
  /// sequence. Without this rebase, any reorder or undo that happens *after*
  /// the first reorder would read a stale reversePatch, restore the wrong
  /// field values as the intermediate state, and then replay subsequent patches
  /// on top of that garbage state — causing patches to appear "not applied".
  void _applyAndRebase(QuestChange c) {
    if (c is UpdateQuestChange) {
      final before = questSystem.maybeGetQuestById(c.questId);
      c.applyLocally(questSystem);
      if (before != null) {
        c.reversePatch = c.patch.reverse(before);
      }
    } else {
      c.applyLocally(questSystem);
    }
  }

  List<QuestChange> _collapse(List<QuestChange> changes) {
    final Map<String, QuestChange> map = {};
    for (final c in changes) {
      final existing = map[c.collapseKey];
      if (existing == null) {
        map[c.collapseKey] = c;
      } else {
        final merged = existing.mergeWith(c);
        if (merged == null) {
          map.remove(c.collapseKey);
        } else {
          map[c.collapseKey] = merged;
        }
      }
    }
    return map.values.toList();
  }

  void dropStaleChanges() {
    _pendingChanges.removeWhere((c) => c.affectedQuestIds != null && !(c.affectedQuestIds?.any((id) => questSystem.maybeGetQuestById(id) != null) ?? true));
    notifyListeners();
  }
}

// ── Patch ──────────────────────────────────────────────────────────────────

/// A sparse set of quest field values. Only non-null fields are applied.
///
/// This is intentionally separate from [Quest] so that an [UpdateQuestChange]
/// can express "only the position changed" without carrying stale snapshots of
/// every other field.
class QuestPatch {
  final String? name;
  final String? description;
  final String? subject;
  final double? posX;
  final double? posY;
  final double? difficulty;
  final double? sizeX;
  final double? sizeY;
  final bool? isCompleted;
  final Color? color;

  const QuestPatch({this.name, this.description, this.subject, this.posX, this.posY, this.difficulty, this.sizeX, this.sizeY, this.isCompleted, this.color});

  /// Creates a patch from two quest snapshots, keeping only fields that differ.
  factory QuestPatch.diff(Quest before, Quest after) {
    assert(before.id == after.id, 'Diff requires the same quest ID');
    return QuestPatch(
      name: after.name != before.name ? after.name : null,
      description: after.description != before.description ? after.description : null,
      subject: after.subject != before.subject ? after.subject : null,
      posX: after.posX != before.posX ? after.posX : null,
      posY: after.posY != before.posY ? after.posY : null,
      difficulty: after.difficulty != before.difficulty ? after.difficulty : null,
      sizeX: after.sizeX != before.sizeX ? after.sizeX : null,
      sizeY: after.sizeY != before.sizeY ? after.sizeY : null,
      isCompleted: after.isCompleted != before.isCompleted ? after.isCompleted : null,
      color: after.color != before.color ? after.color : null,
    );
  }

  factory QuestPatch.fromQuest(Quest quest) {
    return QuestPatch(
      name: quest.name,
      description: quest.description,
      subject: quest.subject,
      posX: quest.posX,
      posY: quest.posY,
      difficulty: quest.difficulty,
      sizeX: quest.sizeX,
      sizeY: quest.sizeY,
      isCompleted: quest.isCompleted,
      color: quest.color,
    );
  }

  /// Creates a reverse patch that restores every field touched by [this]
  /// to its value in [before].
  QuestPatch reverse(Quest before) {
    return QuestPatch(
      name: name != null ? before.name : null,
      description: description != null ? before.description : null,
      subject: subject != null ? before.subject : null,
      posX: posX != null ? before.posX : null,
      posY: posY != null ? before.posY : null,
      difficulty: difficulty != null ? before.difficulty : null,
      sizeX: sizeX != null ? before.sizeX : null,
      sizeY: sizeY != null ? before.sizeY : null,
      isCompleted: isCompleted != null ? before.isCompleted : null,
      color: color == null ? null : before.color,
    );
  }

  /// Returns a new patch with all fields from [this], overridden by any
  /// non-null fields in [newer]. Used when collapsing two updates for the
  /// same quest into one.
  QuestPatch mergedWith(QuestPatch newer) {
    return QuestPatch(
      name: newer.name ?? name,
      description: newer.description ?? description,
      subject: newer.subject ?? subject,
      posX: newer.posX ?? posX,
      posY: newer.posY ?? posY,
      difficulty: newer.difficulty ?? difficulty,
      sizeX: newer.sizeX ?? sizeX,
      sizeY: newer.sizeY ?? sizeY,
      isCompleted: newer.isCompleted ?? isCompleted,
      color: newer.color ?? color,
    );
  }

  /// Applies only the non-null fields of this patch to [quest].
  Quest applyTo(Quest quest) => quest.copyWith(
    name: name,
    description: description,
    subject: subject,
    posX: posX,
    posY: posY,
    difficulty: difficulty,
    sizeX: sizeX,
    sizeY: sizeY,
    isCompleted: isCompleted,
    color: color,
  );

  bool get isEmpty =>
      name == null &&
      description == null &&
      subject == null &&
      posX == null &&
      posY == null &&
      difficulty == null &&
      sizeX == null &&
      sizeY == null &&
      isCompleted == null &&
      color == null;

  /// Serialises only the non-null fields for Supabase.
  ///
  /// [isCompleted] is intentionally excluded – it is client-only state and
  /// has no column in quest_versions.
  Map<String, dynamic> toSupabaseMap({required int questId, required String updateMessage, required String createdBy}) {
    return {
      'quest_id': questId,
      'created_by': createdBy,
      'update_message': updateMessage,
      if (name != null) 'title': name,
      if (description != null) 'description': description,
      if (subject != null) 'subject': subject,
      if (difficulty != null) 'difficulty': difficulty,
      if (posX != null) 'pos_x': posX!.toInt(),
      if (posY != null) 'pos_y': posY!.toInt(),
      if (sizeX != null) 'size_x': sizeX!.toInt(),
      if (sizeY != null) 'size_y': sizeY!.toInt(),
      if (color != null) 'color': color!.toARGB32(),
    };
  }

  String generateChangeMessage() {
    final parts = <String>[];

    if (name != null) parts.add('renamed to "$name"');
    if (description != null) parts.add('updated description');
    if (subject != null) parts.add('changed subject to "$subject"');
    if (difficulty != null) parts.add('changed difficulty to ${(difficulty! * 100).round()}%');
    if (color != null) parts.add('changed color to ${_colorLabel(color!)}');
    if (isCompleted != null) parts.add(isCompleted! ? 'marked as completed' : 'marked as incomplete');

    if (posX != null || posY != null) {
      final x = posX?.toInt() ?? '?';
      final y = posY?.toInt() ?? '?';
      parts.add('moved to ($x, $y)');
    }

    if (sizeX != null || sizeY != null) {
      final w = sizeX?.toInt() ?? '?';
      final h = sizeY?.toInt() ?? '?';
      parts.add('resized to ${w}x$h');
    }

    if (parts.isEmpty) return 'updated quest';
    return parts.join(', ');
  }
  
  static String _colorLabel(Color color) {
    final argb = color.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;

    const namedColors = <int, String>{
      0xFFF44336: 'red',
      0xFFE91E63: 'pink',
      0xFF9C27B0: 'purple',
      0xFF673AB7: 'deep purple',
      0xFF3F51B5: 'indigo',
      0xFF2196F3: 'blue',
      0xFF03A9F4: 'light blue',
      0xFF00BCD4: 'cyan',
      0xFF009688: 'teal',
      0xFF4CAF50: 'green',
      0xFF8BC34A: 'light green',
      0xFFCDDC39: 'lime',
      0xFFFFEB3B: 'yellow',
      0xFFFFC107: 'amber',
      0xFFFF9800: 'orange',
      0xFFFF5722: 'deep orange',
      0xFF795548: 'brown',
      0xFF9E9E9E: 'grey',
      0xFF607D8B: 'blue grey',
      0xFF000000: 'black',
      0xFFFFFFFF: 'white',
      0xFFFF00FF: 'magenta',
    };

    if (namedColors.containsKey(argb)) return namedColors[argb]!;

    String? closestName;
    double closestDist = double.infinity;
    for (final entry in namedColors.entries) {
      final nr = (entry.key >> 16) & 0xFF;
      final ng = (entry.key >> 8) & 0xFF;
      final nb = entry.key & 0xFF;
      final dist = ((r - nr) * (r - nr) + (g - ng) * (g - ng) + (b - nb) * (b - nb)).toDouble();
      if (dist < closestDist) {
        closestDist = dist;
        closestName = entry.value;
      }
    }

    if (closestName != null) return closestName;
    
    print("no closest named color for #${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}, closest is $closestName with distance $closestDist");

    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  @override
  String toString() =>
      'QuestPatch(name: $name, description: $description, subject: $subject, '
      'posX: $posX, posY: $posY, difficulty: $difficulty, '
      'sizeX: $sizeX, sizeY: $sizeY, isCompleted: $isCompleted, color: $color)';
}

class QuestConnectionPatch {
  final String? type;
  final double? xpRequirement;

  const QuestConnectionPatch({this.type, this.xpRequirement});

  /// Creates a patch from two quest snapshots, keeping only fields that differ.
  factory QuestConnectionPatch.diff(QuestConnection before, QuestConnection after) {
    assert(before.fromQuestId == after.fromQuestId && before.toQuestId == after.toQuestId, 'Diff requires the same quest ID');
    return QuestConnectionPatch(
      type: after.type != before.type ? after.type : null,
      xpRequirement: after.xpRequirement != before.xpRequirement ? after.xpRequirement : null,
    );
  }

  factory QuestConnectionPatch.fromQuest(QuestConnection connection) {
    return QuestConnectionPatch(type: connection.type, xpRequirement: connection.xpRequirement);
  }

  /// Creates a reverse patch that restores every field touched by [this]
  /// to its value in [before].
  QuestConnectionPatch reverse(QuestConnection before) {
    return QuestConnectionPatch(type: type != null ? before.type : null, xpRequirement: xpRequirement != null ? before.xpRequirement : null);
  }

  /// Returns a new patch with all fields from [this], overridden by any
  /// non-null fields in [newer]. Used when collapsing two updates for the
  /// same quest into one.
  QuestConnectionPatch mergedWith(QuestConnectionPatch newer) {
    return QuestConnectionPatch(type: newer.type ?? type, xpRequirement: newer.xpRequirement ?? xpRequirement);
  }

  /// Applies only the non-null fields of this patch to [quest].
  QuestConnection applyTo(QuestConnection connection) => connection.copyWith(type: type, xpRequirement: xpRequirement);

  bool get isEmpty => type == null && xpRequirement == null;

  /// Serialises only the non-null fields for Supabase.
  ///
  /// [isCompleted] is intentionally excluded – it is client-only state and
  /// has no column in quest_versions.
  Map<String, dynamic> toSupabaseMap({required int fromId, required int toId, required String updateMessage, required String createdBy}) {
    return {
      'from_id': fromId,
      'to_id': toId,
      'created_by': createdBy,
      'update_message': updateMessage,
      if (type != null) 'type': type,
      if (xpRequirement != null) 'xp_requirement': xpRequirement,
    };
  }

  @override
  String toString() => 'QuestConnectionPatch(type: $type, xp_requirement: $xpRequirement)';
}

// ── Base ───────────────────────────────────────────────────────────────────

abstract class QuestChange {
  final String updateMessage;

  const QuestChange({required this.updateMessage});

  String get collapseKey;

  void applyLocally(QuestSystem system);

  void undoLocally(QuestSystem system);

  /// [system] is provided so patch-based changes can resolve the current quest
  /// state when serialising for the server (no stale snapshots needed).
  Future<void> push(QuestRepository repo, QuestSystem system);

  /// The ID of the quest this change targets, or `null` for non-quest changes
  /// (e.g. connection-only changes). Used for conflict detection and stale-
  /// change cleanup from outside the library.
  List<int>? get affectedQuestIds => null;

  /// Merge [this] (older) with [newer] (same [collapseKey]).
  /// Returns the merged change, or `null` if they cancel out.
  QuestChange? mergeWith(QuestChange newer) => newer;
}

/// Marker for changes that target a specific quest by ID.
abstract class _QuestTargetedChange extends QuestChange {
  int get questId;

  int? get otherQuestId => null;

  const _QuestTargetedChange({required super.updateMessage});

  @override
  List<int>? get affectedQuestIds => [questId, ?otherQuestId];
}

// ── Quest changes ──────────────────────────────────────────────────────────

/// Records the creation of a new quest.
class AddQuestChange extends _QuestTargetedChange {
  final Quest quest;

  const AddQuestChange({required this.quest, super.updateMessage = 'added quest'});

  @override
  int get questId => quest.id;

  @override
  String get collapseKey => 'quest:${quest.id}';

  @override
  void applyLocally(QuestSystem s) => s.upsertQuest(quest);

  @override
  void undoLocally(QuestSystem s) => s.removeQuest(quest.id);

  @override
  Future<void> push(QuestRepository repo, QuestSystem system) => repo.addQuest(quest, updateMessage);

  @override
  QuestChange? mergeWith(QuestChange newer) {
    if (newer is DeleteQuestChange && newer.quest.id == quest.id) return null;
    if (newer is UpdateQuestChange && newer.questId == quest.id) {
      return AddQuestChange(quest: newer.patch.applyTo(quest), updateMessage: newer.updateMessage);
    }
    return newer;
  }
}

/// Records an edit to an existing quest.
///
/// Instead of storing full before/after snapshots, only the changed fields are
/// kept in [patch]. [applyLocally] and [undoLocally] read the **current** quest
/// state and surgically update only the relevant fields, so reordering changes
/// never accidentally restores a stale field value.
///
/// [reversePatch] is intentionally **mutable**: whenever this change is
/// replayed at a new position in the sequence (reorder, skip, redo),
/// [QuestChangeManager._applyAndRebase] captures the real quest state
/// immediately before application and writes it back to [reversePatch].
/// This keeps [undoLocally] correct regardless of how many reorders have
/// occurred since the change was first recorded.
class UpdateQuestChange extends _QuestTargetedChange {
  @override
  final int questId;

  /// The fields that changed — only non-null fields are written.
  final QuestPatch patch;

  /// The previous values for every field in [patch] — used for undo.
  ///
  /// Non-final so that [QuestChangeManager._applyAndRebase] can keep it in
  /// sync with the change's current position in the sequence.
  QuestPatch reversePatch;

  UpdateQuestChange({required this.questId, required this.patch, required this.reversePatch, super.updateMessage = 'updated quest'});

  /// Convenience constructor: computes [patch] and [reversePatch] automatically
  /// from two full quest snapshots.
  factory UpdateQuestChange.fromDiff({required Quest before, required Quest after, String updateMessage = 'updated quest'}) {
    final patch = QuestPatch.diff(before, after);
    return UpdateQuestChange(questId: after.id, patch: patch, reversePatch: patch.reverse(before), updateMessage: updateMessage);
  }

  @override
  String get collapseKey => 'quest:$questId';

  @override
  void applyLocally(QuestSystem s) {
    final current = s.maybeGetQuestById(questId);
    if (current == null) return;
    s.upsertQuest(patch.applyTo(current));
  }

  @override
  void undoLocally(QuestSystem s) {
    final current = s.maybeGetQuestById(questId);
    if (current == null) return;
    s.upsertQuest(reversePatch.applyTo(current));
  }

  /// Sends only the changed fields so the DB trigger merges them via COALESCE.
  @override
  Future<void> push(QuestRepository repo, QuestSystem system) => repo.patchQuest(questId, patch, updateMessage);

  @override
  QuestChange? mergeWith(QuestChange newer) {
    if (newer is UpdateQuestChange && newer.questId == questId) {
      return UpdateQuestChange(questId: questId, patch: patch.mergedWith(newer.patch), reversePatch: reversePatch, updateMessage: newer.updateMessage);
    }
    if (newer is DeleteQuestChange) return newer;
    return newer;
  }

  @override
  String toString() =>
      'UpdateQuestChange(questId: $questId, patch: $patch, '
      'reversePatch: $reversePatch, updateMessage: $updateMessage)';
}

class DeleteQuestChange extends _QuestTargetedChange {
  final Quest quest;

  const DeleteQuestChange({required this.quest, super.updateMessage = 'deleted quest'});

  @override
  int get questId => quest.id;

  @override
  String get collapseKey => 'quest:${quest.id}';

  @override
  void applyLocally(QuestSystem s) => s.removeQuest(quest.id);

  @override
  void undoLocally(QuestSystem s) => s.upsertQuest(quest);

  @override
  Future<void> push(QuestRepository repo, QuestSystem system) => repo.deleteQuest(quest);
}

// ── Connection changes ─────────────────────────────────────────────────────

class AddConnectionChange extends _QuestTargetedChange {
  final int fromId;
  final int toId;

  const AddConnectionChange({required this.fromId, required this.toId, super.updateMessage = 'connection added'});

  @override
  String get collapseKey => 'conn:${fromId}_$toId';

  @override
  void applyLocally(QuestSystem s) => s.addConnection(fromId, toId);

  @override
  void undoLocally(QuestSystem s) => s.removeConnection(fromId, toId);

  @override
  Future<void> push(QuestRepository repo, QuestSystem system) => repo.addConnection(fromId, toId);

  @override
  QuestChange? mergeWith(QuestChange newer) {
    if (newer is RemoveConnectionChange && newer.fromId == fromId && newer.toId == toId) {
      return null;
    }
    return newer;
  }

  @override
  int get questId => fromId;

  @override
  int? get otherQuestId => toId;
}

class RemoveConnectionChange extends _QuestTargetedChange {
  final int fromId;
  final int toId;

  const RemoveConnectionChange({required this.fromId, required this.toId, super.updateMessage = 'connection removed'});

  @override
  String get collapseKey => 'conn:${fromId}_$toId';

  @override
  void applyLocally(QuestSystem s) => s.removeConnection(fromId, toId);

  @override
  void undoLocally(QuestSystem s) => s.addConnection(fromId, toId);

  @override
  Future<void> push(QuestRepository repo, QuestSystem system) => repo.removeConnection(fromId, toId);

  @override
  QuestChange? mergeWith(QuestChange newer) {
    if (newer is AddConnectionChange && newer.fromId == fromId && newer.toId == toId) {
      return null;
    }
    return newer;
  }

  @override
  int get questId => fromId;

  @override
  int? get otherQuestId => toId;
}

class UpdateConnectionChange extends _QuestTargetedChange {
  final int fromId;
  final int toId;

  final QuestConnectionPatch patch;
  QuestConnectionPatch reversePatch;

  UpdateConnectionChange({
    required this.fromId,
    required this.toId,
    required this.patch,
    required this.reversePatch,
    super.updateMessage = 'updated connection',
  });

  @override
  String get collapseKey => 'conn:${fromId}_$toId';

  @override
  void applyLocally(QuestSystem system) {
    final current = system.getConnection(fromId, toId);
    if (current == null) return;
    system.updateConnection(fromId, toId, newType: patch.type, newXpRequirement: patch.xpRequirement);
  }

  @override
  void undoLocally(QuestSystem system) {
    final current = system.getConnection(fromId, toId);
    if (current == null) return;
    system.updateConnection(fromId, toId, newType: reversePatch.type, newXpRequirement: reversePatch.xpRequirement);
  }

  @override
  Future<void> push(QuestRepository repo, QuestSystem system) async {
    return repo.updateConnection(fromId, toId, newType: patch.type, newXpRequirement: patch.xpRequirement, updateMessage: updateMessage);
  }

  @override
  QuestChange? mergeWith(QuestChange newer) {
    if (newer is UpdateConnectionChange && newer.questId == questId) {
      return UpdateConnectionChange(
        fromId: fromId,
        toId: toId,
        patch: patch.mergedWith(newer.patch),
        reversePatch: reversePatch,
        updateMessage: newer.updateMessage,
      );
    }
    if (newer is RemoveConnectionChange) return newer;
    return newer;
  }

  @override
  int get questId => fromId;

  @override
  int? get otherQuestId => toId;

  @override
  String toString() =>
      'UpdateConnectionChange(fromId: $fromId, toId: $toId, patch: $patch, '
      'reversePatch: $reversePatch, updateMessage: $updateMessage)';
}
