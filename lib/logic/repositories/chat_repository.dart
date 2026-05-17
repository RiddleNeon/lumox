import 'package:lumox/base_ui.dart';

import '../../base_logic.dart';
import '../../tools/supabase_tests/supabase_login_test.dart';
import '../chat/chat.dart';
import '../chat/chat_message.dart';
import '../local_storage/local_seen_service.dart';

class ChatRepository {
  static const Duration _chatPageCacheTtl = Duration(seconds: 20);
  static const Duration _conversationSyncMinInterval = Duration(seconds: 4);
  static final RegExp _feedRouteRegex = RegExp(r'(?<!\S)(/feed/\d+)(?:\?[^\s]*)?');
  final Map<String, _CachedChatsPage> _chatPageCache = {};
  final Map<String, Future<({int? newCurrent, List<Chat> result})>> _inFlightChatPages = {};
  final Map<String, _CachedConversationId> _conversationIdCache = {};
  Future<void>? _conversationSyncTask;
  DateTime? _lastConversationSyncAt;

  Future<ChatMessage> sendNotification({required Chat chat, required ChatMessage message, void Function()? onUserBanned}) async {
    final receiverUid = chat.partnerId;
    final conversationId = await _getOrCreateDirectConversation(
      receiverUid,
      partnerName: chat.partnerName,
      partnerProfileImageUrl: chat.partnerProfileImageUrl,
    );
    chat.conversationId = conversationId;

    print("Sending message to conversation $conversationId with content: ${message.text}, replyToMessageId: ${message.replyToMessageId}");
    
    final Map<String, dynamic> responseJson = await supabaseClient.rpc('send_message', params: {
      'p_conversation_id': conversationId,
      'p_content': message.text,
      'p_reply_to_message_id': message.replyToMessageId != null ? int.parse(message.replyToMessageId!) : null,
    }).onError((error, stackTrace) {
      print("ERROR sending message: $error");
      return Future.error(error!, stackTrace);
    },).then((value) {
      print("Message sent successfully, server response: $value");
      return value as Map<String, dynamic>;
    },);
    
    print("Inserted message row. response json: $responseJson");
    
    bool successful = responseJson['success'] == true;
    if (!successful) {
      print("Server indicated failure in sending message. response: $responseJson");
      
      int? warningCount = responseJson['warning_count'] as int?;
      String error = responseJson['error'] as String? ?? 'Unknown error';
      bool isBanned = responseJson['is_banned'] as bool? ?? false;
      
      if(isBanned) {
        Future.delayed(const Duration(seconds: 3), () {
          userBannedHint = true;
          userRepository.selfBanUserSupabase();
          onUserBanned?.call();
        });
        throw UserBannedException("Your account has been banned due to repeated violations of our content guidelines. Please contact support for more information.");
      } else if (error == "MESSAGE_MODERATION_VIOLATION" && warningCount != null && warningCount > 0) {
        print("Message was sent but with $warningCount content warnings. error message: $error");
        throw ContentModerationViolationException(warningCount, "Message sent but contains content that may violate our guidelines. Please review the content and try again.");
      } else if(error == "USER_BANNED") {
        throw UserBannedException("Your account has been banned due to repeated violations of our content guidelines. Please contact support for more information.");
      } else {
        throw Exception("Failed to send message: $error");
      }
    }

    final actualMessage = _rowToChatMessage(responseJson['message']);

    await localSeenService.sendMessageLocal(chat, actualMessage);
    chat.lastMessage = actualMessage.text;
    chat.lastMessageAt = actualMessage.timestamp;
    chat.lastMessageByMe = true;
    _invalidateChatPagesForUser(currentUser.id);
    return actualMessage;
  }

