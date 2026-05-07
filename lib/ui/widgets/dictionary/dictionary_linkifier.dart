import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:lumox/logic/dictionary/dictionary_entry.dart';

class DictionaryLinkifiedSelectableText extends StatefulWidget {
  final String text;
  final TextStyle baseStyle;
  final Color linkColor;
  final Map<String, DictionaryEntry> entriesByTitle;
  final void Function(DictionaryEntry entry) onDictionaryTap;
  final void Function(String route) onRouteTap;

  const DictionaryLinkifiedSelectableText({
    super.key,
    required this.text,
    required this.baseStyle,
    required this.linkColor,
    required this.entriesByTitle,
    required this.onDictionaryTap,
    required this.onRouteTap,
  });

  @override
  State<DictionaryLinkifiedSelectableText> createState() => _DictionaryLinkifiedSelectableTextState();
}

class _DictionaryLinkifiedSelectableTextState extends State<DictionaryLinkifiedSelectableText> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _spans = const [];

  @override
  void initState() {
    super.initState();
    _rebuildSpans();
  }

  @override
  void didUpdateWidget(covariant DictionaryLinkifiedSelectableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.baseStyle != widget.baseStyle || oldWidget.linkColor != widget.linkColor || oldWidget.entriesByTitle != widget.entriesByTitle) {
      _rebuildSpans();
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  void _rebuildSpans() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final matches = _findMatches(widget.text, widget.entriesByTitle);
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start), style: widget.baseStyle));
      }

      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (match.entry != null) {
            widget.onDictionaryTap(match.entry!);
          } else if (match.route != null) {
            widget.onRouteTap(match.route!);
          }
        };
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: widget.text.substring(match.start, match.end),
          style: widget.baseStyle.copyWith(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
          ),
          recognizer: recognizer,
        ),
      );
      cursor = match.end;
    }

    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor), style: widget.baseStyle));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: '', style: widget.baseStyle));
    }

    setState(() => _spans = spans);
  }

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(TextSpan(children: _spans), selectionColor: Theme.of(context).colorScheme.tertiary);
  }
}

class DictionaryMarkdownBody extends StatelessWidget {
  final String data;
  final List<DictionaryEntry> entries;
  final MarkdownStyleSheet? styleSheet;
  final void Function(DictionaryEntry entry) onTapEntry;
  final Color? linkColor;
  final Map<String, DictionaryEntry>? titleIndex;

  const DictionaryMarkdownBody({
    super.key,
    required this.data,
    required this.entries,
    required this.onTapEntry,
    this.styleSheet,
    this.linkColor,
    this.titleIndex,
  });

  @override
  Widget build(BuildContext context) {
    final entriesByTitle = titleIndex ?? <String, DictionaryEntry>{
      for (final entry in entries)
        if (entry.normalizedTitle.isNotEmpty) entry.normalizedTitle: entry,
    };

    if (entriesByTitle.isEmpty) {
      return MarkdownBody(data: data, styleSheet: styleSheet);
    }

    final entriesByRoute = <String, DictionaryEntry>{
      for (final entry in entries) entry.route: entry,
    };
    final entriesBySubjectTitle = _buildSubjectTitleIndex(entriesByTitle);
    final entriesBySubjectId = _buildSubjectIdIndex(entries);

    final effectiveStyleSheet = _applyLinkStyle(styleSheet, linkColor, context);

    return MarkdownBody(
      data: data,
      styleSheet: effectiveStyleSheet,
      onTapLink: (text, href, title) {
        if (href == null || href.trim().isEmpty) return;
        final subjectEntry = _entryForSubjectRef(href, entriesBySubjectTitle, entriesBySubjectId);
        if (subjectEntry != null) {
          onTapEntry(subjectEntry);
          return;
        }
        final entry = _entryForHref(href, entriesByRoute);
        if (entry != null) {
          onTapEntry(entry);
          return;
        }
        final resolved = href.startsWith('/') ? Uri.base.resolve(href).toString() : href;
        launchUrlString(resolved);
      },
    );
  }
}

MarkdownStyleSheet? _applyLinkStyle(MarkdownStyleSheet? styleSheet, Color? linkColor, BuildContext context) {
  if (linkColor == null) return styleSheet;
  final base = styleSheet ?? MarkdownStyleSheet.fromTheme(Theme.of(context));
  return base.copyWith(
    a: TextStyle(color: linkColor, decoration: TextDecoration.underline, decorationColor: linkColor),
  );
}

