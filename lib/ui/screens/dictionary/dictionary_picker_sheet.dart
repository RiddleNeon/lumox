
import 'package:flutter/material.dart';
import 'package:lumox/logic/dictionary/dictionary_entry.dart';

class DictionaryPickerSheet extends StatefulWidget {
  final Future<List<DictionaryEntry>> entriesFuture;
  final void Function(DictionaryEntry entry) onSelect;

  const DictionaryPickerSheet({super.key, required this.entriesFuture, required this.onSelect});

  @override
  State<DictionaryPickerSheet> createState() => _DictionaryPickerSheetState();
}

class _DictionaryPickerSheetState extends State<DictionaryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedSubject;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text.trim()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search dictionary…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.primary, width: 1.4)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<DictionaryEntry>>(
                    future: widget.entriesFuture,
                    builder: (context, snapshot) {
                      final entries = snapshot.data ?? const <DictionaryEntry>[];
                      final subjects = <String>{for (final entry in entries) if (entry.subject.trim().isNotEmpty) entry.subject}.toList()
                        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                      if (_selectedSubject != null && !subjects.contains(_selectedSubject)) {
                        _selectedSubject = null;
                      }

                      return DropdownButtonFormField<String?>(
                        initialValue: _selectedSubject,
                        decoration: InputDecoration(
                          labelText: 'Subject',
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All subjects')),
                          ...subjects.map((subject) => DropdownMenuItem<String?>(value: subject, child: Text(subject))),
                        ],
                        onChanged: (value) => setState(() => _selectedSubject = value),
                      );
                    },
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<DictionaryEntry>>(
                future: widget.entriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final entries = snapshot.data ?? const <DictionaryEntry>[];
                  final filtered = entries.where((entry) {
                    if (_selectedSubject != null && entry.subject != _selectedSubject) return false;
                    if (_searchQuery.isEmpty) return true;
                    final haystack = '${entry.title}\n${entry.subject}\n${entry.description}'.toLowerCase();
                    return haystack.contains(_searchQuery.toLowerCase());
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        entries.isEmpty ? 'No dictionary entries found' : 'No entries match your filter',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      return ListTile(
                        onTap: () => widget.onSelect(entry),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        tileColor: cs.surfaceContainerLow,
                        title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(entry.previewSummary, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.send_rounded),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
