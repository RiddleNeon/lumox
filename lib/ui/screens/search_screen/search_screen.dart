import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:lumox/base_logic.dart';
import 'package:lumox/logic/chat/chat.dart';
import 'package:lumox/logic/chat/chat_message.dart';
import 'package:lumox/logic/dictionary/dictionary_entry.dart';
import 'package:lumox/logic/feed_recommendation/search_video_result_recommender.dart';
import 'package:lumox/logic/local_storage/local_seen_service.dart';
import 'package:lumox/logic/repositories/dictionary_repository.dart';
import 'package:lumox/logic/repositories/video_repository.dart';
import 'package:lumox/logic/users/user_model.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/ui/animations/slide_morph_transitions.dart';
import 'package:lumox/ui/misc/preloading_list.dart';
import 'package:lumox/ui/router/deep_link_builder.dart';
import 'package:lumox/ui/screens/search_screen/search_query.dart';
import 'package:lumox/ui/screens/search_screen/widgets/animated_search_bar.dart';
import 'package:lumox/ui/screens/search_screen/widgets/search_user_card.dart';
import 'package:lumox/ui/screens/search_screen/widgets/search_video_card.dart';
import 'package:lumox/ui/video/short_video_player.dart';
import 'package:lumox/ui/widgets/dictionary/dictionary_linkifier.dart';
import 'package:lumox/ui/widgets/overlays/share_button.dart';

import '../../theme/theme_ui_values.dart';

enum SearchScope { videos, profiles, dictionary, all }

