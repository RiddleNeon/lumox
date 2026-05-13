// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:lumox/logic/chat/chat_message.dart';
import 'package:lumox/logic/local_storage/local_seen_service.dart';
import 'package:lumox/tools/supabase_tests/supabase_login_test.dart';
import 'package:lumox/ui/misc/avatar.dart';
import 'package:lumox/ui/screens/chat/chat_screen.dart';
import 'package:lumox/ui/widgets/loading/shimmer_block.dart';

import '../../../base_logic.dart';
import '../../../logic/chat/chat.dart';
import '../../../util/misc/time_formatting.dart';
import '../../theme/theme_ui_values.dart';
import 'chat_route_preview.dart';

GlobalKey<ChatManagingScreenState> chatManagingScreenKey = GlobalKey();

class ChatManagingScreen extends StatefulWidget {
  final Future<({List<Chat> result, int? newCurrent})> Function(int? current) preloadMoreChats;
  final String? initialChatPartnerId;

  const ChatManagingScreen({super.key, required this.preloadMoreChats, this.initialChatPartnerId});

  @override
  State<ChatManagingScreen> createState() => ChatManagingScreenState();
}

class ChatManagingScreenState extends State<ChatManagingScreen> {
  late final ScrollController _scrollController;
  final List<Chat> chats = [];

  int? currentLastIndex;

