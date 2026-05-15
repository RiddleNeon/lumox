import 'package:lumox/logic/chat/chat.dart';
import 'package:lumox/logic/chat/chat_message.dart';
import 'package:lumox/logic/users/user_model.dart';

import '../../base_logic.dart';
import '../../tools/supabase_tests/supabase_login_test.dart';

LocalSeenService get localSeenService {
  if (_localSeenService == null) throw StateError("Local Seen Service isn't initialized yet!");
  return _localSeenService!;
}

LocalSeenService? _localSeenService;

Future<void> initLocalSeenService() async {
  _localSeenService = LocalSeenService();
  await _localSeenService!.init();
}

Future<void> disposeLocalSeenService() async {
  return await _localSeenService?.dispose();
}

class LocalSeenService {
  // Settings keys
  static const String _lastSyncLikesKey = 'lastSyncLikesTimestamp';
  static const String _lastSyncDislikesKey = 'lastSyncDislikesTimestamp';
  static const String _lastSyncPreferencesKey = 'lastSyncPreferencesTimestamp';
  static const String _lastSyncFollowingKey = 'lastSyncFollowingTimestamp';
  static const String _lastSyncConversationKey = 'lastSyncConversationTimestamp';
  static const String _lastUpdateAuthorsKey = 'lastUpdateAuthorsTimestamp';

  final Map<String, dynamic> _settings = {};
  final Map<String, DateTime> _cursor = {};
  final Map<String, DateTime> _cursorDirty = {};
  final Map<String, DateTime> _blacklistedTags = {};
  final Map<String, bool> _likeVals = {};
  final Map<String, DateTime> _following = {};
  final Map<String, Map<String, dynamic>> _authorCache = {};
  final Map<String, Map<String, dynamic>> _chatMessages = {};
  final Map<String, DateTime> _chatCursors = {};
  final Map<String, Map<String, dynamic>> _conversations = {};

  late final String userId;

  Future<void> init() async {
    userId = currentAuthUserId();
    final lastAuthorUpdate = _settings[_lastUpdateAuthorsKey] as DateTime?;
    if (lastAuthorUpdate == null || DateTime.now().difference(lastAuthorUpdate) > const Duration(days: 2)) {
      _authorCache.clear();
      _settings[_lastUpdateAuthorsKey] = DateTime.now();
    }

    await syncWithSupabase();
  }

  Future<void> dispose() async {
    _settings.clear();
    _cursor.clear();
    _cursorDirty.clear();
    _blacklistedTags.clear();
    _likeVals.clear();
    _following.clear();
    _authorCache.clear();
    _chatMessages.clear();
    _chatCursors.clear();
    _conversations.clear();
  }

  bool hasSeen(String videoId) => false;

  /*_seenBox.containsKey(videoId);*/
  
  // ---------------------------------------------------------------------------
  // MAIN SYNC
  // ---------------------------------------------------------------------------

  Future<void> syncWithSupabase({bool onlyLoad = true}) async {
    final lastSyncLikes = _settings[_lastSyncLikesKey] as DateTime? ?? DateTime.utc(2024, 1, 1);
    final lastSyncDislikes = _settings[_lastSyncDislikesKey] as DateTime? ?? DateTime.utc(2024, 1, 1);
    final lastSyncPreferences = _settings[_lastSyncPreferencesKey] as DateTime? ?? DateTime.utc(2024, 1, 1);
    final lastSyncFollowing = _settings[_lastSyncFollowingKey] as DateTime? ?? DateTime.utc(2024, 1, 1);
    final lastSyncConversation = _settings[_lastSyncConversationKey] as DateTime? ?? DateTime.utc(2024, 1, 1);

    await Future.wait([
      _syncLikes(lastSyncLikes, onlyLoad: onlyLoad),
      _syncDislikes(lastSyncDislikes, onlyLoad: onlyLoad),
      _syncPreferences(lastSyncPreferences, onlyLoad: onlyLoad),
      _syncFollowing(lastSyncFollowing, onlyLoad: onlyLoad),
      _syncConversations(lastSyncConversation),
    ]);
  }

  Future<void> syncConversationsIncremental() async {
    final lastSyncConversation = _settings[_lastSyncConversationKey] as DateTime? ?? DateTime.utc(2024, 1, 1);
    await _syncConversations(lastSyncConversation);
  }

  // ---------------------------------------------------------------------------
  // likes  →  users/{uid}/liked_videos/{videoId}
  // ---------------------------------------------------------------------------

