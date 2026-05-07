import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:lumox/logic/dictionary/dictionary_entry.dart';
import 'package:lumox/logic/repositories/dictionary_repository.dart';
import 'package:lumox/ui/widgets/dictionary/dictionary_linkifier.dart';
import 'package:lumox/logic/chat/chat.dart';
import 'package:lumox/logic/chat/chat_message.dart';
import 'package:lumox/logic/local_storage/local_seen_service.dart';
import 'package:lumox/ui/widgets/overlays/share_button.dart';

import '../../../base_logic.dart';

class DictionaryScreen extends StatefulWidget {
  final String? initialSubject;
  final int? initialEntryId;

  const DictionaryScreen({super.key, this.initialSubject, this.initialEntryId});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _searchDebounce;
  Set<String> _subjects = const {};

  String? _selectedSubject;
  String _searchQuery = '';
  bool _autoOpenedPreview = false;

  List<DictionaryEntry> _entries = const [];
  bool _isLoading = false;
  int _searchRequestId = 0;

  List<ShareContact> _shareContacts = const [];
  final Map<String, Chat> _chatByPartnerId = {};
  final Map<String, Map<String, DateTime>> _lastSharedLinkByPartnerId = {};

  @override
  void initState() {
	super.initState();
	_selectedSubject = widget.initialSubject;
	_searchController.addListener(_onSearchChanged);
	_loadSubjects();
	_loadEntries();
	WidgetsBinding.instance.addPostFrameCallback((_) {
	  if (!mounted) return;
	  _prepareShareContacts();
	});
  }

  @override
  void dispose() {
	_searchDebounce?.cancel();
	_searchController.dispose();
	_scrollController.dispose();
	super.dispose();
  }

