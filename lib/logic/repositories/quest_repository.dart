import 'dart:ui';

import 'package:lumox/logic/quests/quest.dart';
import 'package:lumox/logic/quests/quest_change_manager.dart';
import 'package:lumox/logic/quests/quest_connection.dart';
import 'package:lumox/tools/supabase_tests/supabase_login_test.dart';

import '../../base_logic.dart';

QuestRepository questRepo = QuestRepository();

class QuestRepository {
  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Full snapshot – only used for the initial version of a new quest.
  Map<String, dynamic> _questToMap(Quest quest, String updateMessage, {bool isDeleted = false}) => {
    'quest_id': quest.id,
    'created_by': currentUser.id,
    'update_message': updateMessage,
    'title': quest.name,
    'description': quest.description,
    'subject': quest.subject,
    'difficulty': quest.difficulty,
    'pos_x': quest.posX.toInt(),
    'pos_y': quest.posY.toInt(),
    'size_x': quest.sizeX.toInt(),
    'size_y': quest.sizeY.toInt(),
    'is_deleted': isDeleted,
    'color': quest.color.toARGB32(),
  };

  Quest _questFromRow(Map<String, dynamic> row) => Quest(
    id: row['quest_id'] as int,
    name: row['title'] as String,
    description: row['description'] as String,
    subject: row['subject'] as String,
    difficulty: (row['difficulty'] as num).toDouble(),
    posX: (row['pos_x'] as num).toDouble(),
    posY: (row['pos_y'] as num).toDouble(),
    sizeX: (row['size_x'] as num).toDouble(),
    sizeY: (row['size_y'] as num).toDouble(),
    color: (row['color'] != null) ? Color(row['color'] as int) : const Color(0xFFFFFFFF),
  );

  // ── Fetch ──────────────────────────────────────────────────────────────────

  /// Loads all non-deleted quests for [subject] and returns them together with
  /// their prerequisite connections as a [Map<fromId, Set<toId>>].
  Future<(List<Quest>, List<QuestConnection>)> fetchQuestsBySubject(String subject) async {
    final questRows = await supabaseClient.from('quests_latest').select().eq('subject', subject).eq('is_deleted', false);

    final Map<int, Quest> questMap = {for (final row in questRows as List<dynamic>) (row['quest_id'] as int): _questFromRow(row as Map<String, dynamic>)};

    if (questMap.isEmpty) return (<Quest>[], <QuestConnection>[]);


    final connectionRows = await supabaseClient
        .from('quest_connections')
        .select('from_id, to_id, quest_connections_latest!connection_id(is_deleted, type, xp_requirement)')
        .inFilter('from_id', questMap.keys.toList())
        .inFilter('to_id', questMap.keys.toList())
        .limit(10000);

    final List<QuestConnection> connectionList = [];
    for (final row in connectionRows as List<dynamic>) {
      final latest = row['quest_connections_latest'] as Map<String, dynamic>?;
      if (latest == null || latest['is_deleted'] == true) continue;
      connectionList.add(QuestConnection(fromQuestId: row['from_id'] as int, toQuestId: row['to_id'] as int, type: row['quest_connections_latest']['type'] as String, xpRequirement: (row['quest_connections_latest']['xp_requirement'] as num?)?.toDouble() ?? 0));
    }


    return (questMap.values.toList(), connectionList);
  }