  Future<void> _syncLikes(DateTime lastSync, {required bool onlyLoad}) async {
    if (!onlyLoad) {
      final payload = <Map<String, dynamic>>[];
      for (final entry in _likeVals.entries) {
        final videoId = entry.key;
        if (entry.value != true) continue;
        final parsedVideoId = int.tryParse(videoId);
        if (parsedVideoId == null) continue;
        payload.add({'user_id': userId, 'video_id': parsedVideoId});
      }
      if (payload.isNotEmpty) {
        await _upsertInChunks('likes', payload, onConflict: 'user_id, video_id');
      }
    }

    final snapshot = await supabaseClient
        .from('likes')
        .select('video_id, created_at')
        .eq('user_id', userId)
        .gt('created_at', lastSync.toIso8601String())
        .order('created_at', ascending: false);

    if (snapshot.isEmpty) {
      return;
    }

    _likeVals.addAll({for (final row in snapshot) row['video_id'].toString(): true});

    _settings[_lastSyncLikesKey] = DateTime.parse(snapshot.first['created_at'] as String).toLocal();
  }

  Future<void> _syncDislikes(DateTime lastSync, {required bool onlyLoad}) async {
    if (!onlyLoad) {
      final payload = <Map<String, dynamic>>[];
      for (final entry in _likeVals.entries) {
        final videoId = entry.key;
        if (entry.value != false) continue;
        final parsedVideoId = int.tryParse(videoId);
        if (parsedVideoId == null) continue;
        payload.add({'user_id': userId, 'video_id': parsedVideoId});
      }
      if (payload.isNotEmpty) {
        await _upsertInChunks('dislikes', payload, onConflict: 'user_id, video_id');
      }
    }

    final snapshot = await supabaseClient
        .from('dislikes')
        .select('video_id, created_at')
        .eq('user_id', userId)
        .gt('created_at', lastSync.toIso8601String())
        .order('created_at', ascending: false);

    if (snapshot.isEmpty) {
      return;
    }

    _likeVals.addAll({for (final row in snapshot) row['video_id'].toString(): false});

    _settings[_lastSyncDislikesKey] = DateTime.parse(snapshot.first['created_at'] as String).toLocal();
  }