enum SearchMode { text, tags }

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.initialQuery,
    this.initialScope = SearchScope.all,
    this.initialMode = SearchMode.text,
    required this.showYoutube,
    this.initialDictionarySubject,
    this.initialDictionaryEntryId,
  });

  final String? initialQuery;
  final SearchScope initialScope;
  final SearchMode initialMode;
  final bool showYoutube;
  final String? initialDictionarySubject;
  final int? initialDictionaryEntryId;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  late TabController _tabController;

  bool _hasSearched = false;
  bool _loading = false;

  SearchQuery<Video>? _videoQuery;
  SearchQuery<UserProfile>? _userQuery;

  List<DictionaryEntry> _dictionaryEntries = const [];
  Set<String> _dictionarySubjects = const {};
  String? _dictionarySelectedSubject;
  String _dictionaryQuery = '';
  String? _dictionaryLoadedSubject;
  bool _dictionaryLoading = false;
  bool _dictionaryAutoOpenedPreview = false;
  bool _dictionaryPreparedShareContacts = false;
  Map<String, int> _dictionaryAliasIndex = const {};

  int _searchRequestId = 0;
  int _dictionaryRequestId = 0;

  List<ShareContact> _shareContacts = const [];
  final Map<String, Chat> _chatByPartnerId = {};
  final Map<String, Map<String, DateTime>> _lastSharedLinkByPartnerId = {};

  static const _kSearchBarHeight = 56.0;
  static const _kPadding = 16.0;
  static const _kSearchBarSlotHeight = _kSearchBarHeight + _kPadding * 2;

  double _searchBarVisibility = 1.0;

  @override
  void initState() {
    super.initState();
    _dictionarySelectedSubject = widget.initialDictionarySubject?.trim();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
      if (_tabController.index == 2) {
        _ensureDictionaryData();
      }
    });

    _applyDeepLinkState(triggerSearch: true);

    if (widget.initialScope == SearchScope.dictionary && (widget.initialQuery == null || widget.initialQuery!.trim().isEmpty)) {
      _hasSearched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureDictionaryData();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(backgroundColor: cs.surface, body: _hasSearched ? _buildResultsBody(cs) : _buildLandingBody(cs));
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery == widget.initialQuery &&
        oldWidget.initialScope == widget.initialScope &&
        oldWidget.initialMode == widget.initialMode &&
        oldWidget.initialDictionarySubject == widget.initialDictionarySubject &&
        oldWidget.initialDictionaryEntryId == widget.initialDictionaryEntryId) {
      return;
    }
    _dictionarySelectedSubject = widget.initialDictionarySubject?.trim();
    _dictionaryAutoOpenedPreview = false;
    _applyDeepLinkState(triggerSearch: true);
  }

  void _applyDeepLinkState({required bool triggerSearch}) {
    if (widget.initialScope == SearchScope.videos) {
      _tabController.index = 0;
    } else if (widget.initialScope == SearchScope.profiles) {
      _tabController.index = 1;
    } else if (widget.initialScope == SearchScope.dictionary) {
      _tabController.index = 2;
    }

    final initialQuery = widget.initialQuery?.trim();
    if (initialQuery == null || initialQuery.isEmpty) return;

    _controller.text = initialQuery;
    if (!triggerSearch) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _search(initialQuery);
    });
  }

  @override
  void dispose() {
    disposeThumbnailCache();
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search([String? val]) async {
    val ??= _controller.text;
    final trimmedQuery = val.trim();
    final isDictionaryScope = widget.initialScope == SearchScope.dictionary || _tabController.index == 2;
    if (trimmedQuery.isEmpty && !isDictionaryScope) return;

    final scope = widget.initialScope == SearchScope.all
        ? DeepLinkSearchScope.all
        : (_tabController.index == 0
              ? DeepLinkSearchScope.videos
              : (_tabController.index == 1 ? DeepLinkSearchScope.profiles : DeepLinkSearchScope.dictionary));

    final targetUrl = DeepLinkBuilder.search(
      query: trimmedQuery,
      scope: scope,
      mode: widget.initialMode == SearchMode.tags ? DeepLinkSearchMode.tags : DeepLinkSearchMode.text,
    );
    final currentUri = GoRouterState.of(context).uri.toString();
    if (currentUri != targetUrl) {
      context.replace(targetUrl);
    }

    final requestId = ++_searchRequestId;
    FocusScope.of(context).unfocus();

    setState(() {
      _hasSearched = true;
      _loading = true;
      _searchBarVisibility = 1.0;
    });

    SearchQuery<UserProfile>? nextUserQuery;
    SearchQuery<Video>? nextVideoQuery;
    Future<List<DictionaryEntry>>? dictionaryFuture;

    if (widget.initialScope != SearchScope.profiles && widget.initialScope != SearchScope.dictionary) {
      nextVideoQuery = SearchQuery<Video>((limit, offset) async {
        final videos = widget.initialMode == SearchMode.tags
            ? await videoRepo.searchVideosByTagSupabase(trimmedQuery, limit: limit, offset: offset)
            : (await videoRepo.searchVideos(trimmedQuery, limit: limit, offset: offset, withAuthor: true, showYoutube: widget.showYoutube)).videos;
        return videos;
      }, () => videoRepo.countSearchVideos(trimmedQuery));
    }

    if (widget.initialScope != SearchScope.videos && widget.initialScope != SearchScope.dictionary) {
      nextUserQuery = SearchQuery<UserProfile>((limit, offset) async {
        final result = await userRepository.searchUsers(trimmedQuery, limit: limit, offset: offset);
        return result.users;
      }, () => userRepository.countSearchUsers(trimmedQuery));
    }

    if (widget.initialScope != SearchScope.videos && widget.initialScope != SearchScope.profiles) {
      _ensureDictionaryData(loadEntries: false);
      setState(() => _dictionaryLoading = true);
      dictionaryFuture = _fetchDictionaryEntriesForQuery(trimmedQuery);
    }

    await Future.wait([
      if (nextVideoQuery != null) nextVideoQuery.preloadMore(),
      if (nextUserQuery != null) nextUserQuery.preloadMore(),
      ?dictionaryFuture,
    ]);

    final dictionaryEntries = dictionaryFuture == null ? null : await dictionaryFuture;
    if (requestId != _searchRequestId) return;
    if (!mounted) return;

    setState(() {
      _videoQuery = nextVideoQuery;
      _userQuery = nextUserQuery;
      _loading = false;
      if (dictionaryEntries != null) {
        _dictionaryEntries = dictionaryEntries;
        _dictionaryLoading = false;
        _dictionaryQuery = trimmedQuery;
        _dictionaryLoadedSubject = _dictionarySelectedSubject;
      }
    });

    if (dictionaryEntries != null) {
      _maybeAutoOpenDictionaryPreview(dictionaryEntries);
    }
  }

  void _ensureDictionaryData({bool loadEntries = true}) {
    if (!_dictionaryPreparedShareContacts) {
      _dictionaryPreparedShareContacts = true;
      _prepareShareContacts();
    }
    if (_dictionarySubjects.isEmpty) {
      _loadDictionarySubjects();
    }
    if (_dictionaryAliasIndex.isEmpty) {
      _loadDictionaryAliases();
    }
    if (!loadEntries) return;
    final currentQuery = _controller.text.trim();
    if (_dictionaryEntries.isNotEmpty && _dictionaryQuery == currentQuery && _dictionaryLoadedSubject == _dictionarySelectedSubject) {
      return;
    }
    _loadDictionaryEntries(query: currentQuery);
  }

  Future<void> _loadDictionarySubjects() async {
    final subjects = await dictionaryRepository.fetchSubjects();
    if (!mounted) return;
    setState(() {
      _dictionarySubjects = subjects;
      if (_dictionarySelectedSubject != null && !_dictionarySubjects.contains(_dictionarySelectedSubject)) {
        _dictionarySelectedSubject = null;
      }
    });
  }

  Future<void> _loadDictionaryAliases() async {
    final aliasIndex = await dictionaryRepository.fetchAliasIndex();
    if (!mounted) return;
    setState(() => _dictionaryAliasIndex = aliasIndex);
  }

  Future<List<DictionaryEntry>> _fetchDictionaryEntriesForQuery(String query) {
    if (query.trim().isEmpty) {
      return dictionaryRepository.fetchEntries(subject: _dictionarySelectedSubject);
    }
    return dictionaryRepository.searchEntries(subject: _dictionarySelectedSubject, query: query);
  }

  Future<void> _loadDictionaryEntries({String? query}) async {
    final trimmedQuery = (query ?? _controller.text).trim();
    final requestId = ++_dictionaryRequestId;
    setState(() => _dictionaryLoading = true);
    try {
      final entries = await _fetchDictionaryEntriesForQuery(trimmedQuery);
      if (!mounted || requestId != _dictionaryRequestId) return;
      setState(() {
        _dictionaryEntries = entries;
        _dictionaryQuery = trimmedQuery;
        _dictionaryLoadedSubject = _dictionarySelectedSubject;
      });
      _maybeAutoOpenDictionaryPreview(entries);
    } finally {
      if (mounted && requestId == _dictionaryRequestId) setState(() => _dictionaryLoading = false);
    }
  }

  void _maybeAutoOpenDictionaryPreview(List<DictionaryEntry> entries) {
    if (_dictionaryAutoOpenedPreview || widget.initialDictionaryEntryId == null) return;
    final target = entries.where((entry) => entry.questId == widget.initialDictionaryEntryId).toList();
    if (target.isEmpty) return;
    _dictionaryAutoOpenedPreview = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openEntryDetails(context, target.first, entries);
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
      final messages = await localSeenService.getMessagesWithLocal(chat.partnerId, limit: 180, startOffset: now.add(const Duration(seconds: 1)));
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

    final message = ChatMessage(id: '${contact.id}-${DateTime.now().microsecondsSinceEpoch}', text: entry.route, isMe: true, timestamp: DateTime.now());

    await chatRepository.sendNotification(chat: chat, message: message);
    await localSeenService.sendMessageLocal(chat, message);
    if (!mounted) return;
    await _prepareShareContacts();
  }

  Future<void> _openEntryDetails(BuildContext context, DictionaryEntry entry, List<DictionaryEntry> entries) async {
    final titleIndex = dictionaryRepository.buildTitleAliasIndex(entries, _dictionaryAliasIndex);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return _DictionaryEntryDetailsSheet(
          entry: entry,
          entries: entries,
          titleIndex: titleIndex,
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

  Widget _buildLandingBody(ColorScheme cs) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 560),
              tween: Tween(begin: 0.94, end: 1),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: Text(
                'Discover',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: -1, color: cs.secondary),
              ),
            ),
            const SizedBox(height: 8),
            Text('Find videos & creators', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
            const SizedBox(height: 256),
            _buildSearchField(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(ColorScheme cs) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      height: _kSearchBarHeight,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.9)),
      ),
      child: TextField(
        controller: _controller,
        onSubmitted: _search,
        style: TextStyle(color: cs.onSurface, fontSize: 16),
        cursorColor: cs.primary,
        decoration: InputDecoration(
          hintText: 'Search videos, creators, tags…',
          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant, size: 22),
          suffixIcon: GestureDetector(
            onTap: _search,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(context.uiRadiusMd)),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: _loading ? 0.92 : 1,
                child: Icon(Icons.arrow_forward_rounded, color: cs.onTertiaryContainer, size: 20),
              ),
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        ),
      ),
    );
  }

  Widget _buildResultsBody(ColorScheme cs) {
    return Column(
      children: [
        AnimatedSearchBar(
          visibility: _searchBarVisibility,
          slotHeight: _kSearchBarSlotHeight,
          child: Padding(padding: const EdgeInsets.fromLTRB(_kPadding, _kPadding + 8, _kPadding, _kPadding), child: _buildSearchField(cs)),
        ),
        _buildTabBar(cs),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(key: ValueKey('tab_${_tabController.index}'), child: _buildTabContent()),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SearchSegmentButton(
              selected: _tabController.index == 0,
              onTap: () => _tabController.animateTo(0),
              icon: Icons.play_circle_outline,
              label: _videoQuery?.totalResults != null ? 'Videos (${_videoQuery!.totalResults})' : 'Videos',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SearchSegmentButton(
              selected: _tabController.index == 1,
              onTap: () => _tabController.animateTo(1),
              icon: Icons.person_outline,
              label: _userQuery?.totalResults != null ? 'Creators (${_userQuery!.totalResults})' : 'Creators',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SearchSegmentButton(
              selected: _tabController.index == 2,
              onTap: () => _tabController.animateTo(2),
              icon: Icons.menu_book_outlined,
              label: _dictionaryEntries.isNotEmpty ? 'Dictionary (${_dictionaryEntries.length})' : 'Dictionary',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    if (_tabController.index == 0 && _videoQuery != null) {
      final query = _videoQuery!;
      return PreloadingSliverList<Video>(
        key: ValueKey(query),
        query: query,
        emptyStateLabel: 'No videos found',
        itemBuilder: (context, video) {
          final videos = List<Video>.unmodifiable(query.results);
          final index = videos.indexOf(video);
          if (index < 0) return const SizedBox.shrink();
          return VideoCard(
            video: video,
            cs: Theme.of(context).colorScheme,
            onTap: () async {
              await openVideoPlayer(context: context, listedVideos: videos, videoIndex: index);
            },
          );
        },
      );
    }

    if (_tabController.index == 1 && _userQuery != null) {
      final query = _userQuery!;
      return PreloadingSliverList<UserProfile>(
        key: ValueKey(query),
        query: query,
        emptyStateLabel: 'No creators found',
        itemBuilder: (context, user) => UserCard(initialUser: user, cs: Theme.of(context).colorScheme, key: ValueKey(user.id)),
      );
    }

    if (_tabController.index == 2) {
      return _buildDictionaryTab(Theme.of(context).colorScheme);
    }

    return const SizedBox.shrink();
  }

  Widget _buildDictionaryTab(ColorScheme cs) {
    final entries = _dictionaryEntries;
    final subjects = _dictionarySubjects;
    final isLoading = _dictionaryLoading;
    final hasQuery = _dictionaryQuery.isNotEmpty;
    final hasSubjectFilter = _dictionarySelectedSubject != null;
    final emptyLabel = hasQuery || hasSubjectFilter ? 'No entries match your filter' : 'No dictionary entries found';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _dictionarySelectedSubject,
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
                    ...subjects.map((subject) => DropdownMenuItem<String?>(value: subject, child: Text(subject))),
                  ],
                  onChanged: (value) {
                    setState(() => _dictionarySelectedSubject = value);
                    _loadDictionaryEntries(query: _controller.text);
                  },
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
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Returns the number of likes added (can be negative if user unliked videos)
Future<int> openVideoPlayer({required BuildContext context, required List<Video> listedVideos, required int videoIndex}) async {
  int likes = 0;
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'VideoOverlay',
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, _) => SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(context.uiRadiusLg),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                VideoFeed(
                  customVideoProvider: SearchVideoResultRecommender(listedVideos: listedVideos),
                  itemCount: listedVideos.length,
                  initialPage: videoIndex,
                  onLikeChanged: (liked) => likes += liked ? 1 : -1,
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.inverseSurface.withValues(alpha: 0.85), shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onInverseSurface, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      return SlideMorphTransitions.build(animation, child, beginOffset: const Offset(0, 0.08), beginScale: 0.88);
    },
  );
  return likes;
}

class _SearchSegmentButton extends StatelessWidget {
  const _SearchSegmentButton({required this.selected, required this.onTap, required this.icon, required this.label});

  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.uiRadiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          color: selected ? cs.secondaryContainer.withValues(alpha: 0.75) : Colors.transparent,
          border: selected ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)) : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
            color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DictionaryEntryDetailsSheet extends StatelessWidget {
  final DictionaryEntry entry;
  final List<DictionaryEntry> entries;
  final Map<String, DictionaryEntry> titleIndex;
  final List<ShareContact> shareContacts;
  final VoidCallback onOpenQuest;
  final Future<void> Function(ShareContact contact) onShareToContact;

  const _DictionaryEntryDetailsSheet({
    required this.entry,
    required this.entries,
    required this.titleIndex,
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
                Text('Recommended prerequisites: $prereqText', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.4)),
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
              Flexible(
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(onPressed: onOpenQuest, icon: const Icon(Icons.center_focus_strong_rounded), label: const Text('Open quest')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