DictionaryEntry? _entryForHref(String href, Map<String, DictionaryEntry> entriesByRoute) {
  final direct = entriesByRoute[href];
  if (direct != null) return direct;
  final uri = Uri.tryParse(href);
  if (uri == null || uri.path != '/dictionary') return null;
  final questId = int.tryParse(uri.queryParameters['id'] ?? '');
  if (questId == null) return null;
  final subject = uri.queryParameters['subject']?.trim().toLowerCase();
  for (final entry in entriesByRoute.values) {
    if (entry.questId != questId) continue;
    if (subject == null || entry.subject.toLowerCase() == subject) {
      return entry;
    }
  }
  return null;
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
  final subject = Uri.decodeComponent(trimmed.substring(0, separatorIndex)).trim().toLowerCase();
  final rawKey = Uri.decodeComponent(trimmed.substring(separatorIndex + 1)).trim();
  if (subject.isEmpty || rawKey.isEmpty) return null;

  final numericId = int.tryParse(rawKey);
  if (numericId != null) {
    return entriesBySubjectId['$subject:$numericId'];
  }

  final entryKey = rawKey.toLowerCase();
  return entriesBySubjectTitle['$subject:$entryKey'];
}

Map<String, DictionaryEntry> _buildSubjectIdIndex(List<DictionaryEntry> entries) {
  final index = <String, DictionaryEntry>{};
  for (final entry in entries) {
    final subject = entry.subject.trim().toLowerCase();
    if (subject.isEmpty) continue;
    index.putIfAbsent('$subject:${entry.questId}', () => entry);
  }
  return index;
}

Map<String, DictionaryEntry> _buildSubjectTitleIndex(Map<String, DictionaryEntry> entriesByTitle) {
  final index = <String, DictionaryEntry>{};
  for (final entry in entriesByTitle.entries) {
    final term = entry.key.trim().toLowerCase();
    if (term.isEmpty) continue;
    final subject = entry.value.subject.trim().toLowerCase();
    if (subject.isEmpty) continue;
    index.putIfAbsent('$subject:$term', () => entry.value);
  }
  return index;
}

String linkifyDictionaryEntriesForSubject({
  required String data,
  required Map<String, DictionaryEntry> entriesByTitle,
  required String subject,
}) {
  final normalizedSubject = subject.trim().toLowerCase();
  if (data.trim().isEmpty || normalizedSubject.isEmpty) return data;

  final filtered = <String, DictionaryEntry>{};
  for (final entry in entriesByTitle.entries) {
    final entrySubject = entry.value.subject.trim().toLowerCase();
    if (entrySubject != normalizedSubject) continue;
    final term = entry.key.trim().toLowerCase();
    if (term.isEmpty) continue;
    filtered.putIfAbsent(term, () => entry.value);
  }

  if (filtered.isEmpty) return data;

  final pattern = RegExp(
    _buildDictionaryPattern(filtered.keys.toList()),
    multiLine: true,
    caseSensitive: false,
  );
  final skipRanges = _collectMarkdownSkipRanges(data);
  return _replaceMatchesWithSubjectRef(data, pattern, filtered, skipRanges);
}

String _linkifyDictionaryEntries(String data, Map<String, DictionaryEntry> entriesByTitle) {
  if (data.trim().isEmpty) return data;
  final pattern = RegExp(
    _buildDictionaryPattern(entriesByTitle.keys.toList()),
    multiLine: true,
    caseSensitive: false,
  );
  final skipRanges = _collectMarkdownSkipRanges(data);
  if (skipRanges.isEmpty) return _replaceMatches(data, pattern, entriesByTitle, skipRanges);
  return _replaceMatches(data, pattern, entriesByTitle, skipRanges);
}

String _replaceMatches(
  String data,
  RegExp pattern,
  Map<String, DictionaryEntry> entriesByTitle,
  List<TextRange> skipRanges,
) {
  final buffer = StringBuffer();
  var cursor = 0;

  for (final match in pattern.allMatches(data)) {
    final start = match.start;
    final end = match.end;
    if (_isInSkipRange(start, end, skipRanges)) {
      continue;
    }
    if (start < cursor) continue;

    final matched = match.group(0) ?? '';
    final entry = entriesByTitle[matched.trim().toLowerCase()];
    if (entry == null) continue;

    buffer.write(data.substring(cursor, start));
    buffer.write('[$matched](${entry.route})');
    cursor = end;
  }

  if (cursor < data.length) {
    buffer.write(data.substring(cursor));
  }

  return buffer.toString();
}