  Future<void> _syncPreferences(DateTime lastSync, {required bool onlyLoad}) async {
    if (!onlyLoad) {
      print('Skipping remote preference sync because the provided Supabase schema has no user_preferences table.');
    }
    _settings[_lastSyncPreferencesKey] = DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // Cursor helpers
  // ---------------------------------------------------------------------------

  DateTime? getNewestSeenTimestamp() => _cursor['newestSeenTimestamp'];

  Future<void> saveNewestSeenTimestamp(DateTime timestamp) async {
    _cursor['newestSeenTimestamp'] = timestamp;
    _cursorDirty['newestSeenTimestamp'] = DateTime.now();
  }

  DateTime? getOldestSeenTimestamp() => _cursor['oldestSeenTimestamp'];

  Future<void> saveOldestSeenTimestamp(DateTime timestamp) async {
    _cursor['oldestSeenTimestamp'] = timestamp;
    _cursorDirty['oldestSeenTimestamp'] = DateTime.now();
  }

  DateTime? getTrendingCursor() => _cursor['trendingCursor'];

  Future<void> saveTrendingCursor(DateTime timestamp) async {
    _cursor['trendingCursor'] = timestamp;
    _cursorDirty['trendingCursor'] = DateTime.now();
  }

  Future<void> resetCursors() async {
    _cursor.clear();
    _cursorDirty.clear();
  }

  DateTime? getTagCursor(String tag) => _cursor['tag_cursor_$tag'];

  Future<void> saveTagCursor(String tag, DateTime timestamp) async {
    _cursor['tag_cursor_$tag'] = timestamp;
    _cursorDirty['tag_cursor_$tag'] = DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // Blacklisted tags helpers
  // ---------------------------------------------------------------------------

  Future<void> saveBlacklistedTag(String tag, DateTime timestamp) async {
    _blacklistedTags[tag] = timestamp;
  }

  List<String> getBlacklistedTags() {
    return _blacklistedTags.keys.toList();
  }

  Future<void> removeBlacklistedTag(String tag) async {
    _blacklistedTags.remove(tag);
  }

  Future<void> clearBlacklistedTags() async {
    _blacklistedTags.clear();
  }

  // ---------------------------------------------------------------------------
  // Like / dislike helpers
  // ---------------------------------------------------------------------------

  Future<void> saveLike(String videoId) async {
    _likeVals[videoId] = true;
  }

  Future<void> removeLike(String videoId) async {
    _likeVals.remove(videoId);
  }

  Future<void> saveDislike(String videoId) async {
    _likeVals[videoId] = false;
  }

  Future<void> removeDislike(String videoId) async {
    _likeVals.remove(videoId);
  }

  bool isLiked(String videoId) => _likeVals[videoId] == true;

  bool isDisliked(String videoId) => _likeVals[videoId] == false;

  // ---------------------------------------------------------------------------
  // Following  →  users/{uid}/following/{followedUserId}/followedAt
  // ---------------------------------------------------------------------------

  Future<void> _syncFollowing(DateTime lastSync, {required bool onlyLoad}) async {
    if (!onlyLoad) {
      final payload = <Map<String, dynamic>>[];
      for (final entry in _following.entries) {
        final followedUserId = entry.key;
        final followedAt = entry.value;
        if (!followedAt.isAfter(lastSync)) continue;
        payload.add({'follower_id': userId, 'following_id': followedUserId, 'created_at': followedAt.toIso8601String()});
      }
      if (payload.isNotEmpty) {
        await _upsertInChunks('follows', payload, onConflict: 'follower_id, following_id');
      }
    }

    final snapshot = await supabaseClient
        .from('follows')
        .select('following_id, created_at')
        .eq('follower_id', userId)
        .gt('created_at', lastSync.toIso8601String())
        .order('created_at', ascending: false);

    if (snapshot.isEmpty) {
      return;
    }
    final Map<String, DateTime> toWrite = {};
    for (final row in snapshot) {
      final followedAt = DateTime.parse(row['created_at'] as String).toLocal();
      final followedUserId = row['following_id'] as String;
      final local = _following[followedUserId];
      if (local == null || followedAt.isAfter(local)) {
        toWrite[followedUserId] = followedAt;
      }
    }

    if (toWrite.isNotEmpty) {
      _following.addAll(toWrite);
    }

    _settings[_lastSyncFollowingKey] = DateTime.parse(snapshot.first['created_at'] as String).toLocal();
  }

  Future<void> _syncConversations(DateTime lastSync) async {
    final memberships = await supabaseClient.from('conversation_members').select('conversation_id').eq('profile_id', userId);
    final conversationIds = memberships.map((row) => row['conversation_id'] as int).toList();
    if (conversationIds.isEmpty) {
      _settings[_lastSyncConversationKey] = DateTime.now();
      return;
    }

    final conversations = await supabaseClient
        .from('conversations')
        .select('id, created_at, updated_at, last_message, type')
        .inFilter('id', conversationIds)
        .gt('updated_at', lastSync.toIso8601String())
        .order('updated_at', ascending: false);

    if (conversations.isEmpty) {
      _settings[_lastSyncConversationKey] = DateTime.now();
      return;
    }

    final Map<String, Map<String, dynamic>> toWrite = {};

    final memberRows = await supabaseClient
        .from('conversation_members')
        .select('conversation_id, profile_id, profiles!conversation_members_profile_id_fkey(id, username, display_name, avatar_url, bio, created_at)')
        .inFilter('conversation_id', conversations.map((e) => e['id']).toList());

    final membersByConversation = <int, Map<String, dynamic>>{};
    for (final rawRow in memberRows) {
      final row = Map<String, dynamic>.from(rawRow);
      final rowConversationId = row['conversation_id'] as int?;
      final profileId = row['profile_id'] as String?;
      if (rowConversationId == null || profileId == null || profileId == userId) continue;
      membersByConversation[rowConversationId] = row;
    }

    for (final conversation in conversations) {
      final conversationId = conversation['id'] as int;
      final partner = membersByConversation[conversationId];
      if (partner == null) continue;
      final partnerId = partner['profile_id'] as String;
      final existingLocal = _conversations[partnerId];
      final lastMessageAt = DateTime.parse(conversation['updated_at'] as String).toLocal();
      final localLastMessageAt = existingLocal?['lastMessageAt'] as DateTime?;
      final rawLastMessage = (conversation['last_message'] as String?) ?? '';
      String lastMessageContent = existingLocal?['lastMessage'] ?? '';
      bool lastMessageByMe = existingLocal?['lastMessageByMe'] ?? false;
      if (rawLastMessage.contains(': ')) {
        lastMessageContent = rawLastMessage.split(': ').skip(1).join(': ');
        final senderId = rawLastMessage.split(': ').first;
        lastMessageByMe = senderId == userId;
      }

      if (localLastMessageAt == null || lastMessageAt.isAfter(localLastMessageAt)) {
        final rawProfile = partner['profiles'];
        final partnerProfile = rawProfile is Map ? Map<String, dynamic>.from(rawProfile) : <String, dynamic>{};
        toWrite[partnerId] = {
          'conversationId': conversationId,
          'partnerId': partnerId,
          'lastMessageAt': lastMessageAt,
          'lastMessage': lastMessageContent,
          'createdAt': DateTime.parse(conversation['created_at'] as String).toLocal(),
          'currentUserId': userId,
          'partnerName': partnerProfile['display_name'] ?? partnerProfile['username'] ?? partnerId,
          'partnerProfileImageUrl': partnerProfile['avatar_url'] ?? '',
          'lastMessageByMe': lastMessageByMe,
          'partnerIsAi': conversation['type'] == 'direct-ai',
          'conversationType': conversation['type'] ?? 'direct',
        };

        final cursor = _chatCursors[_conversationId(partnerId)];
        if (cursor == null || lastMessageAt.isAfter(cursor)) {
          _chatCursors[_conversationId(partnerId)] = lastMessageAt;
        }
      }
    }

    if (toWrite.isNotEmpty) {
      _conversations.addAll(toWrite);
    }

    final latestConversation = DateTime.parse(conversations.first['updated_at'] as String).toLocal();
    _settings[_lastSyncConversationKey] = latestConversation;
  }

  // ---------------------------------------------------------------------------
  // Following helpers
  // ---------------------------------------------------------------------------

  Future<void> followUser(String followedUserId) async {
    final now = DateTime.now();
    _following[followedUserId] = now;
  }

  Future<void> unfollowUser(String followedUserId) async {
    _following.remove(followedUserId);
  }

  bool isFollowing(String followedUserId) => _following.containsKey(followedUserId);

  Set<String> get allFollowingIds => _following.keys.toSet();

  DateTime? followedAt(String followedUserId) => _following[followedUserId];

  String _conversationId(String otherUserId) {
    final ids = [userId, otherUserId]..sort();
    return '${ids[0]}-${ids[1]}';
  }

  String _chatKey(String conversationId, String messageId) => '$conversationId:$messageId';

  Map<String, dynamic> _messageToMap(ChatMessage message, String conversationId) {
    final isA = currentUser.id.compareTo(conversationId.split('-')[1]) > 0;
    return {
      'id': message.id,
      'message': message.text,
      'isA': isA == message.isMe,
      'createdAt': message.timestamp,
      'status': message.status.index,
      'editedAt': message.editedAt,
      'deletedAt': message.deletedAt,
    };
  }

  ChatMessage _messageFromMap(Map map, String conversationId) {
    final isA = currentUser.id.compareTo(conversationId.split('-')[1]) > 0;
    return ChatMessage(
      id: map['id'] as String,
      text: map['message'] as String,
      isMe: (map['isA'] as bool) == isA,
      timestamp: map['createdAt'],
      status: MessageStatus.values[map['status'] as int],
      editedAt: map['editedAt'] as DateTime?,
      deletedAt: map['deletedAt'] as DateTime?,
    );
  }

  bool hasChatWith(String otherUserId) {
    final conversationId = _conversationId(otherUserId);
    return _chatCursors.containsKey(conversationId);
  }

  List<Chat> getChats() {
    final chats = _conversations.values.map((e) => Chat.fromJson(e)).toList();
    return chats;
  }

  Chat? getChatWith(String userId) {
    final raw = _conversations[userId];
    if (raw == null) return null;
    return Chat.fromJson(raw);
  }

  Future<void> sendMessageLocal(Chat chat, ChatMessage message) async {
    final conversationId = _conversationId(chat.partnerId);
    final key = _chatKey(conversationId, message.id);

    _chatMessages[key] = _messageToMap(message, conversationId);

    final existing = _chatCursors[conversationId];
    if (existing == null || message.timestamp.isAfter(existing)) {
      _chatCursors[conversationId] = message.timestamp;
    }

    chat.lastMessage = message.text;
    chat.lastMessageAt = message.timestamp;
    chat.lastMessageByMe = message.isMe;
    _conversations[chat.partnerId] = chat.toJson();
  }

  ChatMessage? getMessage(String otherUserId, String messageId) {
    final conversationId = _conversationId(otherUserId);
    final key = _chatKey(conversationId, messageId);
    final raw = _chatMessages[key];
    if (raw == null) return null;
    return _messageFromMap(raw, conversationId);
  }

  Future<List<ChatMessage>> getMessagesWithLocal(String otherUserId, {int limit = 30, DateTime? startOffset}) async {
    final conversationId = _conversationId(otherUserId);

    final localMessages =
        _chatMessages
            .entries
            .where((e) => e.key.startsWith('$conversationId:'))
            .where((element) {
              final createdAt = element.value['createdAt'];
              if (createdAt is! DateTime) return false;
              return createdAt.isBefore(startOffset ?? DateTime.now());
            })
            .map((e) => _messageFromMap(e.value, conversationId))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return localMessages.length > limit ? localMessages.sublist(localMessages.length - limit) : localMessages;
  }

  Future<void> saveMessagesLocal(String otherUserId, Iterable<ChatMessage> messages) async {
    final conversationId = _conversationId(otherUserId);
    DateTime? latestTimestamp;

    for (final message in messages) {
      _chatMessages[_chatKey(conversationId, message.id)] = _messageToMap(message, conversationId);
      if (latestTimestamp == null || message.timestamp.isAfter(latestTimestamp)) {
        latestTimestamp = message.timestamp;
      }
    }

    if (latestTimestamp != null) {
      final existing = _chatCursors[conversationId];
      if (existing == null || latestTimestamp.isAfter(existing)) {
        _chatCursors[conversationId] = latestTimestamp;
      }
    }
  }

  Future<void> updateMessageLocal(String otherUserId, ChatMessage message) async {
    final conversationId = _conversationId(otherUserId);
    final key = _chatKey(conversationId, message.id);
    if (!_chatMessages.containsKey(key)) return;
    _chatMessages[key] = _messageToMap(message, conversationId);
  }

  Future<void> deleteMessageLocal(String otherUserId, String messageId) async {
    final conversationId = _conversationId(otherUserId);
    _chatMessages.remove(_chatKey(conversationId, messageId));
  }

  Future<void> saveChatsLocal(Iterable<Chat> chats) async {
    for (final chat in chats) {
      final existingRaw = _conversations[chat.partnerId];
      final existing = existingRaw == null ? null : Chat.fromJson(Map<String, dynamic>.from(existingRaw));
      final existingTimestamp = existing?.lastMessageAt ?? existing?.createdAt;
      final incomingTimestamp = chat.lastMessageAt ?? chat.createdAt;

      if (existingTimestamp == null || incomingTimestamp.isAfter(existingTimestamp)) {
        _conversations[chat.partnerId] = chat.toJson();
      }

      final conversationId = _conversationId(chat.partnerId);
      final currentCursor = _chatCursors[conversationId];
      if (currentCursor == null || incomingTimestamp.isAfter(currentCursor)) {
        _chatCursors[conversationId] = incomingTimestamp;
      }
    }
  }

  Future<List<ChatMessage>> getMessagesWith(String otherUserId, {int limit = 30, DateTime? startOffset}) async {
    return getMessagesWithLocal(otherUserId, limit: limit, startOffset: startOffset);
  }

  Map<String, String> cachedFcmTokens = {};

  Future<String?> getFcmToken(String userId) async {
    if (cachedFcmTokens.containsKey(userId)) return cachedFcmTokens[userId]!;
    final token = await userRepository.getFcmTokenSupabase(userId);
    if (token == null) return null;
    cachedFcmTokens[userId] = token;

    return token;
  }

  Future<void> saveAuthor(UserProfile user) async {
    _authorCache[user.id] = user.toJson();
  }

  UserProfile? getAuthorFromCache(String id) {
    final json = _authorCache[id];
    if (json == null) return null;
    return UserProfile.fromJson(json);
  }

  Future<void> _upsertInChunks(String table, List<Map<String, dynamic>> payload, {required String onConflict, int chunkSize = 200}) async {
    for (int i = 0; i < payload.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(i, payload.length);
      await supabaseClient.from(table).upsert(payload.sublist(i, end), onConflict: onConflict);
    }
  }
}

DateTime olderDate(DateTime? d1, DateTime? d2) {
  assert(!(d1 == null && d2 == null));
  if (d1 == null) return d2!;
  if (d2 == null) return d1;
  return d1.isBefore(d2) ? d1 : d2;
}