  /// Loads messages with [otherUserId].
  Future<List<ChatMessage>> getMessagesWith(String otherUserId, {int limit = 30, DateTime? startOffset}) async {
    final localMessages = await localSeenService.getMessagesWithLocal(otherUserId, limit: limit, startOffset: startOffset);

    final conversationId = await _findDirectConversationId(otherUserId);
    if (conversationId == null) {
      print("No conversation found with $otherUserId, returning only local messages.");
      final result = localMessages..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return result.length > limit ? result.sublist(result.length - limit) : result;
    }
    
    final serverMessages = <ChatMessage>[];
    if (startOffset == null) {
      if (localMessages.isEmpty) {
        serverMessages.addAll(await _fetchMessagesFromServer(
          conversationId: conversationId,
          otherUserId: otherUserId,
          limit: limit,
        ));
      } else {
        final latestLocal = localMessages.map((m) => m.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
        final oldestLocal = localMessages.map((m) => m.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);

        serverMessages.addAll(await _fetchMessagesFromServer(
          conversationId: conversationId,
          otherUserId: otherUserId,
          limit: limit,
          after: latestLocal,
        ));

        final olderLimit = limit - localMessages.length;
        if (olderLimit > 0) {
          serverMessages.addAll(await _fetchMessagesFromServer(
            conversationId: conversationId,
            otherUserId: otherUserId,
            limit: olderLimit,
            before: oldestLocal,
          ));
        }
      }
    } else {
      serverMessages.addAll(await _fetchMessagesFromServer(
        conversationId: conversationId,
        otherUserId: otherUserId,
        limit: limit,
        before: startOffset,
      ));
    }

    if (serverMessages.isNotEmpty) {
      await localSeenService.saveMessagesLocal(otherUserId, serverMessages);
    }

    final merged = <String, ChatMessage>{
      for (final m in localMessages) m.id: m,
      for (final m in serverMessages) m.id: m,
    };

    final result = merged.values.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result.length > limit ? result.sublist(result.length - limit) : result;
  }

  /// Returns unique video ids from every /feed/:id route ever shared in this direct chat.
  /// IDs are ordered by message creation time (oldest -> newest), then by appearance within message text.
  Future<List<String>> getSharedFeedVideoIdsWith(String otherUserId) async {
    final conversationId = await _findDirectConversationId(otherUserId);
    if (conversationId == null) return const [];

    const pageSize = 500;
    var start = 0;
    final orderedIds = <String>[];
    final seen = <String>{};

    while (true) {
      final rows = (await supabaseClient
              .from('messages')
              .select('content, created_at')
              .eq('conversation_id', conversationId)
              .isFilter('deleted_at', null)
              .order('created_at', ascending: true)
              .range(start, start + pageSize - 1) as List)
          .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
          .toList();

      for (final row in rows) {
        final content = row['content'] as String? ?? '';
        for (final match in _feedRouteRegex.allMatches(content)) {
          final routeToken = match.group(1);
          if (routeToken == null || routeToken.isEmpty) continue;
          final uri = Uri.tryParse(routeToken);
          if (uri == null || uri.pathSegments.length < 2) continue;
          final videoId = uri.pathSegments[1].trim();
          if (videoId.isEmpty || !seen.add(videoId)) continue;
          orderedIds.add(videoId);
        }
      }

      if (rows.length < pageSize) break;
      start += rows.length;
    }

    return orderedIds;
  }
  
  Future<List<ChatMessage>> _fetchMessagesFromServer({
    required int conversationId,
    required String otherUserId,
    int limit = 30,
    DateTime? after,
    DateTime? before,
  }) async {
    try {
      var query = supabaseClient
          .from('messages')
          .select('id, conversation_id, sender_id, content, type, reply_to_message_id, created_at, edited_at, deleted_at')
          .eq('conversation_id', conversationId)
          .isFilter('deleted_at', null);

      if (after != null) {
        query = query.gt('created_at', after.toUtc().toIso8601String());
      }
      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }

      final rows = (await (query.order('created_at', ascending: false).limit(limit)) as List)
          .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
          .toList();

      return rows.map(_rowToChatMessage).toList();
    } catch (e) {
      print('Error fetching messages from server: $e');
      return [];
    }
  }

  /// Converts a raw Supabase `messages` row into a [ChatMessage].
  ChatMessage _rowToChatMessage(Map<String, dynamic> row) {
    final senderId = row['sender_id'] as String? ?? '';
    final isMe = senderId == currentUser.id;
    return ChatMessage(
      id: (row['id'] as int).toString(),
      text: row['content'] as String? ?? '',
      timestamp: _parseDateTime(row['created_at']),
      isMe: isMe,
      replyToMessageId: (row['reply_to_message_id'] as int?)?.toString(),
      type: row['type'] as String? ?? 'text',
      editedAt: row['edited_at'] == null ? null : _parseDateTime(row['edited_at']),
      deletedAt: row['deleted_at'] == null ? null : _parseDateTime(row['deleted_at']),
    );
  }

  Future<ChatMessage> editMessage({required String otherUserId, required String messageId, required String newText}) async {
    final updated = await supabaseClient.rpc('edit_message', params: {'p_message_id': int.parse(messageId), 'p_new_content': newText});
    final row = Map<String, dynamic>.from(updated as Map);
    final message = _rowToChatMessage(row);
    await localSeenService.updateMessageLocal(otherUserId, message);
    return message;
  }

