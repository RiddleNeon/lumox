import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:lumox/logic/dictionary/dictionary_entry.dart';
import 'package:lumox/logic/repositories/dictionary_repository.dart';
import 'package:lumox/logic/repositories/user_repository.dart';
import 'package:lumox/logic/repositories/video_repository.dart';
import 'package:lumox/logic/users/user_model.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/ui/dictionary/dictionary_picker_sheet.dart';
import 'package:lumox/ui/router/router.dart';
import 'package:lumox/ui/screens/profile_screen.dart';
import 'package:lumox/ui/theme/theme_creation_screen.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';
import 'package:lumox/ui/widgets/dictionary/dictionary_linkifier.dart';
import 'package:lumox/ui/widgets/loading/shimmer_block.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../base_logic.dart';
import '../../../logic/chat/chat_message.dart';
import '../../../logic/local_storage/local_seen_service.dart';
import '../../../logic/repositories/chat_repository.dart';
import '../search_screen/search_video_overlay.dart';
import 'calling_screen.dart';
import 'chat_attachment_builders.dart';
import 'chat_route_preview.dart';
import 'message_avatar.dart';
import 'message_bubble.dart';

class MessagingScreen extends StatefulWidget {
  final Future<ChatMessage> Function(String message, void Function()? onUserBanned) onSend;

  final Future<ChatMessage> Function(ChatMessage message, String newText) onEditOwnMessage;
  final Future<void> Function(ChatMessage message) onDeleteOwnMessage;
  final Future<List<MessageVersion>> Function(ChatMessage message) onLoadMessageVersions;
  final Future<bool> Function() canViewMessageHistory;
  final void Function(ChatMessage message) onMessageUpdateLocal;
  final Future<List<ChatMessage>> Function(int limit, DateTime? lastVisibleMessage) loadMoreMessages;

  String? get recipientName => user.displayName;

  String get recipientId => user.id;

  String? get recipientAvatarUrl => user.profileImageUrl;

  final UserProfile user;

  final bool isOnline;

  final int conversationId;

  final bool fakeTyping;

  const MessagingScreen({
    super.key,
    required this.onSend,
    required this.onEditOwnMessage,
    required this.onDeleteOwnMessage,
    required this.onLoadMessageVersions,
    required this.canViewMessageHistory,
    this.isOnline = true,
    required this.loadMoreMessages,
    required this.onMessageUpdateLocal,
    required this.user,
    required this.conversationId,
    this.fakeTyping = false,
  });

  @override
  State<MessagingScreen> createState() => MessagingScreenState();
}

class MessagingScreenState extends State<MessagingScreen> with TickerProviderStateMixin {
  static const String _cloudinaryCloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

   bool moreMessagesAvailable = true;
   DateTime? currentMessageCursor;

   late final List<ChatMessage> _messages = [];
   final Map<String, AnimationController> _bubbleControllers = {};

    bool _isTyping = false;
    bool _showScrollDown = false;
    bool _partnerTyping = false;
    bool _initialViewportAnchored = false;
    bool _historyLoadArmedByUserScroll = false;
    static const int _initialHistoryPageSize = 30;
    static const int _historyPageSize = 20;
    static const double _historyLoadTopThreshold = 80;
    static const double _bottomScrollThreshold = 80;
    String? _editingMessageId;
  bool _canViewMessageHistory = false;
  final Map<String, Future<ChatRoutePreview?>> _previewFutureCache = {};
  List<String>? _sharedFeedVideoIds;
  Future<List<String>>? _sharedFeedVideoIdsTask;
  Map<String, DictionaryEntry> _dictionaryEntriesByTitle = {};

  late AnimationController _typingDotController;

  RealtimeChannel? _messagesChannel;

   @override
   void initState() {
     super.initState();

     _textController.addListener(_onTextChanged);
     _scrollController.addListener(_onScroll);

     _typingDotController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

     _loadHistoryPermission();
     _loadDictionaryEntries();
     
     _loadCachedMessages();
     
     _preloadMore(limit: _initialHistoryPageSize);

     _startRealtime();
   }

   Future<void> _loadCachedMessages() async {
     try {
       final cachedMessages = await localSeenService.getMessagesWithLocal(widget.recipientId, limit: _initialHistoryPageSize);
       if (cachedMessages.isNotEmpty && mounted) {
         _addMessages(cachedMessages, appendToEnd: false, isNewMessage: false);
         _initialViewportAnchored = true;
       }
     } catch (e) {
       debugPrint('Failed to load cached messages: $e');
     }
   }

