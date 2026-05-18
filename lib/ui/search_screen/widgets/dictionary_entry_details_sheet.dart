import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:lumox/logic/dictionary/dictionary_entry.dart';
import 'package:lumox/logic/repositories/dictionary_repository.dart';
import 'package:lumox/ui/widgets/dictionary/dictionary_linkifier.dart';
import 'package:lumox/ui/widgets/overlays/buttons/share_button.dart';

class DictionaryEntryDetailsSheet extends StatelessWidget {
  final DictionaryEntry entry;
  final List<DictionaryEntry> entries;
  final Map<String, DictionaryEntry> titleIndex;
  final Future<Set<ShareContact>> Function() loadContacts;
  final VoidCallback onOpenQuest;
  final Future<void> Function(ShareContact contact) onShareToContact;
  final Map<String, int> dictionaryAliasIndex;

  const DictionaryEntryDetailsSheet({
    super.key,
    required this.entry,
    required this.entries,
    required this.titleIndex,
    required this.loadContacts,
    required this.onOpenQuest,
    required this.onShareToContact,
    required this.dictionaryAliasIndex,
  });

  String _difficultyLabel(double d) {
    if (d < 0.2) return 'Beginner';
    if (d < 0.4) return 'Novice';
    if (d < 0.6) return 'Intermediate';
    if (d < 0.8) return 'Advanced';
    return 'Expert';
  }

  Color _difficultyColor(double d, ColorScheme cs) {
    if (d < 0.4) return cs.tertiary;
    if (d < 0.7) return cs.primary;
    return cs.error;
  }

  String _formatPrerequisites(DictionaryEntry entry) {
    if (entry.prerequisites.isEmpty) return '';
    final names = entry.prerequisites.map((p) => p.title).toList();
    final visible = names.take(4).toList();
    final extra = names.length - visible.length;
    final base = visible.join(', ');
    return extra > 0 ? '$base +$extra' : base;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final difficultyColor = _difficultyColor(entry.difficulty, cs);
    final prereqText = _formatPrerequisites(entry);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.subject,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  ShareButton(
                    shareUrl: entry.route,
                    loadContacts: loadContacts,
                    emptyStateLabel: 'No chats yet',
                    onShareToContact: (contact, _) => onShareToContact(contact),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: difficultyColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: difficultyColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${_difficultyLabel(entry.difficulty)} · ${((entry.difficulty).clamp(0.0, 1.0) * 100).round()}%',
                      style: TextStyle(color: difficultyColor, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text('Quest #${entry.questId}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
              if (prereqText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Recommended prerequisites: $prereqText', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.4)),
              ],
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
                child: SingleChildScrollView(
                  child: DictionaryMarkdownBody(
                    data: entry.description,
                    entries: entries,
                    titleIndex: dictionaryRepository.buildTitleAliasIndex(entries, dictionaryAliasIndex),
                    linkColor: cs.primary,
                    onTapEntry: (dictionaryEntry) => showDictionaryEntryPreviewSheet(
                      context,
                      entry: dictionaryEntry,
                      onOpenQuest: () => context.go(dictionaryEntry.questRoute),
                      onOpenDictionary: () => context.go(dictionaryEntry.route),
                    ),
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: TextStyle(color: cs.onSurface, fontSize: 14.5, height: 1.55),
                      h1: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800),
                      h2: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800),
                      h3: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(onPressed: onOpenQuest, icon: const Icon(Icons.center_focus_strong_rounded), label: const Text('Open quest')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