  Future<void> deleteMessage({required String otherUserId, required String messageId}) async {
    await supabaseClient.rpc('delete_message', params: {'p_message_id': int.parse(messageId)});
    await localSeenService.deleteMessageLocal(otherUserId, messageId);
  }

  Future<List<MessageVersion>> getMessageVersions(String messageId) async {
    final rows = await supabaseClient.rpc('get_message_versions', params: {'p_message_id': int.parse(messageId)});
    final data = (rows as List).map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row)).toList();
    return data.map(MessageVersion.fromSupabase).toList();
  }

  Future<bool> canViewMessageHistory() async {
    final result = await supabaseClient.rpc('is_current_user_admin');
    return result == true;
  }

  ChatMessage? getMessage(String otherUserId, String messageId) {
    return localSeenService.getMessage(otherUserId, messageId);
  }

  Future<({int? newCurrent, List<Chat> result})> getChats(String userId, {int limit = 10, int offset = 0}) async {
    final cacheKey = _getChatsCacheKey(userId: userId, limit: limit, offset: offset);
    final cachedPage = _chatPageCache[cacheKey];
    if (cachedPage != null && !cachedPage.isExpired) {
      return _cloneChatPage(cachedPage.value);
    }

    final inFlight = _inFlightChatPages[cacheKey];
    if (inFlight != null) {
      return _cloneChatPage(await inFlight);
    }

    final fetch = _getChatsFromLocalWithIncrementalSync(userId, limit: limit, offset: offset)
        .then((value) {
          _chatPageCache[cacheKey] = _CachedChatsPage(value);
          return value;
        })
        .whenComplete(() {
          _inFlightChatPages.remove(cacheKey);
        });
    _inFlightChatPages[cacheKey] = fetch;
    return _cloneChatPage(await fetch);
  }
  
  Future<Chat> getChat(int conversationId, String otherUserId, {String partnerName = '', String partnerProfileImageUrl = '', bool? partnerIsAi, String? conversationType}) async {
    final chat = localSeenService.getChatWith(otherUserId);
    if (chat != null) {
      print("found in cache");
      return _cloneChat(chat);
    }
    
    final serverResult = await supabaseClient.from('conversations').select('type').eq('id', conversationId).maybeSingle();
    print("Queried conversation $conversationId from server, result: $serverResult");
    
    
    final conversation = serverResult as Map<String, dynamic>?;
    if (conversation == null) {
      throw Exception("No conversation found with id $conversationId");
    }
    final conversationTypeFromServer = conversation['type'] as String? ?? 'direct';
    final partnerIsAiFromServer = conversationTypeFromServer == 'direct-ai';
    print("conversation type from server: $conversationTypeFromServer, partnerIsAiFromServer: $partnerIsAiFromServer");
    final newChat = Chat(
      conversationId: conversationId,
      partnerId: otherUserId,
      partnerProfileImageUrl: partnerProfileImageUrl,
      partnerName: partnerName,
      lastMessage: '',
      lastMessageAt: null,
      lastMessageByMe: false,
      createdAt: DateTime.now(),
      partnerIsAi: partnerIsAi ?? partnerIsAiFromServer,
      conversationType: conversationType ?? conversationTypeFromServer,
    );
    localSeenService.saveChatsLocal([newChat]);
    
    return newChat;
  }

  Future<({int? newCurrent, List<Chat> result})> _getChatsFromLocalWithIncrementalSync(String userId, {int limit = 10, int offset = 0}) async {
    await _syncConversationsIncrementalIfNeeded();
    final localChats = localSeenService.getChats()..sort((a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(a.lastMessageAt ?? a.createdAt));
    final page = localChats.skip(offset).take(limit).toList();
    return (result: page, newCurrent: localChats.length > offset + page.length ? offset + page.length : null);
  }

  Future<void> _syncConversationsIncrementalIfNeeded() async {
    final now = DateTime.now();
    if (_lastConversationSyncAt != null && now.difference(_lastConversationSyncAt!) < _conversationSyncMinInterval) {
      return;
    }
    if (_conversationSyncTask != null) {
      return _conversationSyncTask;
    }
    _conversationSyncTask = localSeenService.syncConversationsIncremental().whenComplete(() {
      _lastConversationSyncAt = DateTime.now();
      _conversationSyncTask = null;
    });
    return _conversationSyncTask;
  }

  Future<int?> _findDirectConversationId(String receiverId) async {
    final cached = _conversationIdCache[receiverId];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final cachedChat = localSeenService.getChatWith(receiverId);
    if (cachedChat?.conversationId != null) {
      _conversationIdCache[receiverId] = _CachedConversationId(cachedChat!.conversationId);
      return cachedChat.conversationId;
    }

    final currentMembershipRows = await supabaseClient.from('conversation_members').select('conversation_id').eq('profile_id', currentUser.id);
    final currentConversationIds = (currentMembershipRows as List)
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .map<int>((row) => row['conversation_id'] as int)
        .toList();
    if (currentConversationIds.isEmpty) {
      return null;
    }

    final receiverMembershipRows = await supabaseClient
        .from('conversation_members')
        .select('conversation_id')
        .eq('profile_id', receiverId)
        .inFilter('conversation_id', currentConversationIds);
    final sharedConversationIds = (receiverMembershipRows as List)
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .map<int>((row) => row['conversation_id'] as int)
        .toList();
    if (sharedConversationIds.isEmpty) {
      return null;
    }

    final directConversations = await supabaseClient
        .from('conversations')
        .select('id')
        .inFilter('type', ['direct', 'direct-ai'])
        .inFilter('id', sharedConversationIds)
        .limit(1);

    final directConversationList = (directConversations as List).map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row)).toList();
    if (directConversationList.isEmpty) {
      _conversationIdCache[receiverId] = _CachedConversationId(null);
      return null;
    }
    final conversationId = directConversationList.first['id'] as int;
    _conversationIdCache[receiverId] = _CachedConversationId(conversationId);
    return conversationId;
  }

  Future<int> _getOrCreateDirectConversation(String receiverId, {required String partnerName, required String partnerProfileImageUrl}) async {
    final existingConversationId = await _findDirectConversationId(receiverId);
    if (existingConversationId != null) {
      _conversationIdCache[receiverId] = _CachedConversationId(existingConversationId);
      return existingConversationId;
    }

    print("No existing conversation found with $receiverId, creating a new one. currentUser: ${currentUser.id}");

    final conversationId = await supabaseClient.rpc(
      'create_conversation',
      params: {'p_receiver_id': receiverId, 'p_title': null, 'p_type': null},
    ) as int;
    print("Created conversation $conversationId with $receiverId");

    await getChat(conversationId, receiverId, partnerName: partnerName, partnerProfileImageUrl: partnerProfileImageUrl);
    print("got chat");
    _conversationIdCache[receiverId] = _CachedConversationId(conversationId);
    _invalidateChatPagesForUser(currentUser.id);

    return conversationId;
  }
  
  Future<int> createConversationWith(String otherUserId, {required String partnerName, required String partnerProfileImageUrl}) async {
    return await _getOrCreateDirectConversation(otherUserId, partnerName: partnerName, partnerProfileImageUrl: partnerProfileImageUrl);
  }

  void _invalidateChatPagesForUser(String userId) {
    final prefix = '$userId:';
    _chatPageCache.removeWhere((key, _) => key.startsWith(prefix));
  }

  String _getChatsCacheKey({required String userId, required int limit, required int offset}) {
    return '$userId:$offset:$limit';
  }

  ({int? newCurrent, List<Chat> result}) _cloneChatPage(({int? newCurrent, List<Chat> result}) page) {
    return (newCurrent: page.newCurrent, result: page.result.map(_cloneChat).toList());
  }

  Chat _cloneChat(Chat chat) {
    return Chat.fromJson(chat.toJson(), customPartnerId: chat.partnerId);
  }
}

String getChatId({String? currentUserId, required String receiverId}) {
  final userId = currentUserId ?? currentUser.id;
  final ids = [userId, receiverId]..sort();
  return "${ids[0]}-${ids[1]}";
}

DateTime _parseDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.parse(value);
  return DateTime.now();
}

class _CachedChatsPage {
  final ({int? newCurrent, List<Chat> result}) value;
  final DateTime cachedAt;

  _CachedChatsPage(this.value) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt) > ChatRepository._chatPageCacheTtl;
}

class _CachedConversationId {
  static const Duration _ttl = Duration(minutes: 5);
  final int? value;
  final DateTime cachedAt;

  _CachedConversationId(this.value) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt) > _ttl;
}


class ContentModerationViolationException implements Exception {
  final int warningCount;
  final String message;

  ContentModerationViolationException(this.warningCount, this.message);

  @override
  String toString() => 'ContentModerationViolationException: $message (warnings: $warningCount)';
}

class UserBannedException implements Exception {
  final String message;

  UserBannedException(this.message);

  @override
  String toString() => 'UserBannedException: $message';
}