  Future<List<String>> fetchQuestSubjects() async {
    final rows = await supabaseClient.from('quests_latest').select('subject').eq('is_deleted', false);
    final subjects = <String>{};

    for (final row in rows as List<dynamic>) {
      final subject = (row as Map<String, dynamic>)['subject'] as String?;
      if (subject == null) continue;
      final trimmed = subject.trim();
      if (trimmed.isNotEmpty) subjects.add(trimmed);
    }

    final list = subjects.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Inserts a new quest row and its first version (full snapshot).
  Future<void> addQuest(Quest quest, [String message = 'initial version']) async {
    await supabaseClient.from('quests').insert({'id': quest.id, 'created_by': currentUser.id});
    await supabaseClient.from('quest_versions').insert(_questToMap(quest, message)).select().single();
  }

  /// Appends a version that contains only the changed fields from [patch].
  /// NULL fields are omitted – the DB trigger fills them from the previous
  /// version via COALESCE.
  Future<void> patchQuest(int questId, QuestPatch patch, String message) async {
    print('Patching quest $questId: $message');
    await supabaseClient
        .from('quest_versions')
        .insert(patch.toSupabaseMap(questId: questId, updateMessage: message, createdBy: currentUser.id))
        .select()
        .single();
  }

  /// Soft-deletes a quest by inserting a version with is_deleted = true.
  Future<void> deleteQuest(Quest quest) async {
    print('Deleting quest ${quest.id}');
    await supabaseClient.from('quest_versions').insert(_questToMap(quest, 'quest deleted', isDeleted: true));
  }

  /// Creates a prerequisite connection: [toId] must be completed before [fromId].
  /// Does NOT mutate local state – the caller (QuestChangeManager) is responsible
  /// for that via [QuestSystem.addConnection].
  Future<void> addConnection(int fromId, int toId) async {
    print('Adding connection from $fromId to $toId');

    final int? existingId =
        (await supabaseClient.from('quest_connections').select('connection_id').eq('from_id', fromId).eq('to_id', toId).maybeSingle())?['connection_id']
            as int?;
    final exists = existingId != null;
    print('Connection already exists? $exists (id: $existingId)');
    final int connectionId;

    if (!exists) {
      print('Inserting new connection into quest_connections');
      final result = await supabaseClient
          .from('quest_connections')
          .insert({'from_id': fromId, 'to_id': toId, 'created_at': DateTime.now().toIso8601String(), 'created_by': currentUser.id})
          .select()
          .single();
      connectionId = result['connection_id'] as int;
    } else {
      connectionId = existingId;
    }

    print('Connection ID to version: $connectionId');

    await supabaseClient.from('quest_connection_versions').insert({
      'connection_id': connectionId,
      'type': 'prerequisite',
      'is_deleted': false,
      'update_message': exists ? 'connection updated' : 'connection added',
      'created_by': currentUser.id,
    });
  }

  /// Soft-deletes a prerequisite connection.
  /// Does NOT mutate local state – the caller (QuestChangeManager) is responsible.
  Future<void> removeConnection(int fromId, int toId) async {
    final int? existingId =
        (await supabaseClient.from('quest_connections').select('connection_id').eq('from_id', fromId).eq('to_id', toId).maybeSingle())?['connection_id']
            as int?;
    final bool exists = existingId != null;
    final int connectionId;
    if (!exists) {
      print("Connection doesn't exist, inserting new connection into quest_connections");
      connectionId =
          (await supabaseClient.from('quest_connections').insert({'from_id': fromId, 'to_id': toId, 'created_by': currentUser.id}).select().single())['connection_id']
              as int;
    } else {
      connectionId = existingId;
    }
    await supabaseClient.from('quest_connection_versions').insert({
      'connection_id': connectionId,
      'type': 'prerequisite',
      'is_deleted': true,
      'update_message': 'connection removed',
      'created_by': currentUser.id,
    });
  }

  Future<void> updateConnection(int fromId, int toId, {String? newType, double? newXpRequirement, String? updateMessage}) async {
    final int? existingId =
        (await supabaseClient.from('quest_connections').select('connection_id').eq('from_id', fromId).eq('to_id', toId).maybeSingle())?['connection_id']
            as int?;
    final bool exists = existingId != null;
    final int? connectionId;
    if (!exists) {
      print("Connection doesn't exist, inserting new connection into quest_connections");
      connectionId =
          (await supabaseClient.from('quest_connections').insert({
                'from_id': fromId,
                'to_id': toId,
                'created_by': currentUser.id,
              }).select().maybeSingle())?['connection_id']
              as int?;
      print("inserted new connection with id $connectionId for update");
    } else {
      connectionId = existingId;
    }
    final Map<String, dynamic> updateData = {
      'connection_id': connectionId,
      'update_message': updateMessage ?? 'connection updated',
      'created_by': currentUser.id,
      'type': newType,
      'xp_requirement': newXpRequirement,
    };

    await supabaseClient.from('quest_connection_versions').insert(updateData);
  }
}
