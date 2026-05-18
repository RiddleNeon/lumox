import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lumox/logic/users/user_model.dart';
import 'package:lumox/ui/router/deep_link_builder.dart';
import 'package:lumox/ui/router/router.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';

import '../../../../base_logic.dart';
import '../../../../logic/local_storage/local_seen_service.dart';
import '../../../../logic/video/video.dart';
import '../../../misc/avatar.dart';
import '../../../screens/profile_screen.dart';
import '../buttons/follow_button.dart';

class VideoInfoOverlay extends StatefulWidget {
  final Video video;

  const VideoInfoOverlay({super.key, required this.video});

  @override
  State<VideoInfoOverlay> createState() => _VideoInfoOverlayState();
}

class _VideoInfoOverlayState extends State<VideoInfoOverlay> {
  UserProfile? _author;
  bool _expanded = false;
  bool _showAllTags = false;

  @override
  void initState() {
    super.initState();
    _loadAuthor();
  }

  @override
  void didUpdateWidget(covariant VideoInfoOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _expanded = false;
      _showAllTags = false;
    }
    if (oldWidget.video.authorId != widget.video.authorId) {
      _author = null;
      _loadAuthor();
    }
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  Future<void> _loadAuthor() async {
    final user = await userRepository.getUser(widget.video.authorId);
    if (!mounted) return;
    setState(() {
      _author = user;
    });
  }

  Future<void> _openProfile() async {
    final user = _author ?? await userRepository.getUser(widget.video.authorId);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileScreen(
          initialProfile: user,
          ownProfile: userLoggedIn && user.id == currentUser.id,
          hasBackButton: true,
          initialFollowed: localSeenService.isFollowing(user.id),
          onFollowChange: (bool followed) {},
        ),
      ),
    );
  }

  bool get _isYoutubeVideo {
    final url = widget.video.videoUrl.toLowerCase();
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  Future<void> _openOriginalYoutubeUrl() async {
    final uri = Uri.tryParse(widget.video.videoUrl);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open YouTube link')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = widget.video.title.trim();
    final description = widget.video.description.trim();
    final filteredTags = widget.video.tags
        .where((tag) => tag.trim().isNotEmpty)
        .map((tag) => tag.trim())
        .toList();
    final visibleTags = _showAllTags
        ? filteredTags
        : filteredTags.take(3).toList();
    final hiddenTagsCount = filteredTags.length - visibleTags.length;
    final isOwnProfile =
        userLoggedIn && currentUser.id == widget.video.authorId;
    final hasDescriptionSection = description.isNotEmpty || _isYoutubeVideo;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    cs.scrim.withValues(alpha: 0.74),
                    cs.scrim.withValues(alpha: 0.44),
                    cs.scrim.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxCardWidth = math.min(
                  420.0,
                  math.max(260.0, constraints.maxWidth - 22),
                );
                final maxTagWidth = math.max(64.0, (maxCardWidth - 84) / 3);
                final maxCardHeight = math.max(
                  120.0,
                  constraints.maxHeight - 8,
                );
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxCardWidth,
                    maxHeight: maxCardHeight,
                  ),
                  child: GestureDetector(
                    onTap: _toggleExpanded,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(context.uiRadiusLg),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 34,
                                        height: 34,
                                        child: FittedBox(
                                          fit: BoxFit.cover,
                                          child: Avatar(
                                            imageUrl: _author?.profileImageUrl,
                                            name:
                                                _author
                                                        ?.displayName
                                                        .isNotEmpty ==
                                                    true
                                                ? _author!.displayName
                                                : widget.video.authorName,
                                            colorScheme: cs,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: _openProfile,
                                        child: Text(
                                          _author?.username.isNotEmpty == true
                                              ? _author!.username
                                              : widget.video.authorName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: cs.onSurface,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                    ],
                                  ),
                                ),
                              ),
                              if (!isOwnProfile && _author != null) ...[
                                const SizedBox(width: 8),
                                FollowButton(
                                  key: ValueKey(widget.video.authorId),
                                  user: _author!,
                                  initialSubscribed: localSeenService
                                      .isFollowing(widget.video.authorId),
                                  design: FollowButtonDesign.compact,
                                ),
                              ],
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: _expanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: cs.onSurfaceVariant,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          if (title.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              title,
                              maxLines: _expanded ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                          Flexible(
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              child: ClipRect(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SizeTransition(
                                        sizeFactor: animation,
                                        axisAlignment: -1,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _expanded
                                      ? Padding(
                                          key: ValueKey(
                                            'expanded_details_$_showAllTags',
                                          ),
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (description.isNotEmpty)
                                                  Text(
                                                    description,
                                                    style: TextStyle(
                                                      color:
                                                          cs.onSurfaceVariant,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                if (_isYoutubeVideo)
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                      top:
                                                          description.isNotEmpty
                                                          ? 4
                                                          : 0,
                                                    ),
                                                    child: InkWell(
                                                      onTap:
                                                          _openOriginalYoutubeUrl,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 1,
                                                            ),
                                                        child: Text(
                                                          'source: YouTube',
                                                          style: TextStyle(
                                                            color: cs
                                                                .onSurfaceVariant,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            decoration:
                                                                TextDecoration
                                                                    .underline,
                                                            decorationColor: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (hasDescriptionSection &&
                                                    visibleTags.isNotEmpty)
                                                  const SizedBox(height: 8),
                                                if (visibleTags.isNotEmpty)
                                                  ClipRect(
                                                    child: Wrap(
                                                      spacing: 6,
                                                      runSpacing: 6,
                                                      children: [
                                                        ...visibleTags.map(
                                                          (tag) => _TagChip(
                                                            text: '#$tag',
                                                            maxWidth:
                                                                maxTagWidth,
                                                            isInteractive:
                                                                false,
                                                            onTap: () {
                                                              final deepLink = DeepLinkBuilder.search(
                                                                query: tag,
                                                                mode: .tags,
                                                              );
                                                              
                                                              routerConfig.push(deepLink);
                                                              navBarKey.currentState?.switchToId("/search");
                                                            },
                                                          ),
                                                        ),
                                                        if (hiddenTagsCount > 0)
                                                          _TagChip(
                                                            text:
                                                                '+$hiddenTagsCount',
                                                            isInteractive: true,
                                                            maxWidth:
                                                                maxTagWidth,
                                                            onTap: () {
                                                              setState(() {
                                                                _showAllTags =
                                                                    true;
                                                              });
                                                            },
                                                          ),
                                                        if (_showAllTags &&
                                                            filteredTags
                                                                    .length >
                                                                3)
                                                          _TagChip(
                                                            isInteractive: true,
                                                            text: 'Show less',
                                                            maxWidth:
                                                                maxTagWidth +
                                                                24,
                                                            onTap: () {
                                                              setState(() {
                                                                _showAllTags =
                                                                    false;
                                                              });
                                                            },
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : const SizedBox(
                                          key: ValueKey('collapsed_details'),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  final double maxWidth;
  final VoidCallback? onTap;
  final bool isInteractive;

  const _TagChip({
    required this.text,
    required this.maxWidth,
    this.onTap,
    required this.isInteractive,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.uiRadiusLg),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isInteractive
                  ? cs.tertiary.withValues(alpha: 0.72)
                  : cs.primaryContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(context.uiRadiusLg),
              border: Border.all(
                color: isInteractive
                    ? cs.tertiaryFixedDim
                    : cs.primaryContainer.withValues(alpha: 0.32),
              ),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