  Future<void> _loadSubjects() async {
    final subjects = await dictionaryRepository.fetchSubjects();
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      if (_selectedSubject != null && !_subjects.contains(_selectedSubject)) {
        _selectedSubject = null;
        _loadEntries();
      }
    });
  }

  Future<List<DictionaryEntry>> _fetchEntriesForState() {
    if (_searchQuery.isEmpty) {
      return dictionaryRepository.fetchEntries(subject: _selectedSubject);
    }
    return dictionaryRepository.searchEntries(subject: _selectedSubject, query: _searchQuery);
  }

  Future<void> _loadEntries() async {
    final requestId = ++_searchRequestId;
    setState(() => _isLoading = true);
    try {
      final entries = await _fetchEntriesForState();
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _entries = entries);
    } finally {
      if (mounted && requestId == _searchRequestId) setState(() => _isLoading = false);
    }
  }

  void _refreshEntries() => _loadEntries();

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final query = _searchController.text.trim();
      if (query == _searchQuery) return;
      setState(() => _searchQuery = query);
      _loadEntries();
    });
  }

  Future<void> _prepareShareContacts() async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final chats = localSeenService.getChats();
    final contacts = <ShareContact>[];
    final chatMap = <String, Chat>{};
    final lastSharedLinkByPartnerId = <String, Map<String, DateTime>>{};

    for (final chat in chats) {
      final messages = await localSeenService.getMessagesWithLocal(
        chat.partnerId,
        limit: 180,
        startOffset: now.add(const Duration(seconds: 1)),
      );
      final myRecentMessages = messages.where((message) => message.isMe && message.timestamp.isAfter(thirtyDaysAgo)).toList();
      final lastSharedAt = myRecentMessages.isEmpty ? chat.lastMessageAt : myRecentMessages.last.timestamp;

      final sharedLinks = <String, DateTime>{};
      for (final message in messages) {
        if (!message.isMe) continue;
        final link = message.text.trim();
        if (link.isEmpty) continue;
        final existing = sharedLinks[link];
        if (existing == null || message.timestamp.isAfter(existing)) {
          sharedLinks[link] = message.timestamp;
        }
      }
      lastSharedLinkByPartnerId[chat.partnerId] = sharedLinks;

      contacts.add(
        ShareContact(
          id: chat.partnerId,
          name: chat.partnerName,
          avatarUrl: chat.partnerProfileImageUrl,
          recentShareCount: myRecentMessages.length,
          lastSharedAt: lastSharedAt,
        ),
      );
      chatMap[chat.partnerId] = chat;
    }

    if (!mounted) return;
    setState(() {
      _shareContacts = contacts;
      _lastSharedLinkByPartnerId
        ..clear()
        ..addAll(lastSharedLinkByPartnerId);
      _chatByPartnerId
        ..clear()
        ..addAll(chatMap);
    });
  }

  List<ShareContact> _contactsForEntry(DictionaryEntry entry) {
    final link = entry.route;
    return _shareContacts.map((contact) {
      final lastSharedAt = _lastSharedLinkByPartnerId[contact.id]?[link];
      return ShareContact(
        id: contact.id,
        name: contact.name,
        avatarUrl: contact.avatarUrl,
        recentShareCount: contact.recentShareCount,
        lastSharedAt: contact.lastSharedAt,
        alreadySharedWithThisVideo: lastSharedAt != null,
        lastSharedThisVideoAt: lastSharedAt,
      );
    }).toList();
  }

  Future<void> _shareToContact(ShareContact contact, DictionaryEntry entry) async {
    final chat = _chatByPartnerId[contact.id];
    if (chat == null) return;

    final message = ChatMessage(
      id: '${contact.id}-${DateTime.now().microsecondsSinceEpoch}',
      text: entry.route,
      isMe: true,
      timestamp: DateTime.now(),
    );

    await chatRepository.sendNotification(chat: chat, message: message);
    await localSeenService.sendMessageLocal(chat, message);
    if (!mounted) return;
    await _prepareShareContacts();
  }

  Future<void> _openEntryDetails(BuildContext context, DictionaryEntry entry, List<DictionaryEntry> entries) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return _DictionaryEntryDetailsSheet(
          entry: entry,
          entries: entries,
          shareContacts: _contactsForEntry(entry),
          onOpenQuest: () {
            Navigator.of(ctx).pop();
            context.go(entry.questRoute);
          },
          onShareToContact: (contact) => _shareToContact(contact, entry),
        );
      },
    );
  }

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
	final cs = Theme.of(context).colorScheme;
	final entries = _entries;
	final subjects = _subjects;
	final filtered = entries;

	if (!_autoOpenedPreview && widget.initialEntryId != null && entries.isNotEmpty) {
	  DictionaryEntry? target;
	  for (final entry in filtered) {
		if (entry.questId == widget.initialEntryId) {
		  target = entry;
		  break;
		}
	  }
	  if (target != null) {
		_autoOpenedPreview = true;
		WidgetsBinding.instance.addPostFrameCallback((_) {
		  if (!mounted) return;
		  _openEntryDetails(context, target!, entries);
		});
	  }
	}

	return Scaffold(
	  appBar: AppBar(title: const Text('Dictionary'), centerTitle: true),
	  body: Column(
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
				if (_isLoading) ...[
				  const SizedBox(height: 8),
				  LinearProgressIndicator(color: cs.primary, minHeight: 2),
				],
				const SizedBox(height: 10),
				Row(
				  children: [
					Expanded(
					  child: DropdownButtonFormField<String?>(
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
						onChanged: (value) {
						  setState(() => _selectedSubject = value);
						  _refreshEntries();
						},
					  ),
					),
					const SizedBox(width: 10),
					Text(
					  _searchQuery.isEmpty && _selectedSubject == null
						  ? '${entries.length} entries'
						  : '${entries.length} results',
					  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
					),
				  ],
				),
			  ],
			),
		  ),
		  Expanded(
			child: filtered.isEmpty
				? Center(
					child: Text(
					  entries.isEmpty
						  ? (_searchQuery.isEmpty && _selectedSubject == null ? 'No dictionary entries found' : 'No entries match your filter')
						  : 'No dictionary entries found',
					  style: TextStyle(color: cs.onSurfaceVariant),
					),
				  )
				: ListView.separated(
					controller: _scrollController,
					padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
					itemCount: filtered.length,
					separatorBuilder: (_, _) => const SizedBox(height: 10),
					itemBuilder: (context, index) {
					  final entry = filtered[index];
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
						  onTap: () => _openEntryDetails(context, entry, entries),
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
									  contacts: _contactsForEntry(entry),
									  emptyStateLabel: 'No chats yet',
									  onShareToContact: (contact, _) => _shareToContact(contact, entry),
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
						));
					},
				  ),
		  ),
		],
	  ),
	);
  }
}

class _DictionaryEntryDetailsSheet extends StatelessWidget {
  final DictionaryEntry entry;
  final List<DictionaryEntry> entries;
  final List<ShareContact> shareContacts;
  final VoidCallback onOpenQuest;
  final Future<void> Function(ShareContact contact) onShareToContact;

  const _DictionaryEntryDetailsSheet({
    required this.entry,
    required this.entries,
    required this.shareContacts,
    required this.onOpenQuest,
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
                      Text(entry.title, style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(entry.subject, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                ShareButton(
                  shareUrl: entry.route,
                  contacts: shareContacts,
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
              Text(
                'Recommended prerequisites: $prereqText',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
              child: SingleChildScrollView(
                child: DictionaryMarkdownBody(
                  data: entry.description,
                  entries: entries,
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
              child: FilledButton.icon(
                onPressed: onOpenQuest,
                icon: const Icon(Icons.center_focus_strong_rounded),
                label: const Text('Open quest'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
