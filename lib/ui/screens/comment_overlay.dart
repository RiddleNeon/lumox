// ignore_for_file: unused_element_parameter

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumox/logic/repositories/chat_repository.dart';
import 'package:lumox/ui/misc/avatar.dart';
import 'package:lumox/ui/animations/slide_morph_transitions.dart';
import 'package:lumox/ui/router/router.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';

import '../../base_logic.dart';
import '../../base_ui.dart';
import '../../logic/comments/comment.dart';
import '../../logic/repositories/video_repository.dart';
import '../../logic/video/video.dart';
import 'auth_screen.dart';

class _CommentVM {
  final Comment comment;

  bool get likedByMe => comment.likedByCurrentUser;

  set likedByMe(bool value) => comment.likedByCurrentUser = value;
  int likeCount;

  int get replyCount => comment.replyCount ?? 0;

  set replyCount(int newVal) => comment.replyCount = newVal;

  bool isLoadingReplies;

  /// true once replies have been fetched at least once
  bool repliesLoaded;

  /// whether the reply section is currently expanded
  bool showReplies;

  /// child VMs – empty until first load
  final List<_CommentVM> replies;

  _CommentVM({required this.comment, this.isLoadingReplies = false, this.repliesLoaded = false, this.showReplies = false, List<_CommentVM>? replies})
    : likeCount = comment.likeCount,
      replies = replies ?? [];
}

Future<void> openCommentsForVideo(Video video, BuildContext context) async {
  String videoId = video.id;
  final commentQueryResult = await videoRepo.getComments(videoId);
  List<Comment> comments = commentQueryResult.comments;
  print("comments: $comments}");
  int? lastCommentOffset = commentQueryResult.nextOffset;
  final Map<String, int> replyOffsets = {};
  if (!context.mounted) return;
  showCommentsOverlay(
    context: context,
    comments: comments,
    currentUserId: currentAuthUserId(),
    currentUsername: currentUser.username,
    currentUserProfileImageUrl: currentUser.profileImageUrl,
    initialCommentsCount: video.commentsCount,
    onCommentAdded: (p0) {
      return videoRepo.addComment(videoId, p0);
    },
    onLoadMore: () async {
      if (lastCommentOffset == null) return [];
      final commentQueryResult = await videoRepo.getComments(videoId, offset: lastCommentOffset!);
      List<Comment> comments = commentQueryResult.comments;
      lastCommentOffset = commentQueryResult.nextOffset;
      return comments;
    },
    onLoadReplies: (parent) async {
      final replyOffset = replyOffsets[parent.id] ?? 0;
      final result = await videoRepo.getComments(videoId, commentId: parent.id, offset: replyOffset);
      if (result.nextOffset != null) {
        replyOffsets[parent.id] = result.nextOffset!;
      }
      return result.comments;
    },
  );
}

void showCommentsOverlay({
  required BuildContext context,
  required List<Comment> comments,
  required String currentUserId,
  required String currentUsername,
  required String currentUserProfileImageUrl,
  required Future<Comment> Function(Comment) onCommentAdded,
  Future<List<Comment>> Function()? onLoadMore,
  Future<List<Comment>> Function(Comment parent)? onLoadReplies,
  int? initialCommentsCount,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.6),
    builder: (_) => CommentsOverlay(
      comments: comments,
      currentUserId: currentUserId,
      currentUsername: currentUsername,
      currentUserProfileImageUrl: currentUserProfileImageUrl,
      onCommentAdded: onCommentAdded,
      onLoadMore: onLoadMore,
      onLoadReplies: onLoadReplies,
      initialCommentCount: initialCommentsCount,
    ),
  );
}

class CommentsOverlay extends StatefulWidget {
  final List<Comment> comments;
  final String currentUserId;
  final String currentUsername;
  final String currentUserProfileImageUrl;
  final Future<Comment> Function(Comment) onCommentAdded;
  final int? initialCommentCount;

  /// Called when the user scrolls near the end of the top-level list.
  /// Return [] to signal no more comments.
  final Future<List<Comment>> Function()? onLoadMore;

  /// Called the first time the user taps "View replies" on any comment.
  /// Receives the parent [Comment]; return its direct children.
  /// The overlay calls this recursively for deeper nesting levels on demand.
  final Future<List<Comment>> Function(Comment parent)? onLoadReplies;