  void _startRealtime() {
    final supabase = Supabase.instance.client;

    _messagesChannel = supabase.channel('conversation-${widget.conversationId}');

    _messagesChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: widget.conversationId),
          callback: (payload) {
            try {
              final data = payload.newRecord;

              final messageId = data['id'].toString();

              final alreadyExists = _messages.any((m) => m.id == messageId);

              if (alreadyExists) return;

              final isMe = data['sender_id'] == currentUser.id;

              final message = ChatMessage(
                id: messageId,
                text: data['content'] ?? '',
                isMe: isMe,
                timestamp: DateTime.parse(data['created_at']),
                status: MessageStatus.delivered,
              );

              final shouldAutoScroll = _isNearBottom;

              if (_mergeOwnRealtimeMessage(message)) return;

              _createBubbleController(message.id);

              setState(() {
                _messages.add(message);
                if (!isMe && _partnerTyping && widget.fakeTyping) {
                  _partnerTyping = false;
                } else if (!isMe && !_partnerTyping && widget.fakeTyping) {
                  setState(() {
                    currentFakeTypingTimer?.cancel();
                    currentFakeTypingTimer = null;
                    _partnerTyping = false;
                  });
                }
              });

              widget.onMessageUpdateLocal(message);

              if (shouldAutoScroll) {
                _scrollToBottom(force: true);
              }
            } catch (e) {
              debugPrint('Realtime insert failed: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: widget.conversationId),
          callback: (payload) {
            print("UPDATE message version received: ${payload.newRecord}");

            int messageId = int.parse(payload.newRecord['id'].toString());

            ChatMessage? message = _messages.where((m) => m.id == messageId.toString()).firstOrNull;
            if (message == null) return;

            bool isDeleted = payload.newRecord['deleted_at'] != null;
            if (isDeleted) {
              print("message delete received for messageId=$messageId");
              setState(() {
                _messages.removeWhere((m) => m.id == messageId.toString());
                _disposeBubbleController(messageId.toString());
              });
              return;
            }

            String? newContent = payload.newRecord['content'];
            if (newContent == null || newContent == message.text) return;

            print("message version update received for messageId=$messageId, newContent=$newContent");
            setState(() {
              int index = _messages.indexWhere((m) => m.id == messageId.toString());
              if (index != -1) {
                _messages[index] = ChatMessage(
                  id: message.id,
                  text: newContent,
                  isMe: message.isMe,
                  timestamp: message.timestamp,
                  status: message.status,
                  editedAt: DateTime.parse(payload.newRecord['edited_at']),
                  type: message.type,
                  deletedAt: message.deletedAt,
                  replyToMessageId: message.replyToMessageId,
                );
              }
            });
          },
        )
        .subscribe();
  }

  bool _mergeOwnRealtimeMessage(ChatMessage incoming) {
    if (!incoming.isMe) return false;

    final index = _messages.indexWhere((m) {
      if (!m.isMe) return false;
      if (m.status == MessageStatus.delivered) return false;
      if (m.text != incoming.text) return false;
      final diff = m.timestamp.difference(incoming.timestamp).abs();
      return diff <= const Duration(seconds: 5);
    });

    if (index == -1) return false;

    final old = _messages[index];
    _rekeyBubbleController(old.id, incoming.id);
    setState(() {
      _messages[index] = ChatMessage(
        id: incoming.id,
        text: incoming.text,
        isMe: incoming.isMe,
        timestamp: incoming.timestamp,
        status: MessageStatus.delivered,
        editedAt: incoming.editedAt,
        deletedAt: incoming.deletedAt,
        replyToMessageId: incoming.replyToMessageId,
        type: incoming.type,
      );
    });
    return true;
  }

  Future<ChatRoutePreview?> _previewFutureFor(ChatRouteReference ref) {
    return _previewFutureCache.putIfAbsent(ref.route, () => ChatRoutePreviewResolver.resolve(ref));
  }

  Future<void> _loadDictionaryEntries() async {
    try {
      final entries = await dictionaryRepository.fetchEntries();
      final aliasIndex = await dictionaryRepository.fetchAliasIndex();
      if (!mounted) return;
      setState(() {
        _dictionaryEntriesByTitle = dictionaryRepository.buildTitleAliasIndex(entries, aliasIndex);
      });
    } catch (e) {
      debugPrint('load dictionary entries failed: $e');
    }
  }

  Future<void> _showDictionaryPreview(DictionaryEntry entry) async {
    if (!mounted) return;
    await showDictionaryEntryPreviewSheet(
      context,
      entry: entry,
      onSendToChat: () => _sendDictionaryEntry(entry),
      onOpenQuest: () => context.go(entry.questRoute),
      onOpenDictionary: () => context.go(entry.route),
    );
  }

  Future<void> _sendDictionaryEntry(DictionaryEntry entry) async {
    await _sendMessageText(entry.route);
  }

  Future<void> _openDictionaryPicker() async {
    if (!mounted) return;
    final selected = await showModalBottomSheet<DictionaryEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DictionaryPickerSheet(entriesFuture: dictionaryRepository.fetchEntries(), onSelect: (entry) => Navigator.of(ctx).pop(entry)),
    );
    if (selected != null) {
      await _sendDictionaryEntry(selected);
    }
  }