  @override
  void initState() {
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) => _preload());
    super.initState();
  }

  bool noMoreChats = false;
  bool loading = true;
  bool _handledInitialChat = false;
  String? _lastHandledDeepLinkPartnerId;

  void _onScroll() async {
    if (_scrollController.offset >= _scrollController.position.maxScrollExtent - 60 && !loading && !noMoreChats) {
      preload();
    }
  }
  
  void preload(){
    if (loading) return;
    loading = true;
    _preload();
  }

  void _preload() async {
    try {
      final preloadedChatsResult = await widget.preloadMoreChats(currentLastIndex);
      currentLastIndex = preloadedChatsResult.newCurrent;
      final preloadedChats = preloadedChatsResult.result;
      chats.addAll(preloadedChats);
      reSortChats();
      if (mounted) {
        setState(() {});
      }
      if (preloadedChats.isEmpty || currentLastIndex == null) {
        noMoreChats = true;
      }
      await _tryOpenInitialChat();
    } finally {
      loading = false;
    }
  }

  Future<void> _tryOpenInitialChat() async {
    final partnerId = widget.initialChatPartnerId;
    if (_handledInitialChat || partnerId == null || partnerId.isEmpty) return;
    if (_lastHandledDeepLinkPartnerId == partnerId) return;
    _handledInitialChat = true;
    _lastHandledDeepLinkPartnerId = partnerId;

    Chat? chat;
    for (final item in chats) {
      if (item.partnerId == partnerId) {
        chat = item;
        break;
      }
    }

    if (chat == null) {
      try {
        final partner = await userRepository.getUser(partnerId);
        if (!mounted) return;
        chat = Chat(
          partnerId: partner.id,
          partnerProfileImageUrl: partner.profileImageUrl,
          partnerName: partner.displayName,
          lastMessage: '',
          lastMessageAt: null,
          lastMessageByMe: true,
          createdAt: DateTime.now(),
        );
        chats.insert(0, chat);
        setState(() {});
      } catch (_) {
        _handledInitialChat = false;
        return;
      }
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openChat(chat!, (message) => onMessageUpdate(chat!, message));
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatManagingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialChatPartnerId == widget.initialChatPartnerId) return;
    if (widget.initialChatPartnerId == null || widget.initialChatPartnerId!.isEmpty) return;
    _handledInitialChat = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tryOpenInitialChat();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text("Chats", textAlign: TextAlign.center,),
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        centerTitle: true,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadiusGeometry.only(bottomLeft: Radius.circular(context.uiRadiusMd), bottomRight: Radius.circular(context.uiRadiusMd)),
        ),
      ),
      body: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: _buildChatList(chats)),
    );
  }

  void onMessageUpdate(Chat chat, ChatMessage message) async {
    if(message.timestamp.isBefore(chat.lastMessageAt ?? chat.createdAt)) {
      return;
    }
    
    localSeenService.sendMessageLocal(chat, message);

    if(message.isMe) {
      await supabaseClient.functions.invoke(
          'ai-bots',
          body: {
            "conversation_id": chat.conversationId
          }
      );
    }

    
    setState(() {
      final manageableChat = chats.firstWhere((c) => c.partnerId == chat.partnerId, orElse: () => chat);
      manageableChat.lastMessage = message.text;
      manageableChat.lastMessageAt = message.timestamp;
      manageableChat.lastMessageByMe = message.isMe;
    });
  }

  String _formatLastMessage(Chat chat) {
    String formattedMessage = chat.lastMessage;
    if (ChatRoutePreviewResolver.isPureRouteMessage(formattedMessage)) {
      final uri = Uri.tryParse(formattedMessage.trim());
      if (uri != null) {
        if (uri.path.startsWith('/feed/')) formattedMessage = '▶ Shared a video';
        else if (uri.path.startsWith('/quests')) formattedMessage = '🗺 Shared a quest';
        else if (uri.path.startsWith('/themes')) formattedMessage = '🎨 Shared a theme';
        else if (uri.path.startsWith('/search')) formattedMessage = '🔍 Shared a search';
        else if (uri.path.startsWith('/chat')) formattedMessage = '💬 Shared a chat';
        else formattedMessage = '🔗 Shared a link';
      }
    }
    return formattedMessage;
  }

  List<Chat> _highlightedChats(List<Chat> chats) {
    if (chats.isEmpty) return const [];
    final sorted = [...chats];
    sorted.sort((a, b) {
      final aTime = (a.lastMessageAt ?? a.createdAt).toLocal();
      final bTime = (b.lastMessageAt ?? b.createdAt).toLocal();
      return bTime.compareTo(aTime);
    });
    return sorted.take(3).toList();
  }

  Widget _buildHighlightsSection(List<Chat> chats) {
    final theme = Theme.of(context);
    final highlights = _highlightedChats(chats);
    if (highlights.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Top chats', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Recent', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 6),
            itemCount: highlights.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final chat = highlights[index];
              return SizedBox(width: 220, child: _buildHighlightCard(chat));
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildHighlightCard(Chat chat) {
    final theme = Theme.of(context);
    final timeString = formatTime(chat.lastMessageAt ?? chat.createdAt);
    final formattedMessage = _formatLastMessage(chat);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openChat(chat, (message) => onMessageUpdate(chat, message)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Avatar(imageUrl: chat.partnerProfileImageUrl, name: chat.partnerName, colorScheme: theme.colorScheme),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        chat.partnerName,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 32),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [Text(
                        formattedMessage.isEmpty ? 'Start a conversation' : formattedMessage.substring(0, formattedMessage.length > 60 ? 60 : formattedMessage.length),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),]
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(timeString, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
                    if (!chat.lastMessageByMe)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: theme.colorScheme.tertiary, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(context.uiRadiusLg);
    return ListView(
      controller: _scrollController,
      children: [
        Text('Top chats', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return SizedBox(
                width: 220,
                child: ShimmerBlock(borderRadius: radius),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        Text('All chats', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...List.generate(5, (_) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ShimmerBlock(height: 78, borderRadius: radius),
          );
        }),
      ],
    );
  }

  Widget _buildChatList(List<Chat> chats) {
    if (loading && chats.isEmpty) {
      return _buildLoadingSkeleton();
    }

    if (chats.isEmpty) {
      return const Center(child: Text("No Chats yet!"));
    }

    final showLoadingFooter = loading && chats.isNotEmpty;
    final itemCount = chats.length + 1 + (showLoadingFooter ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHighlightsSection(chats),
              Text('All chats', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
            ],
          );
        }

        final chatIndex = index - 1;
        if (chatIndex < chats.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildChatEntry(chats[chatIndex], (message) => onMessageUpdate(chats[chatIndex], message)),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ShimmerBlock(height: 72, borderRadius: BorderRadius.circular(context.uiRadiusLg)),
        );
      },
    );
  }

  Widget _buildChatEntry(Chat chat, void Function(ChatMessage) onMessageUpdate) {
    final theme = Theme.of(context);

    final lastMessageTime = chat.lastMessageAt ?? chat.createdAt;
    final timeString = formatTime(lastMessageTime);

    final formattedMessage = _formatLastMessage(chat);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(context.uiRadiusLg),
          onTap: () => _openChat(chat, onMessageUpdate),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Avatar(imageUrl: chat.partnerProfileImageUrl, name: chat.partnerName, colorScheme: theme.colorScheme),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.partnerName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      Text(
                        "${chat.lastMessageByMe ? "You: " : ""}$formattedMessage",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: chat.lastMessageByMe ? FontWeight.w400 : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(timeString, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
                    const SizedBox(height: 6),

                    if (!chat.lastMessageByMe)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: theme.colorScheme.tertiary, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void reSortChats() {
    chats.sort((a, b) {
      final aTime = (a.lastMessageAt ?? a.createdAt).toLocal();
      final bTime = (b.lastMessageAt ?? b.createdAt).toLocal();
      return bTime.compareTo(aTime);
    });
  }

  void _openChat(Chat chat, void Function(ChatMessage) onMessageUpdate) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) => buildMessagingScreen(chat, onMessageUpdate),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
          return ClipRect(
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );

    setState(() {
      reSortChats();
    });
  }
}