  const CommentsOverlay({
    super.key,
    required this.comments,
    required this.currentUserId,
    required this.currentUsername,
    required this.currentUserProfileImageUrl,
    required this.onCommentAdded,
    this.onLoadMore,
    this.onLoadReplies,
    this.initialCommentCount,
  });

  @override
  State<CommentsOverlay> createState() => _CommentsOverlayState();
}

class _CommentsOverlayState extends State<CommentsOverlay> {
  late final List<_CommentVM> _vms;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  int newOwnComments = 0;

  _CommentVM? _replyTarget;

  ColorScheme get _cs => Theme.of(context).colorScheme;

  Color get _bgColor => _cs.surface.withValues(alpha: 0.95);

  Color get _surfaceColor => _cs.surfaceContainerHigh;

  Color get _accentColor => _cs.primary;

  Color get _subtleText => _cs.onSurfaceVariant;

  Color get _dividerColor => _cs.outlineVariant.withValues(alpha: 0.65);

  Color get _likedColor => _cs.error;

  Color get _bodyTextColor => _cs.onSurface.withValues(alpha: 0.92);

  static const int _maxIndentDepth = 5;
  static const double _indentPerDepth = 20.0;

  @override
  void initState() {
    super.initState();
    _vms = widget.comments.map(_toVM).toList();
    if (widget.onLoadMore != null) {
      _scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  _CommentVM _toVM(Comment c) => _CommentVM(comment: c);

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) _loadMoreComments();
  }

