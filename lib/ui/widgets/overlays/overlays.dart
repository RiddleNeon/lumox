import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lumox/logic/chat/chat.dart';
import 'package:lumox/logic/chat/chat_message.dart';
import 'package:lumox/logic/local_storage/local_seen_service.dart';
import 'package:lumox/logic/repositories/video_repository.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/ui/router/deep_link_builder.dart';
import 'package:lumox/ui/screens/comment_overlay.dart';
import 'package:lumox/ui/widgets/overlays/pause_indicator.dart';
import 'package:lumox/ui/widgets/overlays/share_button.dart';
import 'package:lumox/ui/widgets/overlays/video_info_overlay.dart';

import '../../../base_logic.dart';
import '../../screens/auth_screen.dart';
import 'comment_button.dart';
import 'dislike_button.dart';
import 'like_button.dart';

class PageOverlay extends StatefulWidget {
  final TickerProvider provider;
  final Video video;
  final int index;

  final bool initiallyLiked;
  final bool initiallyDisliked;

  final void Function(bool isDisliked)? onDislikeChanged;
  final void Function(bool isLiked)? onLikeChanged;
  final void Function(bool hasShared)? onShareChanged;
  final void Function(bool hasSaved)? onSaveChanged;
  final void Function(bool hasCommented)? onCommentChanged;
  final VoidCallback onTogglePause;
  final bool isPaused;

  const PageOverlay({
    super.key,
    required this.provider,
    required this.video,
    required this.index,
    this.onLikeChanged,
    this.onDislikeChanged,
    this.onShareChanged,
    this.onSaveChanged,
    this.onCommentChanged,
    required this.initiallyLiked,
    required this.initiallyDisliked,
    required this.onTogglePause,
    required this.isPaused,
  });

  @override
  State<PageOverlay> createState() => _PageOverlayState();
}

class _PageOverlayState extends State<PageOverlay> {
  late bool lastLiked = widget.initiallyLiked;
  late bool lastDisliked = widget.initiallyDisliked;
  late bool liked = widget.initiallyLiked;
  late bool disliked = widget.initiallyDisliked;

  Set<ShareContact> _shareContacts = const {};
  final Map<String, Chat> _chatByPartnerId = {};
  bool _isShareMenuExpanded = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (_isShareMenuExpanded) return;
            widget.onTogglePause();
          },
          child: const SizedBox.expand(),
        ),
        Positioned.fill(
          child: Center(
            child: PauseIndicator(
              isPaused: widget.isPaused,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 8,
            children: [
              LikeButton(provider: widget.provider, initiallyLiked: liked, onLikeChanged: _onLikeChanged),
              DislikeButton(initiallyDisliked: disliked, onDislikeChanged: _onDislikeChanged),
              CommentButton(onComment: _onCommentButtonPressed),
              ShareButton(
                shareUrl: DeepLinkBuilder.feed(videoId: widget.video.id),
                loadContacts: () async {
                  await _prepareShareContacts();
                  return _shareContacts;
                },
                onShared: () => widget.onShareChanged?.call(true),
                onShareToContact: _shareToContact,
                onExpandedChanged: (expanded) {
                  if (!mounted) return;
                  setState(() {
                    _isShareMenuExpanded = expanded;
                  });
                },
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: FractionallySizedBox(
            heightFactor: 0.3,
            alignment: Alignment.bottomCenter,
            child: Transform.scale(scale: 1.005, child: VideoInfoOverlay(video: widget.video)),
          ),
        ),
      ],
    );
  }

  Future<void> _prepareShareContacts() async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final currentVideoLink = DeepLinkBuilder.feed(videoId: widget.video.id);
    final chats = localSeenService.getChats();
    final contacts = <ShareContact>{};
    final chatMap = <String, Chat>{};

    for (final chat in chats) {
      final messages = await localSeenService.getMessagesWithLocal(
        chat.partnerId,
        limit: 180,
        startOffset: now.add(const Duration(seconds: 1)),
      );
      final myRecentMessages = messages.where((message) => message.isMe && message.timestamp.isAfter(thirtyDaysAgo)).toList();
      final mySharesOfCurrentVideo = messages
          .where((message) => message.isMe && message.text.trim() == currentVideoLink)
          .toList();
      final lastSharedAt = myRecentMessages.isEmpty ? chat.lastMessageAt : myRecentMessages.last.timestamp;
      final lastSharedThisVideoAt = mySharesOfCurrentVideo.isEmpty ? null : mySharesOfCurrentVideo.last.timestamp;

      contacts.add(
        ShareContact(
          id: chat.partnerId,
          name: chat.partnerName,
          avatarUrl: chat.partnerProfileImageUrl,
          recentShareCount: myRecentMessages.length,
          lastSharedAt: lastSharedAt,
          alreadySharedWithThisVideo: mySharesOfCurrentVideo.isNotEmpty,
          lastSharedThisVideoAt: lastSharedThisVideoAt,
        ),
      );
      chatMap[chat.partnerId] = chat;
    }

    if (!mounted) return;
    setState(() {
      _shareContacts = contacts;
      _chatByPartnerId
        ..clear()
        ..addAll(chatMap);
    });
  }

  Future<void> _shareToContact(ShareContact contact, String link) async {
    final chat = _chatByPartnerId[contact.id];
    if (chat == null) return;

    final message = ChatMessage(
      id: '${contact.id}-${DateTime.now().microsecondsSinceEpoch}',
      text: link,
      isMe: true,
      timestamp: DateTime.now(),
    );

    await chatRepository.sendNotification(chat: chat, message: message, onUserBanned: () {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) {
              return const LoginScreen();
            },
          ),
        );
      }
    });
    if (!mounted) return;
    await _prepareShareContacts();
  }

  void _onLikeChanged(bool newLiked) async {
    liked = newLiked;
    if (disliked && newLiked) {
      print("switch to undisliked");
      setState(() {
        disliked = false;
      });
    }
    bool toggleResult = await videoRepo.toggleLike(widget.video.id);
    if (toggleResult != newLiked) {
      print("Error toggling like: expected $newLiked but got $toggleResult");
      setState(() {
        liked = toggleResult;
      });
    } else {
      print("Successfully toggled like of ${widget.video.id} to $toggleResult");
    }
    widget.onLikeChanged?.call(toggleResult);

    if (toggleResult) {
      localSeenService.saveLike(widget.video.id);
    } else {
      localSeenService.removeLike(widget.video.id);
    }
  }

  void _onDislikeChanged(bool newDisliked) async {
    disliked = newDisliked;
    if (liked && newDisliked) {
      print("switch to unliked");
      setState(() {
        liked = false;
      });
    }
    bool toggleResult = await videoRepo.toggleDislike(widget.video.id);

    if (toggleResult != newDisliked) {
      print("Error toggling dislike: expected $newDisliked but got $toggleResult");
      setState(() {
        disliked = toggleResult;
      });
    } else {
      print("Successfully toggled dislike to $toggleResult");
    }
    widget.onDislikeChanged?.call(toggleResult);

    if (toggleResult) {
      localSeenService.saveDislike(widget.video.id);
    } else {
      localSeenService.removeDislike(widget.video.id);
    }
  }

  void _onCommentButtonPressed() {
    openCommentsForVideo(widget.video, context);
  }
}
