import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:lumox/ui/theme/theme_creation_screen.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:lumox/logic/chat/chat_message.dart';
import 'package:lumox/logic/dictionary/dictionary_entry.dart';
import 'package:lumox/ui/misc/animations/slide_morph_transitions.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';
import 'package:lumox/ui/widgets/dictionary/dictionary_linkifier.dart';

import 'chat_route_preview.dart';
import 'message_avatar.dart';

double _chatBubbleRadius(BuildContext context) => context.uiRadiusLg;
double _chatBubbleTightRadius(BuildContext context) =>
    context.uiRadiusSm * 0.66;

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showAvatar;
  final bool showTimestamp;
  final bool isFirst;
  final bool isLast;
  final AnimationController animationController;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final String recipientName;
  final String? recipientAvatarUrl;
  final VoidCallback? onLongPress;
  final void Function(String route) onRouteTap;
  final void Function(DictionaryEntry entry) onDictionaryTap;
  final Future<ChatRoutePreview?> Function(ChatRouteReference ref)
  previewFutureFor;
  final Map<String, DictionaryEntry> dictionaryEntriesByTitle;

  const MessageBubble({
    super.key,
    required this.message,
    required this.showAvatar,
    required this.showTimestamp,
    required this.isFirst,
    required this.isLast,
    required this.animationController,
    required this.colorScheme,
    required this.theme,
    required this.recipientName,
    this.recipientAvatarUrl,
    this.onLongPress,
    required this.onRouteTap,
    required this.onDictionaryTap,
    required this.previewFutureFor,
    required this.dictionaryEntriesByTitle,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final cs = colorScheme;

    final slide =
        Tween<Offset>(
          begin: Offset(isMe ? 0.3 : -0.3, 0.1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    return SlideMorphTransitions.build(
      animationController,
      SlideTransition(
        position: slide,
        child: Padding(
          padding: EdgeInsets.only(
            top: isFirst ? 8 : 2,
            bottom: isLast ? 6 : 2,
          ),
          child: Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                SizedBox(
                  width: 32,
                  child: showAvatar
                      ? MessageAvatarWidget(
                          name: recipientName,
                          imageUrl: recipientAvatarUrl,
                          isOnline: false,
                          radius: 14,
                          colorScheme: cs,
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 6),
              ],

              Flexible(
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    _BubbleBody(
                      message: message,
                      isMe: isMe,
                      isFirst: isFirst,
                      isLast: isLast,
                      colorScheme: cs,
                      onLongPress: onLongPress,
                      onRouteTap: onRouteTap,
                      onDictionaryTap: onDictionaryTap,
                      previewFutureFor: previewFutureFor,
                      dictionaryEntriesByTitle: dictionaryEntriesByTitle,
                    ),
                    if (showTimestamp || (isMe && isLast))
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 4,
                          left: 4,
                          right: 4,
                          bottom: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(message.timestamp),
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 3),
                              _StatusIcon(
                                status: message.status,
                                colorScheme: cs,
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              if (isMe) const SizedBox(width: 4),
            ],
          ),
        ),
      ),
      beginOffset: Offset(isMe ? 0.08 : -0.08, 0.06),
      beginScale: 0.97,
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _BubbleBody extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isFirst;
  final bool isLast;
  final ColorScheme colorScheme;
  final VoidCallback? onLongPress;
  final void Function(String route) onRouteTap;
  final void Function(DictionaryEntry entry) onDictionaryTap;
  final Future<ChatRoutePreview?> Function(ChatRouteReference ref)
  previewFutureFor;
  final Map<String, DictionaryEntry> dictionaryEntriesByTitle;

  const _BubbleBody({
    required this.message,
    required this.isMe,
    required this.isFirst,
    required this.isLast,
    required this.colorScheme,
    this.onLongPress,
    required this.onRouteTap,
    required this.onDictionaryTap,
    required this.previewFutureFor,
    required this.dictionaryEntriesByTitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final r = Radius.circular(_chatBubbleRadius(context));
    final rSmall = Radius.circular(_chatBubbleTightRadius(context));
    final borderWidth = context.uiBorderWidth;

    BorderRadius borderRadius;
    if (isMe) {
      borderRadius = BorderRadius.only(
        topLeft: r,
        topRight: isFirst ? r : rSmall,
        bottomLeft: r,
        bottomRight: isLast ? rSmall : rSmall,
      );
    } else {
      borderRadius = BorderRadius.only(
        topLeft: isFirst ? r : rSmall,
        topRight: r,
        bottomLeft: isLast ? rSmall : rSmall,
        bottomRight: r,
      );
    }

    final hasText = ChatRoutePreviewResolver.hasVisibleText(message.text);

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onLongPress?.call();
      },
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (hasText)
            Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: EdgeInsets.symmetric(
                horizontal: context.uiSpace(14),
                vertical: context.uiSpace(10),
              ),
              decoration: BoxDecoration(
                color: isMe ? cs.primary : cs.secondary,
                borderRadius: borderRadius,
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                  width: borderWidth,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MessageText(
                    text: message.text,
                    textColor: isMe ? cs.onPrimary : cs.onSecondary,
                    linkColor: isMe
                        ? cs.onPrimary.withValues(alpha: 0.9)
                        : cs.primary,
                    entriesByTitle: dictionaryEntriesByTitle,
                    onDictionaryTap: onDictionaryTap,
                    onRouteTap: onRouteTap,
                    textColorCode: isMe ? cs.primary : cs.secondary,
                  ),
                  if (message.isEdited)
                    Padding(
                      padding: EdgeInsets.only(top: context.uiSpace(4)),
                      child: Text(
                        'edited',
                        style: TextStyle(
                          color: (isMe ? cs.onPrimary : cs.onSecondary)
                              .withValues(alpha: 0.7),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          _RoutePreviewList(
            messageText: message.text,
            onRouteTap: onRouteTap,
            previewFutureFor: previewFutureFor,
          ),
          if (!hasText && message.isEdited)
            Padding(
              padding: EdgeInsets.only(
                top: context.uiSpace(4),
                right: context.uiSpace(2),
                left: context.uiSpace(2),
              ),
              child: Text(
                'edited',
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LinkedSelectableText extends StatelessWidget {
  final String text;
  final Color textColor;
  final Color linkColor;
  final Map<String, DictionaryEntry> entriesByTitle;
  final void Function(DictionaryEntry entry) onDictionaryTap;
  final void Function(String route) onRouteTap;

  const _LinkedSelectableText({
    required this.text,
    required this.textColor,
    required this.linkColor,
    required this.entriesByTitle,
    required this.onDictionaryTap,
    required this.onRouteTap,
  });

  @override
  Widget build(BuildContext context) {
    return DictionaryLinkifiedSelectableText(
      text: text,
      baseStyle: TextStyle(color: textColor, fontSize: 15, height: 1.4),
      linkColor: linkColor,
      entriesByTitle: entriesByTitle,
      onDictionaryTap: onDictionaryTap,
      onRouteTap: onRouteTap,
    );
  }
}

class _MessageText extends StatelessWidget {
  final String text;
  final Color textColor;
  final Color textColorCode;
  final Color linkColor;
  final Map<String, DictionaryEntry> entriesByTitle;
  final void Function(DictionaryEntry entry) onDictionaryTap;
  final void Function(String route) onRouteTap;

  const _MessageText({
    required this.text,
    required this.textColor,
    required this.linkColor,
    required this.entriesByTitle,
    required this.onDictionaryTap,
    required this.onRouteTap,
    required this.textColorCode,
  });

  @override
  Widget build(BuildContext context) {
    if (!_looksLikeMarkdown(text)) {
      return _LinkedSelectableText(
        text: text,
        textColor: textColor,
        linkColor: linkColor,
        entriesByTitle: entriesByTitle,
        onDictionaryTap: onDictionaryTap,
        onRouteTap: onRouteTap,
      );
    }

    final entriesByRoute = <String, DictionaryEntry>{
      for (final entry in entriesByTitle.values) entry.route: entry,
    };
    final entriesBySubjectTitle = <String, DictionaryEntry>{};
    final entriesBySubjectId = <String, DictionaryEntry>{};
    for (final entry in entriesByTitle.values) {
      final subject = entry.subject.trim().toLowerCase();
      if (subject.isEmpty) continue;
      entriesBySubjectId['$subject:${entry.questId}'] = entry;
      final normalizedTitle = entry.normalizedTitle;
      if (normalizedTitle.isNotEmpty) {
        entriesBySubjectTitle['$subject:$normalizedTitle'] = entry;
      }
    }

    final linkified = _linkifyRoutes(
      linkifyDictionaryEntries(data: text, entriesByTitle: entriesByTitle),
    );

    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: TextStyle(color: textColor, fontSize: 15, height: 1.4),
      a: TextStyle(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
      ),
      code: TextStyle(color: textColorCode, fontSize: 11),
    );

    return MarkdownBody(
      data: linkified,
      styleSheet: sheet,
      onTapLink: (label, href, title) {
        final raw = href?.trim();
        if (raw == null || raw.isEmpty) return;
        if (ChatRoutePreviewResolver.isRoutableToken(raw)) {
          onRouteTap(raw);
          return;
        }
        final entry =
            _entryForSubjectRef(
              raw,
              entriesBySubjectTitle,
              entriesBySubjectId,
            ) ??
            entriesByRoute[raw];
        if (entry != null) {
          onDictionaryTap(entry);
          return;
        }
        final resolved = raw.startsWith('/')
            ? Uri.base.resolve(raw).toString()
            : raw;
        launchUrlString(resolved);
      },
    );
  }
}

bool _looksLikeMarkdown(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  final patterns = <RegExp>[
    RegExp(r'^#{1,6}\s', multiLine: true),
    RegExp(r'(\*\*|__)[^\n]+?(\*\*|__)'),
    RegExp(r'(?<!\*)\*[^\n]+?\*(?!\*)'),
    RegExp(r'(?<!_)_[^\n]+?_(?!_)'),
    RegExp(r'`[^`\n]+`'),
    RegExp(r'```', multiLine: true),
    RegExp(r'^\s*[-*+]\s+\S', multiLine: true),
    RegExp(r'^\s*\d+\.\s+\S', multiLine: true),
    RegExp(r'\[[^\]]+\]\([^\)]+\)'),
    RegExp(r'^>\s', multiLine: true),
  ];
  return patterns.any((pattern) => pattern.hasMatch(text));
}

String _linkifyRoutes(String data) {
  if (data.trim().isEmpty) return data;
  final routeRegex = RegExp(r'(?<!\S)(/\S+)');
  final skipRanges = _collectMarkdownSkipRanges(data);
  final buffer = StringBuffer();
  var cursor = 0;

  for (final match in routeRegex.allMatches(data)) {
    final start = match.start;
    final end = match.end;
    if (_isInSkipRange(start, end, skipRanges)) continue;
    if (start < cursor) continue;

    final raw = match.group(1);
    if (raw == null || !ChatRoutePreviewResolver.isRoutableToken(raw)) continue;

    buffer.write(data.substring(cursor, start));
    buffer.write('[$raw]($raw)');
    cursor = end;
  }

  if (cursor < data.length) {
    buffer.write(data.substring(cursor));
  }

  return buffer.toString();
}

DictionaryEntry? _entryForSubjectRef(
  String href,
  Map<String, DictionaryEntry> entriesBySubjectTitle,
  Map<String, DictionaryEntry> entriesBySubjectId,
) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('/') || trimmed.contains('://')) return null;
  final separatorIndex = trimmed.indexOf(':');
  if (separatorIndex <= 0 || separatorIndex >= trimmed.length - 1) return null;
  final subject = Uri.decodeComponent(
    trimmed.substring(0, separatorIndex),
  ).trim().toLowerCase();
  final rawKey = Uri.decodeComponent(
    trimmed.substring(separatorIndex + 1),
  ).trim();
  if (subject.isEmpty || rawKey.isEmpty) return null;

  final numericId = int.tryParse(rawKey);
  if (numericId != null) {
    return entriesBySubjectId['$subject:$numericId'];
  }

  return entriesBySubjectTitle['$subject:${rawKey.toLowerCase()}'];
}

List<TextRange> _collectMarkdownSkipRanges(String data) {
  final ranges = <TextRange>[];
  final patterns = <RegExp>[
    RegExp(r'```[\s\S]*?```', multiLine: true),
    RegExp(r'`[^`\n]+`'),
    RegExp(r'!\[[\s\S]*?\]\([\s\S]*?\)'),
    RegExp(r'\[[\s\S]*?\]\([\s\S]*?\)'),
  ];

  for (final pattern in patterns) {
    for (final match in pattern.allMatches(data)) {
      ranges.add(TextRange(start: match.start, end: match.end));
    }
  }

  if (ranges.isEmpty) return ranges;
  ranges.sort((a, b) => a.start.compareTo(b.start));

  final merged = <TextRange>[];
  var current = ranges.first;
  for (final range in ranges.skip(1)) {
    if (range.start <= current.end) {
      current = TextRange(
        start: current.start,
        end: range.end > current.end ? range.end : current.end,
      );
    } else {
      merged.add(current);
      current = range;
    }
  }
  merged.add(current);
  return merged;
}

bool _isInSkipRange(int start, int end, List<TextRange> ranges) {
  for (final range in ranges) {
    if (range.start < end && start < range.end) return true;
  }
  return false;
}

class _RoutePreviewList extends StatelessWidget {
  final String messageText;
  final void Function(String route) onRouteTap;
  final Future<ChatRoutePreview?> Function(ChatRouteReference ref)
  previewFutureFor;

  const _RoutePreviewList({
    required this.messageText,
    required this.onRouteTap,
    required this.previewFutureFor,
  });

  static double _estimatedPreviewHeight(ChatRouteReference ref) {
    final path = ref.uri.path;
    if (path.startsWith('/feed/')) return 252;
    if (path.startsWith('/themes')) return 190;
    return 64;
  }

  static Widget _buildPreviewPlaceholder(
    BuildContext context,
    ChatRouteReference ref, {
    bool isError = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: _estimatedPreviewHeight(ref),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        border: isError
            ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.6))
            : null,
      ),
      alignment: Alignment.center,
      child: isError
          ? Text(
              'Preview unavailable',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final refs = ChatRoutePreviewResolver.extract(messageText);
    if (refs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          children: refs
              .map(
                (ref) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FutureBuilder<ChatRoutePreview?>(
                    future: previewFutureFor(ref),
                    builder: (context, snapshot) {
                      final preview = snapshot.data;
                      if (snapshot.connectionState != ConnectionState.done) {
                        return _buildPreviewPlaceholder(context, ref);
                      }
                      if (preview == null) {
                        return _buildPreviewPlaceholder(
                          context,
                          ref,
                          isError: true,
                        );
                      }
                      return _RoutePreviewCard(
                        preview: preview,
                        onTap: () => onRouteTap(preview.route),
                      );
                    },
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _RoutePreviewCard extends StatelessWidget {
  final ChatRoutePreview preview;
  final VoidCallback onTap;

  const _RoutePreviewCard({required this.preview, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = switch (preview.type) {
      ChatRoutePreviewType.feed => Icons.play_circle_fill_rounded,
      ChatRoutePreviewType.quests => Icons.map_outlined,
      ChatRoutePreviewType.chat => Icons.chat_bubble_outline_rounded,
      ChatRoutePreviewType.search => Icons.search_rounded,
      ChatRoutePreviewType.dictionary => Icons.menu_book_outlined,
      ChatRoutePreviewType.themes => Icons.palette_outlined,
      ChatRoutePreviewType.profile => Icons.person_outline_rounded,
    };

    // Special preview for themes with full theme preview widget
    if (preview.type == ChatRoutePreviewType.themes &&
        preview.themeModel != null) {
      final theme = preview.themeModel!;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        child: SizedBox(
          width: double.infinity,
          height: 190,
          child: ThemePreview(
            c: theme.colors,
            theme: theme,
            isDefault: false,
            openEditor: null,
            saveTheme: null,
            deleteTheme: null,
            isSelected: false,
            onShare: null,
            creatorName: preview.subtitle.replaceFirst('by ', ''),
            showCreatorInline: true,
            isPublic: theme.isPublic,
            showVisibilityBadge: false,
          ),
        ),
      );
    }

    if (preview.type == ChatRoutePreviewType.feed &&
        preview.thumbnailUrl?.isNotEmpty == true) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(context.uiRadiusMd),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(context.uiRadiusMd),
                      topRight: Radius.circular(context.uiRadiusMd),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: preview.thumbnailUrl!,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        width: double.infinity,
                        height: 200,
                        color: cs.surfaceContainerHighest,
                        child: Icon(icon, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    if (preview.avatarUrl != null &&
                        preview.avatarUrl!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundImage: CachedNetworkImageProvider(
                            preview.avatarUrl!,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preview.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            preview.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.uiRadiusMd),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            if (preview.thumbnailUrl != null &&
                preview.thumbnailUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(context.uiRadiusMd),
                  bottomLeft: Radius.circular(context.uiRadiusMd),
                ),
                child: CachedNetworkImage(
                  // Stable cached image prevents flashing while list items recycle.
                  imageUrl: preview.thumbnailUrl!,
                  width: 72,
                  height: 64,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(
                    width: 72,
                    height: 64,
                    color: cs.surfaceContainerHighest,
                    child: Icon(icon, color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              Container(
                width: 56,
                height: 64,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(context.uiRadiusMd),
                    bottomLeft: Radius.circular(context.uiRadiusMd),
                  ),
                ),
                child: Icon(icon, color: cs.onSurfaceVariant),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preview.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (preview.avatarUrl != null && preview.avatarUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: CircleAvatar(
                  radius: 12,
                  backgroundImage: CachedNetworkImageProvider(
                    preview.avatarUrl!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final ColorScheme colorScheme;

  const _StatusIcon({required this.status, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        );
      case MessageStatus.sent:
        return Icon(
          Icons.check_rounded,
          size: 12,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        );
      case MessageStatus.delivered:
        return Icon(
          Icons.done_all_rounded,
          size: 12,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        );
      case MessageStatus.read:
        return Icon(
          Icons.done_all_rounded,
          size: 12,
          color: colorScheme.tertiary,
        );
    }
  }
}