String _replaceMatchesWithSubjectRef(
  String data,
  RegExp pattern,
  Map<String, DictionaryEntry> entriesByTitle,
  List<TextRange> skipRanges,
) {
  final buffer = StringBuffer();
  var cursor = 0;

  for (final match in pattern.allMatches(data)) {
    final start = match.start;
    final end = match.end;
    if (_isInSkipRange(start, end, skipRanges)) {
      continue;
    }
    if (start < cursor) continue;

    final matched = match.group(0) ?? '';
    final entry = entriesByTitle[matched.trim().toLowerCase()];
    if (entry == null) continue;

    buffer.write(data.substring(cursor, start));
    buffer.write('[$matched](${entry.subject}:${entry.questId})');
    cursor = end;
  }

  if (cursor < data.length) {
    buffer.write(data.substring(cursor));
  }

  return buffer.toString();
}

bool _isInSkipRange(int start, int end, List<TextRange> ranges) {
  for (final range in ranges) {
    if (range.overlaps(start, end)) return true;
  }
  return false;
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
      current = TextRange(start: current.start, end: range.end > current.end ? range.end : current.end);
    } else {
      merged.add(current);
      current = range;
    }
  }
  merged.add(current);
  return merged;
}

extension on TextRange {
  bool overlaps(int start, int end) {
    return this.start < end && start < this.end;
  }
}

class DictionaryEntryPreviewSheet extends StatelessWidget {
  final DictionaryEntry entry;
  final VoidCallback onOpenDictionary;
  final VoidCallback? onOpenQuest;
  final VoidCallback? onCopyRoute;
  final VoidCallback? onSendToChat;

  const DictionaryEntryPreviewSheet({
    super.key,
    required this.entry,
    required this.onOpenDictionary,
    this.onOpenQuest,
    this.onCopyRoute,
    this.onSendToChat,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sheetStyle = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.55),
      listBullet: TextStyle(color: cs.onSurface, fontSize: 14),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(entry.subject, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: entry.description,
                  styleSheet: sheetStyle,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onSendToChat != null)
                  FilledButton.icon(
                    onPressed: onSendToChat,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Send in chat'),
                  ),
                if (onSendToChat != null) const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onOpenDictionary,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Open dictionary'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showDictionaryEntryPreviewSheet(
  BuildContext context, {
  required DictionaryEntry entry,
  required VoidCallback onOpenDictionary,
  VoidCallback? onOpenQuest,
  VoidCallback? onSendToChat,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      void closeThen(VoidCallback action) {
        Navigator.of(ctx).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          action();
        });
      }

      return DictionaryEntryPreviewSheet(
        entry: entry,
        onOpenDictionary: () => closeThen(onOpenDictionary),
        onOpenQuest: onOpenQuest == null ? null : () => closeThen(onOpenQuest),
        onSendToChat: onSendToChat == null ? null : () => closeThen(onSendToChat),
        onCopyRoute: () {
          Clipboard.setData(ClipboardData(text: entry.route));
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('Copied ${entry.title} link')),
          );
        },
      );
    },
  );
}


class _TextMatch {
  final int start;
  final int end;
  final DictionaryEntry? entry;
  final String? route;

  const _TextMatch({required this.start, required this.end, this.entry, this.route});
}

List<_TextMatch> _findMatches(String text, Map<String, DictionaryEntry> entriesByTitle) {
  final matches = <_TextMatch>[];

  final routeRegex = RegExp(r'(?<!\S)(/\S+)');
  for (final match in routeRegex.allMatches(text)) {
    final raw = match.group(1);
    if (raw == null || raw.isEmpty) continue;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.path.isEmpty) continue;
    if (!_isSupportedRoute(uri.path)) continue;
    matches.add(_TextMatch(start: match.start, end: match.end, route: raw));
  }

  final dictRegex = RegExp(
    _buildDictionaryPattern(entriesByTitle.keys.toList()),
    multiLine: true,
    caseSensitive: false,
  );
  for (final match in dictRegex.allMatches(text)) {
    final matched = match.group(0) ?? '';
    final entry = entriesByTitle[matched.trim().toLowerCase()];
    if (entry == null) continue;
    matches.add(_TextMatch(start: match.start, end: match.end, entry: entry));
  }

  matches.sort((a, b) {
    final startCompare = a.start.compareTo(b.start);
    if (startCompare != 0) return startCompare;
    return b.end.compareTo(a.end);
  });

  final filtered = <_TextMatch>[];
  var lastEnd = -1;
  for (final match in matches) {
    if (match.start < lastEnd) continue;
    filtered.add(match);
    lastEnd = match.end;
  }
  return filtered;
}

String _buildDictionaryPattern(List<String> titles) {
  final terms = titles.where((t) => t.trim().isNotEmpty).map(RegExp.escape).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (terms.isEmpty) return r'(?!x)x';
  return r'(?<!\w)(' + terms.join('|') + r')(?!\w)';
}

bool _isSupportedRoute(String path) {
  return path.startsWith('/feed/') || path == '/quests' || path.startsWith('/chat') || path == '/search' || path == '/dictionary' || path.startsWith('/themes');
}