Chat? currentOpenChat;
GlobalObjectKey<MessagingScreenState>? currentOpenChatScreenKey;

Widget buildMessagingScreen(Chat chat, void Function(ChatMessage) onMessageUpdate) {
  currentOpenChatScreenKey = GlobalObjectKey('chat${currentUser.id}-${chat.partnerId}-${DateTime.now().millisecondsSinceEpoch}');
  currentOpenChat = chat;
  return FutureBuilder(
    future: userRepository.getUser(chat.partnerId),
    builder: (context, asyncSnapshot) {
      if (!asyncSnapshot.hasData) {
        return const _MessagingScreenSkeleton();
      }

      return MessagingScreen(
        key: currentOpenChatScreenKey,
        user: asyncSnapshot.data!,
        onMessageUpdateLocal: onMessageUpdate,
        canViewMessageHistory: () => chatRepository.canViewMessageHistory(),
        onLoadMessageVersions: (message) => chatRepository.getMessageVersions(message.id),
        onEditOwnMessage: (message, newText) async {
          final updated = await chatRepository.editMessage(otherUserId: chat.partnerId, messageId: message.id, newText: newText);
          onMessageUpdate(updated);
          return updated;
        },
        onDeleteOwnMessage: (message) async {
          await chatRepository.deleteMessage(otherUserId: chat.partnerId, messageId: message.id);
        },
        onSend: (message) async {
          chatManager.addChat(chat, replaceExisting: false);
          final serverMsg = await chatRepository.sendNotification(
            chat: chat,
            message: ChatMessage(id: "${chat.partnerId}-${DateTime.now().microsecondsSinceEpoch}", text: message, isMe: true, timestamp: DateTime.now()),
          );
          return serverMsg;
        },
        loadMoreMessages: (int limit, DateTime? lastVisibleMessage) async {
          print("Loading more messages for chat ${chat.partnerId} with offset $lastVisibleMessage and limit $limit");
          return chatRepository.getMessagesWith(chat.partnerId, startOffset: lastVisibleMessage, limit: limit);
        }, conversationId: chat.conversationId!,
      );
    },
  );
}

class _MessagingScreenSkeleton extends StatelessWidget {
  const _MessagingScreenSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainer,
        elevation: 0,
        title: const Text('Loading chat…'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            ShimmerBlock(height: 60, borderRadius: BorderRadius.circular(18)),
            const SizedBox(height: 12),
            ShimmerBlock(height: 60, borderRadius: BorderRadius.circular(18)),
            const SizedBox(height: 12),
            ShimmerBlock(height: 60, borderRadius: BorderRadius.circular(18)),
            const Spacer(),
            ShimmerBlock(height: 54, borderRadius: BorderRadius.circular(999)),
          ],
        ),
      ),
    );
  }
}