  Future<String> _uploadImageToCloudinary(Uint8List bytes, {String? filename}) async {
    if (_cloudinaryCloudName.isEmpty) {
      throw StateError('Cloudinary cloud name is not configured.');
    }
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudinaryCloudName/image/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = 'tmp_profile_imgs'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename ?? 'chat_image.jpg'));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw Exception('Cloudinary upload failed (${response.statusCode}): $body');
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final secureUrl = decoded['secure_url']?.toString();
    if (secureUrl == null || secureUrl.isEmpty) {
      throw Exception('Cloudinary response missing secure_url');
    }
    return secureUrl;
  }

  Future<void> _sendImageMarkdown(String imageUrl) async {
    final url = imageUrl.trim();
    if (url.isEmpty) return;
    await _sendMessageText('![image]($url)');
  }

  Future<void> _openAttachmentSheet() async {
    final action = await showChatAttachmentActionSheet(context);
    if (!mounted || action == null) return;

    try {
      switch (action) {
        case ChatAttachmentAction.fileImage:
          final uploadedUrl = await showChatFileImageUploadSheet(context, uploadImage: _uploadImageToCloudinary);
          if (uploadedUrl != null) {
            await _sendImageMarkdown(uploadedUrl);
          }
          break;
        case ChatAttachmentAction.urlImage:
          final imageUrl = await showChatUrlImageUploadSheet(context);
          if (imageUrl != null) {
            await _sendImageMarkdown(imageUrl);
          }
          break;
        case ChatAttachmentAction.cameraImage:
          final uploadedUrl = await showChatCameraImageUploadSheet(context, uploadImage: _uploadImageToCloudinary);
          if (uploadedUrl != null) {
            await _sendImageMarkdown(uploadedUrl);
          }
          break;
        case ChatAttachmentAction.deepLink:
          final route = await showChatDeepLinkBuilderSheet(context);
          if (route != null && route.trim().isNotEmpty) {
            await _sendMessageText(route.trim());
          }
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attachment action failed: $e')));
    }
  }

  List<String> _collectSharedFeedVideoIds() {
    final seen = <String>{};
    final ids = <String>[];
    for (final message in _messages) {
      for (final ref in ChatRoutePreviewResolver.extract(message.text)) {
        if (!ref.uri.path.startsWith('/feed/')) continue;
        final pathId = ref.uri.pathSegments.length > 1 ? ref.uri.pathSegments[1] : '';
        if (pathId.isNotEmpty && seen.add(pathId)) {
          ids.add(pathId);
        }
      }
    }
    return ids;
  }

  Future<List<String>> _loadSharedFeedVideoIds() {
    final cached = _sharedFeedVideoIds;
    if (cached != null) return Future.value(cached);

    final inFlight = _sharedFeedVideoIdsTask;
    if (inFlight != null) return inFlight;

    final task = chatRepository
        .getSharedFeedVideoIdsWith(widget.recipientId)
        .then((ids) {
          final result = ids.isEmpty ? _collectSharedFeedVideoIds() : ids;
          _sharedFeedVideoIds = result;
          return result;
        })
        .catchError((_) {
          final fallback = _collectSharedFeedVideoIds();
          _sharedFeedVideoIds = fallback;
          return fallback;
        })
        .whenComplete(() {
          _sharedFeedVideoIdsTask = null;
        });

    _sharedFeedVideoIdsTask = task;
    return task;
  }

  Future<String> _withChatFeedContext(String route) async {
    final uri = Uri.tryParse(route);
    if (uri == null || !uri.path.startsWith('/feed/')) return route;
    final currentVideoId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
    if (currentVideoId.isEmpty) return route;

    final ids = <String>[currentVideoId, ...await _loadSharedFeedVideoIds()];
    final unique = <String>[];
    final seen = <String>{};
    for (final id in ids) {
      if (seen.add(id)) {
        unique.add(id);
      }
    }
    if (unique.length <= 1) return route;

    final query = Map<String, String>.from(uri.queryParameters);
    query['ids'] = unique.join(',');
    return uri.replace(queryParameters: query).toString();
  }

  Future<void> _openRouteFromMessage(String route) async {
    final targetRoute = await _withChatFeedContext(route);
    if (!mounted) return;

    final uri = Uri.tryParse(targetRoute);
    if (uri != null && uri.path.startsWith('/feed/')) {
      await _openFeedRouteInDialog(uri);
      return;
    }

    context.push(targetRoute);
  }

  Future<void> _openFeedRouteInDialog(Uri uri) async {
    final routeVideoId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
    if (routeVideoId.isEmpty) return;

    final queryIds = (uri.queryParameters['ids'] ?? '').split(',').map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    final orderedIds = <String>[routeVideoId, ...queryIds];

    final uniqueIds = <String>[];
    final seen = <String>{};
    for (final id in orderedIds) {
      if (seen.add(id)) {
        uniqueIds.add(id);
      }
    }

    List<Video> videos = [];
    if (uniqueIds.isNotEmpty) {
      final fetched = await videoRepo.fetchVideosByIds(uniqueIds);
      final byId = {for (final video in fetched) video.id: video};
      videos = [
        for (final id in uniqueIds)
          if (byId[id] != null) byId[id]!,
      ];
    }

    if (videos.isEmpty) {
      final single = await videoRepo.getVideoByIdSupabase(routeVideoId);
      if (single == null || !mounted) return;
      videos = [single];
    }

    if (!mounted) return;
    final index = videos.indexWhere((video) => video.id == routeVideoId);
    await openVideoPlayer(context: context, listedVideos: videos, videoIndex: index >= 0 ? index : 0);
  }

  bool preloading = false;

  Future<void> _loadHistoryPermission() async {
    try {
      final allowed = await widget.canViewMessageHistory();
      if (!mounted) return;
      setState(() => _canViewMessageHistory = allowed);
    } catch (_) {}
  }

  Future<void> _preloadMore({int limit = 30}) async {
    if (!moreMessagesAvailable || preloading) return;
    preloading = true;
    if (mounted) setState(() {});

    try {
      final wasEmpty = _messages.isEmpty;
      final loadedMessages = await widget.loadMoreMessages(limit, currentMessageCursor);
      if (!mounted) return;

      if (loadedMessages.isEmpty) {
        moreMessagesAvailable = false;
        return;
      } else if (loadedMessages.length < limit) {
        moreMessagesAvailable = false;
      }

      loadedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _addMessages(loadedMessages, appendToEnd: false, isNewMessage: false);
      currentMessageCursor = loadedMessages.first.timestamp;
      if (wasEmpty) {
        _initialViewportAnchored = true;
      }
    } catch (e) {
      debugPrint('preload messages failed: $e');
    } finally {
      preloading = false;
      if (mounted) setState(() {});
    }
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    return _scrollController.offset <= _bottomScrollThreshold;
  }

  AnimationController _ensureBubbleController(String id, {bool animate = true}) {
    final existing = _bubbleControllers[id];
    if (existing != null) return existing;
    final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _bubbleControllers[id] = ctrl;
    if (animate) {
      ctrl.forward();
    } else {
      ctrl.value = 1.0;
    }
    return ctrl;
  }

  AnimationController _createBubbleController(String id, {bool animate = true}) {
    return _ensureBubbleController(id, animate: animate);
  }

  void _rekeyBubbleController(String oldId, String newId) {
    if (oldId == newId) return;
    final ctrl = _bubbleControllers.remove(oldId);
    if (ctrl != null) {
      _bubbleControllers[newId] = ctrl;
    }
  }

  void _disposeBubbleController(String id) {
    final ctrl = _bubbleControllers.remove(id);
    ctrl?.dispose();
  }

  void onReceiveMessage(String text) {
    final shouldAutoScroll = _isNearBottom;
    if (_partnerTyping) {
      setState(() => _partnerTyping = false);
    }
    _addMessage(text: text, isMe: false, autoScroll: shouldAutoScroll);
  }

  void setPartnerTyping(bool typing) {
    setState(() => _partnerTyping = typing);
    if (typing && _isNearBottom) {
      _scrollToBottom(force: true);
    }
  }

  int _addMessage({
    required String text,
    required bool isMe,
    Future<void>? sendingFuture,
    bool animated = true,
    bool appendToEnd = true,
    bool isNewMessage = true,
    bool autoScroll = false,
    DateTime? createdAt,
    String? id,
    bool cacheLocally = true,
  }) {
    if (!mounted) return -1;
    final messageId = id ?? (createdAt ?? DateTime.now()).millisecondsSinceEpoch.toString();
    if (isNewMessage && cacheLocally) {
      widget.onMessageUpdateLocal(ChatMessage(id: messageId, text: text, isMe: isMe, timestamp: createdAt ?? DateTime.now()));
    }
    final msg = ChatMessage(
      id: messageId,
      text: text,
      isMe: isMe,
      timestamp: createdAt ?? DateTime.now(),
      status: isMe ? MessageStatus.sending : MessageStatus.delivered,
    );
    _createBubbleController(msg.id, animate: animated);
    setState(() {
      if (appendToEnd) {
        _messages.add(msg);
      } else {
        _messages.insert(0, msg);
      }
      if (!autoScroll && !_showScrollDown) {
        _showScrollDown = true;
      }
    });
    _sharedFeedVideoIds = null;
    if (autoScroll) {
      _scrollToBottom(force: true);
    }

    if (isMe) {
      if (sendingFuture == null) {
        if (widget.fakeTyping) {
          startFakeTyping(Duration(seconds: Random().nextInt(6)));
        }

        setState(() => msg.status = MessageStatus.sent);
      }
      sendingFuture
          ?.then((val) {
            if (mounted) {
              setState(() => msg.status = MessageStatus.delivered);
            }

            if (widget.fakeTyping) {
              startFakeTyping(Duration(seconds: Random().nextInt(3) + 1));
            }
          })
          .catchError((e) {
            if (mounted) {
              setState(() => msg.status = MessageStatus.sent);
            }
            debugPrint('send message failed: $e');
          });
    }
    return _messages.indexWhere((m) => m.id == msg.id);
  }

  Timer? currentFakeTypingTimer;

  Future<void> startFakeTyping([Duration? offset]) async {
    if (offset != null) {
      currentFakeTypingTimer = Timer(offset, () async {
        await startFakeTyping();
        WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
          currentFakeTypingTimer?.cancel();
          currentFakeTypingTimer = null;
        });
      });
    } else {
      if (!mounted) return;

      setState(() => _partnerTyping = true);
    }
  }

  void _addMessages(List<ChatMessage> messages, {bool appendToEnd = true, bool isNewMessage = true}) {
    if (!mounted) return;
    if (messages.isEmpty) return;

    final existingIndexById = <String, int>{for (int i = 0; i < _messages.length; i++) _messages[i].id: i};

    final newMessages = <ChatMessage>[];
    var didUpdateExisting = false;

    for (final element in messages) {
      final normalized = ChatMessage(
        id: element.id,
        text: element.text,
        isMe: element.isMe,
        timestamp: element.timestamp,
        status: element.isMe ? MessageStatus.sent : MessageStatus.delivered,
        editedAt: element.editedAt,
        deletedAt: element.deletedAt,
        replyToMessageId: element.replyToMessageId,
        type: element.type,
      );

      final existingIndex = existingIndexById[normalized.id];
      if (existingIndex != null) {
        final current = _messages[existingIndex];
        final shouldUpdate =
            current.text != normalized.text ||
            current.timestamp != normalized.timestamp ||
            current.editedAt != normalized.editedAt ||
            current.deletedAt != normalized.deletedAt ||
            current.replyToMessageId != normalized.replyToMessageId ||
            current.type != normalized.type ||
            current.status != normalized.status;
        if (shouldUpdate) {
          _messages[existingIndex] = normalized;
          didUpdateExisting = true;
        }
        if (isNewMessage) {
          widget.onMessageUpdateLocal(normalized);
        }
        continue;
      }

      newMessages.add(normalized);
      if (isNewMessage) {
        widget.onMessageUpdateLocal(normalized);
      }
    }

    if (newMessages.isEmpty && !didUpdateExisting) return;

    for (final message in newMessages) {
      _createBubbleController(message.id, animate: false);
    }

    setState(() {
      if (newMessages.isNotEmpty) {
        if (appendToEnd) {
          _messages.addAll(newMessages);
        } else {
          _messages.insertAll(0, newMessages);
        }
      }
    });
    _sharedFeedVideoIds = null;
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_editingMessageId != null) {
      final index = _messages.indexWhere((m) => m.id == _editingMessageId);
      if (index == -1) {
        setState(() => _editingMessageId = null);
        return;
      }
      final original = _messages[index];
      if (text == original.text) {
        setState(() {
          _editingMessageId = null;
          _textController.clear();
        });
        return;
      }
      try {
        final updated = await widget.onEditOwnMessage(original, text);
        if (!mounted) return;
        setState(() {
          _messages[index] = ChatMessage(
            id: updated.id,
            text: updated.text,
            isMe: updated.isMe,
            timestamp: updated.timestamp,
            status: original.status,
            editedAt: updated.editedAt,
            deletedAt: updated.deletedAt,
          );
          _editingMessageId = null;
          _textController.clear();
        });
        widget.onMessageUpdateLocal(updated);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to edit message: $e')));
      }
      return;
    }

    _textController.clear();
    await _sendMessageText(text);
  }

  Future<void> _sendMessageText(String text) async {
    HapticFeedback.lightImpact();

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    int tempIndex = _addMessage(text: text, isMe: true, isNewMessage: true, id: tempId, autoScroll: true, cacheLocally: false);

    try {
      final serverMessage = await widget.onSend(text, () {
        if (context.mounted) {
          routerConfig.go('/login-force');
        }
      });
      if (mounted) {
        widget.onMessageUpdateLocal(serverMessage);
        int existingIndex = _messages.indexWhere((m) => m.id == serverMessage.id);
        int tempIndex = _messages.indexWhere((m) => m.id == tempId);

        if (existingIndex != -1) {
          setState(() {
            if (tempIndex != -1) {
              _messages.removeAt(tempIndex);
              _disposeBubbleController(tempId);
              if (existingIndex > tempIndex) {
                existingIndex -= 1;
              }
            }

            _messages[existingIndex] = ChatMessage(
              id: serverMessage.id,
              text: serverMessage.text,
              isMe: serverMessage.isMe,
              timestamp: serverMessage.timestamp,
              status: MessageStatus.delivered,
              editedAt: serverMessage.editedAt,
              deletedAt: serverMessage.deletedAt,
              replyToMessageId: serverMessage.replyToMessageId,
              type: serverMessage.type,
            );
          });
          return;
        }

        if (tempIndex != -1) {
          _rekeyBubbleController(tempId, serverMessage.id);
          setState(() {
            _messages[tempIndex] = ChatMessage(
              id: serverMessage.id,
              text: serverMessage.text,
              isMe: serverMessage.isMe,
              timestamp: serverMessage.timestamp,
              status: MessageStatus.delivered,
              editedAt: serverMessage.editedAt,
              deletedAt: serverMessage.deletedAt,
              replyToMessageId: serverMessage.replyToMessageId,
              type: serverMessage.type,
            );
          });
        }
      }
    } on ContentModerationViolationException catch (e) {
      if (mounted) {
        showSnackBar(context, e.message);
        setState(() {
          _messages.removeAt(tempIndex);
        });
      }
    } catch (e) {
      debugPrint('send message failed: $e');
      if (mounted) {
        final index = _messages.indexWhere((m) => m.id == tempId);
        if (index != -1) {
          setState(() {
            _messages[index].status = MessageStatus.sent;
          });
        }
      }
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    try {
      await widget.onDeleteOwnMessage(message);
      if (!mounted) return;
      setState(() => _messages.removeWhere((m) => m.id == message.id));
      _disposeBubbleController(message.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete message: $e')));
    }
  }

  Future<void> _showMessageHistory(ChatMessage message) async {
    if (!_canViewMessageHistory && !message.isEdited) return;
    try {
      final versions = await widget.onLoadMessageVersions(message);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Message edit history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: versions.isEmpty
                      ? const Center(child: Text('No versions found'))
                      : ListView.builder(
                          itemCount: versions.length,
                          itemBuilder: (context, i) {
                            final version = versions[i];
                            return ListTile(
                              title: Text(version.content),
                              subtitle: Text('v${version.versionNo} • ${version.changeType} • ${version.editedAt.toLocal()}'),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load history: $e')));
    }
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    if (!message.isMe && !_canViewMessageHistory && !message.isEdited) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (message.isMe)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit message'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _editingMessageId = message.id;
                    _textController.text = message.text;
                    _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
                  });
                  _focusNode.requestFocus();
                },
              ),
            if (message.isMe)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete message', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(message);
                },
              ),
            if (_canViewMessageHistory || message.isEdited)
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('View edit history'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMessageHistory(message);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _isTyping) setState(() => _isTyping = hasText);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.offset <= _bottomScrollThreshold;
    if (!atBottom && !_showScrollDown) {
      setState(() => _showScrollDown = true);
    } else if (atBottom && _showScrollDown) {
      setState(() => _showScrollDown = false);
    }
    final remaining = _scrollController.position.maxScrollExtent - _scrollController.offset;
    if (_scrollController.offset > _bottomScrollThreshold) {
      _historyLoadArmedByUserScroll = true;
    }
    if (_initialViewportAnchored && _historyLoadArmedByUserScroll && remaining <= _historyLoadTopThreshold) {
      _preloadMore(limit: _historyPageSize);
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (!force && !_isNearBottom) return;
        final target = _scrollController.position.minScrollExtent;
        if (force) {
          _scrollController.jumpTo(target);
        } else {
          _scrollController.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      }
    });
  }

  Widget _buildMessageSkeleton(ColorScheme cs) {
    final radius = BorderRadius.circular(context.uiRadiusLg);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ShimmerBlock(width: 220, height: 40, borderRadius: radius, color: cs.surfaceContainerHigh),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ShimmerBlock(width: 180, height: 36, borderRadius: radius, color: cs.surfaceContainerHigh),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ShimmerBlock(width: 240, height: 54, borderRadius: radius, color: cs.surfaceContainerHigh),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ShimmerBlock(width: 200, height: 40, borderRadius: radius, color: cs.surfaceContainerHigh),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ShimmerBlock(width: 160, height: 36, borderRadius: radius, color: cs.surfaceContainerHigh),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: _buildAppBar(theme, cs),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(child: _buildMessageList(theme, cs)),
              if (_partnerTyping) _buildTypingIndicator(cs),
              _buildInputBar(theme, cs),
            ],
          ),
          // Scroll-to-bottom FAB
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            bottom: _showScrollDown ? 80 : -60,
            right: 16,
            child: _ScrollDownButton(onTap: () => _scrollToBottom(force: true), colorScheme: cs),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, ColorScheme cs) {
    return AppBar(
      backgroundColor: cs.surfaceContainer,
      elevation: 0,
      /*shape: const RoundedRectangleBorder( //fixxme
        borderRadius: BorderRadiusGeometry.only(bottomLeft: Radius.circular(context.uiRadiusMd), bottomRight: Radius.circular(context.uiRadiusMd)),
      ),*/
      scrolledUnderElevation: 0,
      toolbarHeight: kToolbarHeight,
      systemOverlayStyle: SystemUiOverlayStyle(statusBarBrightness: theme.brightness == Brightness.dark ? Brightness.dark : Brightness.light),
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cs.onSurface),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) {
              return ProfileScreen(
                initialProfile: widget.user,
                ownProfile: widget.user.id == currentUser.id,
                hasBackButton: true,
                initialFollowed: localSeenService.isFollowing(widget.user.id),
                onFollowChange: (bool followed) {},
              );
            },
          ),
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(context.uiRadiusLg), bottomRight: Radius.circular(context.uiRadiusLg)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
          child: Row(
            children: [
              MessageAvatarWidget(
                name: widget.recipientName ?? '',
                imageUrl: widget.recipientAvatarUrl,
                isOnline: widget.isOnline,
                radius: 18,
                colorScheme: cs,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.recipientName ?? '',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
                  ),
                  Text(
                    widget.isOnline ? 'Active now' : 'Offline',
                    style: TextStyle(fontSize: 11, color: widget.isOnline ? cs.tertiary : cs.outline, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        Center(
          child: IconButton(
            icon: Icon(Icons.videocam_rounded, color: cs.onSurface),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) {
                    return CallingApp(
                      name: widget.recipientName ?? "Unknown User",
                      profileImageUrl: widget.recipientAvatarUrl ?? createUserProfileImageUrl(widget.recipientName ?? ""),
                    );
                  },
                ),
              );
            },
          ),
        ),
        /*        IconButton(
          icon: Icon(Icons.info_outline_rounded, color: cs.onSurface),
          onPressed: () {},
        ),*/
      ],
    );
  }

  Widget _buildMessageList(ThemeData theme, ColorScheme cs) {
    final isLoading = _messages.isEmpty && preloading;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: isLoading
          ? KeyedSubtree(key: const ValueKey('chat_skeleton'), child: _buildMessageSkeleton(cs))
          : KeyedSubtree(
              key: const ValueKey('chat_messages'),
              child: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  // Only load older pages after a deliberate upward user scroll.
                  if (notification.direction != ScrollDirection.idle && _scrollController.hasClients && _scrollController.offset > _bottomScrollThreshold) {
                    _historyLoadArmedByUserScroll = true;
                  }
                  return false;
                },
                child: GestureDetector(
                  onTap: () => _focusNode.unfocus(),
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final index = _messages.length - 1 - i;
                      final msg = _messages[index];
                      final prevMsg = index > 0 ? _messages[index - 1] : null;
                      final nextMsg = index < _messages.length - 1 ? _messages[index + 1] : null;

                      final showAvatar = !msg.isMe && (nextMsg == null || nextMsg.isMe || _isNewGroup(msg, nextMsg));
                      final showTimestamp = nextMsg == null || msg.timestamp.difference(nextMsg.timestamp).abs() > const Duration(minutes: 10);

                      final ctrl = _bubbleControllers[msg.id] ?? _ensureBubbleController(msg.id, animate: false);

                      return MessageBubble(
                        key: ValueKey(msg.id),
                        message: msg,
                        showAvatar: showAvatar,
                        showTimestamp: showTimestamp,
                        isFirst: prevMsg == null || prevMsg.isMe != msg.isMe,
                        isLast: nextMsg == null || nextMsg.isMe != msg.isMe,
                        animationController: ctrl,
                        colorScheme: cs,
                        theme: theme,
                        recipientName: widget.recipientName ?? '',
                        recipientAvatarUrl: widget.recipientAvatarUrl,
                        onLongPress: () => _showMessageActions(msg),
                        onRouteTap: _openRouteFromMessage,
                        onDictionaryTap: _showDictionaryPreview,
                        previewFutureFor: _previewFutureFor,
                        dictionaryEntriesByTitle: _dictionaryEntriesByTitle,
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }

  bool _isNewGroup(ChatMessage a, ChatMessage b) {
    return b.timestamp.difference(a.timestamp).abs() > const Duration(minutes: 5);
  }

  Widget _buildTypingIndicator(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 56, bottom: 4, right: 80),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TypingBubble(controller: _typingDotController, colorScheme: cs),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : max(MediaQuery.of(context).padding.bottom, 12),
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3), width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editingMessageId != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(context.uiRadiusSm),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 16, color: cs.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Editing message',
                      style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _editingMessageId = null;
                        _textController.clear();
                      });
                    },
                    child: Icon(Icons.close_rounded, size: 18, color: cs.onSecondaryContainer),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _InputIconButton(icon: Icons.add_circle_outline_rounded, color: cs.onSurfaceVariant, onTap: _openAttachmentSheet),
              const SizedBox(width: 6),
              _InputIconButton(icon: Icons.menu_book_outlined, color: cs.onSurfaceVariant, onTap: _openDictionaryPicker),
              const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(_isTyping ? 22 : 24),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: _isTyping ? 0.7 : 0.4), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Focus(
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                !HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) &&
                                !HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight)) {
                              _sendMessage();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: _textController,
                            onSubmitted: (value) => _sendMessage(),
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            style: TextStyle(color: cs.onSurface, fontSize: 15, height: 1.4),
                            decoration: InputDecoration(
                              hintText: _editingMessageId == null ? 'Message…' : 'Edit message…',
                              hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 15),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: _isTyping
                    ? _SendButton(key: const ValueKey('send'), onTap: _sendMessage, colorScheme: cs)
                    : _InputIconButton(key: const ValueKey('mic'), icon: Icons.mic_none_rounded, color: cs.onSurfaceVariant, onTap: () {}),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();

    _scrollController.dispose();
    _typingDotController.dispose();

    for (var element in _bubbleControllers.values) {
      element.dispose();
    }

    _bubbleControllers.clear();

    _textController.dispose();
    _focusNode.dispose();

    super.dispose();
  }
}