  Future<void> _loadMoreComments() async {
    if (_isLoadingMore || !_hasMore || widget.onLoadMore == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final next = await widget.onLoadMore!();
      if (!mounted) return;
      setState(() {
        if (next.isEmpty) {
          _hasMore = false;
        } else {
          _vms.addAll(next.map(_toVM));
        }
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _toggleReplies(_CommentVM vm) async {
    if (vm.repliesLoaded) {
      setState(() => vm.showReplies = !vm.showReplies);
      return;
    }

    if (widget.onLoadReplies == null) return;

    setState(() => vm.isLoadingReplies = true);
    try {
      final loaded = await widget.onLoadReplies!(vm.comment);
      if (!mounted) return;
      setState(() {
        vm.comment.addReplies(loaded);
        vm.replies
          ..clear()
          ..addAll(loaded.map(_toVM));
        vm.repliesLoaded = true;
        vm.isLoadingReplies = false;
        vm.showReplies = true;
      });
    } catch (_) {
      if (mounted) setState(() => vm.isLoadingReplies = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_isSending) return;

    newOwnComments++;

    HapticFeedback.lightImpact();
    setState(() => _isSending = true);
    
    final target = _replyTarget;

    final newId = '${DateTime.now().millisecondsSinceEpoch}';

    final newComment = Comment(
      id: newId,
      userId: widget.currentUserId,
      username: widget.currentUsername,
      userProfileImageUrl: widget.currentUserProfileImageUrl,
      message: text,
      date: DateTime.now(),
      likeCount: 0,
      parentId: target?.comment.id,
      depth: target != null ? target.comment.depth + 1 : 0,
      replyCount: 0,
      likedByCurrentUser: false,
    );
    
    
    final Comment savedComment;
    try {
       savedComment = await widget.onCommentAdded(newComment);
    } on UserBannedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      Future.delayed(const Duration(seconds: 3), () {
        userBannedHint = true;
        userRepository.selfBanUserSupabase();
        if (mounted) {
          routerConfig.push("/login-force");
        }
      });
      _isSending = false;
      _textController.clear();
      _focusNode.unfocus();
      return;
    } on ContentModerationViolationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      _isSending = false;
      _textController.clear();
      _focusNode.unfocus();
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to post comment. Please try again.')));
      _isSending = false;
      _textController.clear();
      _focusNode.unfocus();
      return;
    }
    
    
    newComment.id = savedComment.id;

    final newVm = _toVM(newComment);
    newVm.repliesLoaded = true;

    setState(() {
      if (target != null) {
        print("Adding reply to ${target.comment.id}: ${newComment.message}");
        target.replies.insert(0, newVm);
        target.comment.addReply(newComment);
        target.repliesLoaded = true;
        target.showReplies = true;
      } else {
        _vms.insert(0, newVm);
      }
      _replyTarget = null;
      _isSending = false;
    });

    _textController.clear();
    _focusNode.unfocus();

    if (target == null && _scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _startReply(_CommentVM vm) {
    setState(() => _replyTarget = vm);
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTarget = null);
    _focusNode.unfocus();
  }

  void _toggleLike(_CommentVM vm) async {
    HapticFeedback.selectionClick();

    bool liked = await videoRepo.toggleCommentLike(vm.comment.id);
    if (mounted) {
      setState(() {
        if (liked) {
          vm.likedByMe = true;
          vm.likeCount++;
        } else {
          vm.likedByMe = false;
          vm.likeCount--;
        }
      });
    }
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.day}.${date.month}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(context.uiRadiusLg)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.80,
        color: _bgColor,
        child: Column(
          children: [
            _buildHeader(),
            Divider(color: _dividerColor, height: 1),
            Expanded(child: _buildList()),
            Divider(color: _dividerColor, height: 1),
            if (_replyTarget != null) _buildReplyBanner(),
            _buildInputBar(bottomPadding),
          ],
        ),
      ),
    );
  }


  Widget _buildHeader() {
    final count = (widget.initialCommentCount ?? _vms.length) + newOwnComments;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: _dividerColor, borderRadius: BorderRadius.circular(context.uiRadiusSm)),
                  ),
                ),
                Text(
                  'Comments • $count',
                  style: TextStyle(color: _cs.onSurface, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: _subtleText),
          ),
        ],
      ),
    );
  }


  Widget _buildList() {
    if (_vms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, color: _subtleText, size: 48),
            const SizedBox(height: 12),
            Text(
              'No comments yet.\nBe the first!',
              textAlign: TextAlign.center,
              style: TextStyle(color: _subtleText, fontSize: 15, height: 1.5),
            ),
          ],
        ),
      );
    }

    final hasFooter = widget.onLoadMore != null;
    final count = _vms.length + (hasFooter ? 1 : 0);

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      itemCount: count,
      separatorBuilder: (_, i) {
        if (i >= _vms.length - 1) return const SizedBox.shrink();
        return Divider(color: _dividerColor, height: 1, indent: 68);
      },
      itemBuilder: (_, i) {
        if (i == _vms.length) return _buildFooter();
        return _buildCommentBlock(_vms[i], depth: 0);
      },
    );
  }


  Widget _buildCommentBlock(_CommentVM vm, {required int depth}) {
    final double deltaIndent = depth > 0 && depth <= _maxIndentDepth ? _indentPerDepth : 0.0;
    final bool isReply = depth > 0;
    
    final bool showRepliesRow = vm.isLoadingReplies || vm.replies.isNotEmpty || (!vm.repliesLoaded && widget.onLoadReplies != null);

    return Padding(
      padding: EdgeInsets.only(left: deltaIndent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentTile(
            vm: vm,
            timeAgo: _timeAgo(vm.comment.date),
            isOwn: vm.comment.userId == widget.currentUserId,
            accentColor: _accentColor,
            likedColor: _likedColor,
            subtleText: _subtleText,
            textColor: _cs.onSurface,
            bodyTextColor: _bodyTextColor,
            isReply: isReply,
            depth: depth,
            onLike: () => _toggleLike(vm),
            onReply: () => _startReply(vm),
          ),

          // ── Replies toggle / spinner ────────────────────────────
          if (showRepliesRow && (vm.replyCount > 0))
            Padding(
              padding: const EdgeInsets.only(left: 52, bottom: 4),
              child: GestureDetector(
                onTap: vm.isLoadingReplies ? null : () => _toggleReplies(vm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (vm.isLoadingReplies) ...[
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: _subtleText)),
                      const SizedBox(width: 8),
                      Text(
                        'Loading replies…',
                        style: TextStyle(color: _subtleText, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ] else ...[
                      Container(width: 24, height: 1, color: _subtleText, margin: const EdgeInsets.only(right: 8)),
                      Text(
                        vm.showReplies ? 'Hide replies' : 'View ${vm.replyCount} repl${vm.replyCount == 1 ? 'y' : 'ies'}',
                        style: TextStyle(color: _subtleText, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // ── Recursive children ──────────────────────────────────
          if (vm.showReplies && vm.replies.isNotEmpty)
            Column(
              children: vm.replies.map((reply) {
                return Column(
                  children: [
                    Divider(color: _dividerColor, height: 1, indent: 16),
                    _buildCommentBlock(reply, depth: depth + 1),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    if (_isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _accentColor)),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('— no more comments —', style: TextStyle(color: _subtleText, fontSize: 12)),
        ),
      );
    }
    return const SizedBox(height: 8);
  }

  // ── Reply banner ──────────────────────────────────────────────

  Widget _buildReplyBanner() {
    return Container(
      color: _cs.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 15, color: _accentColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Replying to @${_replyTarget!.comment.username}',
              style: TextStyle(color: _accentColor, fontSize: 12.5, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _cancelReply,
            child: Icon(Icons.close_rounded, size: 16, color: _subtleText),
          ),
        ],
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────

  Widget _buildInputBar(double bottomPadding) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomPadding),
      child: Row(
        children: [
          _Avatar(url: widget.currentUserProfileImageUrl, radius: 18, username: widget.currentUsername),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(context.uiRadiusLg),
                border: Border.all(color: _dividerColor),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendComment(),
                style: TextStyle(color: _cs.onSurface, fontSize: 15),
                decoration: InputDecoration(
                  hintText: _replyTarget != null ? 'Reply to @${_replyTarget!.comment.username}…' : 'Write a comment…',
                  hintStyle: TextStyle(color: _subtleText, fontSize: 15),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _textController,
            builder: (_, _) {
              final hasText = _textController.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText && !_isSending ? _sendComment : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: hasText ? _accentColor : _surfaceColor),
                  child: _isSending
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, color: _cs.onPrimary),
                        )
                      : Icon(Icons.arrow_upward_rounded, color: hasText ? _cs.onPrimary : _subtleText, size: 20),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final _CommentVM vm;
  final String timeAgo;
  final bool isOwn;
  final bool isReply;
  final int depth;
  final Color accentColor;
  final Color likedColor;
  final Color subtleText;
  final Color textColor;
  final Color bodyTextColor;
  final VoidCallback onLike;
  final VoidCallback onReply;

  const _CommentTile({
    required this.vm,
    required this.timeAgo,
    required this.isOwn,
    required this.accentColor,
    required this.likedColor,
    required this.subtleText,
    required this.textColor,
    required this.bodyTextColor,
    required this.onLike,
    required this.onReply,
    this.isReply = false,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context) {
    final double avatarRadius = isReply ? (depth > 1 ? 13.0 : 16.0) : 20.0;
    final double fontSize = isReply ? (depth > 1 ? 12.5 : 13.5) : 14.5;
    final double nameFontSize = isReply ? (depth > 1 ? 11.5 : 12.5) : 13.5;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, isReply ? 8 : 12, 16, isReply ? 8 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(url: vm.comment.userProfileImageUrl, radius: avatarRadius, username: vm.comment.username),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      vm.comment.username,
                      style: TextStyle(color: isOwn ? accentColor : textColor, fontWeight: FontWeight.w600, fontSize: nameFontSize),
                    ),
                    if (isOwn)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text('· you', style: TextStyle(color: subtleText, fontSize: 11)),
                      ),
                    const Spacer(),
                    Text(timeAgo, style: TextStyle(color: subtleText, fontSize: 11.5)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  vm.comment.message,
                  style: TextStyle(color: bodyTextColor, fontSize: fontSize, height: 1.45),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _LikeButton(count: vm.likeCount, liked: vm.likedByMe, likedColor: likedColor, subtleText: subtleText, onTap: onLike),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: onReply,
                      child: Row(
                        children: [
                          Icon(Icons.reply_rounded, size: 15, color: subtleText),
                          const SizedBox(width: 4),
                          Text('Reply', style: TextStyle(color: subtleText, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LikeButton extends StatefulWidget {
  final int count;
  final bool liked;
  final Color likedColor;
  final Color subtleText;
  final VoidCallback onTap;

  const _LikeButton({required this.count, required this.liked, required this.likedColor, required this.subtleText, required this.onTap});

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.liked ? widget.likedColor : widget.subtleText;
    return GestureDetector(
      onTap: _handleTap,
      child: Row(
        children: [
          ScaleTransition(
            scale: _scale,
            child: Icon(widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 15, color: color),
          ),
          const SizedBox(width: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => SlideMorphTransitions.switcher(child, anim, beginOffset: const Offset(0, 0.16), beginScale: 0.9),
            child: Text(
              widget.count > 0 ? '${widget.count}' : 'Like',
              key: ValueKey(widget.count),
              style: TextStyle(color: color, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String username;
  final double radius;

  const _Avatar({required this.url, required this.radius, required this.username});

  @override
  Widget build(BuildContext context) {
    return Avatar(imageUrl: url, name: username, colorScheme: Theme.of(context).colorScheme);
  }
}
