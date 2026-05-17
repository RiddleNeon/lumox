import 'package:flutter/material.dart';
import 'package:lumox/logic/dictionary/dictionary_entry.dart';
import 'package:lumox/ui/widgets/overlays/share_button.dart';

class SearchDictionaryTab extends StatelessWidget {
  final List<DictionaryEntry> entries;
  final Set<String> subjects;
  final bool isLoading;
  final String query;
  final String? selectedSubject;
  final ColorScheme colorScheme;
  final ValueChanged<String?> onSubjectChanged;
  final void Function(DictionaryEntry entry, List<DictionaryEntry> entries) onOpenEntry;
  final Future<Set<ShareContact>> Function(DictionaryEntry entry) loadContacts;
  final Future<void> Function(ShareContact contact, DictionaryEntry entry) onShareToContact;

  const SearchDictionaryTab({
    super.key,
    required this.entries,
    required this.subjects,
    required this.isLoading,
    required this.query,
    required this.selectedSubject,
    required this.colorScheme,
    required this.onSubjectChanged,
    required this.onOpenEntry,
    required this.loadContacts,
    required this.onShareToContact,
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

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final hasQuery = query.isNotEmpty;
    final hasSubjectFilter = selectedSubject != null;
    final emptyLabel = hasQuery || hasSubjectFilter ? 'No entries match your filter' : 'No dictionary entries found';
    final safeSelectedSubject = subjects.contains(selectedSubject) ? selectedSubject : null;
    final subjectItems = subjects.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: safeSelectedSubject,
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All subjects')),
                    ...subjectItems.map((subject) => DropdownMenuItem<String?>(value: subject, child: Text(subject))),
                    if (safeSelectedSubject == null && selectedSubject != null)
                      DropdownMenuItem<String?>(value: selectedSubject, child: Text(selectedSubject ?? '')),
                  ],
                  onChanged: onSubjectChanged,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                hasQuery || hasSubjectFilter ? '${entries.length} results' : '${entries.length} entries',
                style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (isLoading) LinearProgressIndicator(color: cs.primary, minHeight: 2),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(emptyLabel, style: TextStyle(color: cs.onSurfaceVariant)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final difficultyColor = _difficultyColor(entry.difficulty, cs);
                    return Card(
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => onOpenEntry(entry, entries),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  ),
                                  ShareButton(
                                    shareUrl: entry.route,
                                    loadContacts: () async => loadContacts(entry),
                                    emptyStateLabel: 'No chats yet',
                                    onShareToContact: (contact, _) => onShareToContact(contact, entry),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Chip(
                                    label: Text(entry.subject),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
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
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