class TypingBubble extends StatelessWidget {
  final AnimationController controller;
  final ColorScheme colorScheme;

  const TypingBubble({super.key, required this.controller, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final radiusLg = context.uiRadiusLg;
    final radiusSm = context.uiRadiusSm;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          margin: EdgeInsets.only(bottom: context.uiSpace(4)),
          padding: EdgeInsets.symmetric(horizontal: context.uiSpace(16), vertical: context.uiSpace(12)),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(radiusSm),
              topRight: Radius.circular(radiusLg),
              bottomLeft: Radius.circular(radiusLg),
              bottomRight: Radius.circular(radiusLg),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return _TypingDot(index: i, controllerValue: controller.value, color: cs.onSurfaceVariant);
            }),
          ),
        );
      },
    );
  }
}

class _TypingDot extends StatelessWidget {
  final int index;
  final double controllerValue;
  final Color color;

  const _TypingDot({required this.index, required this.controllerValue, required this.color});

  @override
  Widget build(BuildContext context) {
    final delay = index * 0.18;

    final t = ((controllerValue - delay) % 1.0).clamp(0.0, 1.0);

    final curve = Curves.easeInOutCubicEmphasized.transform(sin(t * pi));

    final translateY = -curve * 5;
    final scale = 0.85 + (curve * 0.35);
    final opacity = 0.35 + (curve * 0.65);

    return Padding(
      padding: EdgeInsets.only(right: index < 2 ? context.uiSpace(4) : 0),
      child: Transform.translate(
        offset: Offset(0, translateY + 3.5),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: context.uiSpace(7),
              height: context.uiSpace(7),
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _SendButton({super.key, required this.onTap, required this.colorScheme});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120), lowerBound: 0.0, upperBound: 1.0);
    _scaleAnim = Tween(begin: 1.0, end: 0.88).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final buttonSize = context.uiSpace(42);
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45), width: context.uiBorderWidth),
          ),
          child: Icon(Icons.send_rounded, color: cs.onPrimary, size: 20),
        ),
      ),
    );
  }
}

class _ScrollDownButton extends StatelessWidget {
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _ScrollDownButton({required this.onTap, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final size = context.uiSpace(36);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant, width: context.uiBorderWidth),
        ),
        child: Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurface, size: 20),
      ),
    );
  }
}

class _InputIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _InputIconButton({super.key, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = context.uiSpace(36);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: color, size: context.uiSpace(24)),
      ),
    );
  }
}
