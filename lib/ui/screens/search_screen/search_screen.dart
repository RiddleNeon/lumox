import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumox/base_logic.dart';
import 'package:lumox/logic/chat/chat.dart';
import 'package:lumox/logic/chat/chat_message.dart';
import 'package:lumox/logic/dictionary/dictionary_entry.dart';
import 'package:lumox/logic/local_storage/local_seen_service.dart';
import 'package:lumox/logic/repositories/dictionary_repository.dart';
import 'package:lumox/logic/repositories/video_repository.dart';
import 'package:lumox/logic/users/user_model.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/ui/misc/preloading_list.dart';
import 'package:lumox/ui/router/deep_link_builder.dart';
import 'package:lumox/ui/screens/search_screen/search_query.dart';
import 'package:lumox/ui/screens/search_screen/search_video_overlay.dart';
import 'package:lumox/ui/screens/search_screen/widgets/animated_search_bar.dart';
import 'package:lumox/ui/screens/search_screen/widgets/dictionary_entry_details_sheet.dart';
import 'package:lumox/ui/screens/search_screen/widgets/search_dictionary_tab.dart';
import 'package:lumox/ui/screens/search_screen/widgets/search_segment_button.dart';
import 'package:lumox/ui/screens/search_screen/widgets/search_user_card.dart';
import 'package:lumox/ui/screens/search_screen/widgets/search_video_card.dart';

import '../../theme/theme_ui_values.dart';
import '../../widgets/overlays/share_button.dart';
import '../auth_screen.dart';

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

    await Future.wait([if (nextVideoQuery != null) nextVideoQuery.preloadMore(), if (nextUserQuery != null) nextUserQuery.preloadMore(), ?dictionaryFuture]);

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
    // if (!_dictionaryPreparedShareContacts) {
    //   _dictionaryPreparedShareContacts = true;
    //   _prepareShareContacts();
    // }
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
    print("loading subjects now");
    final subjects = await dictionaryRepository.fetchSubjects();
    if (!mounted) return;
    setState(() {
      _dictionarySubjects = subjects;
      print("loaded subjects: $_dictionarySubjects");
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

  Set<ShareContact> _contactsForEntry(DictionaryEntry entry) {
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
    }).toSet();
  }

  Future<void> _shareToContact(ShareContact contact, DictionaryEntry entry) async {
    final chat = _chatByPartnerId[contact.id];
    if (chat == null) return;

    final message = ChatMessage(id: '${contact.id}-${DateTime.now().microsecondsSinceEpoch}', text: entry.route, isMe: true, timestamp: DateTime.now());

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
    await localSeenService.sendMessageLocal(chat, message);
    if (!mounted) return;
    print("PREPARING!");
    await _prepareShareContacts();
    print("PREPARED!");
  }

  Future<void> _openEntryDetails(BuildContext context, DictionaryEntry entry, List<DictionaryEntry> entries) async {
    final titleIndex = dictionaryRepository.buildTitleAliasIndex(entries, _dictionaryAliasIndex);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return DictionaryEntryDetailsSheet(
          entry: entry,
          entries: entries,
          titleIndex: titleIndex,
          loadContacts: () async {
            await _prepareShareContacts();

            return _contactsForEntry(entry);
          },
          onOpenQuest: () {
            Navigator.of(ctx).pop();
            context.go(entry.questRoute);
          },
          onShareToContact: (contact) => _shareToContact(contact, entry),
          dictionaryAliasIndex: _dictionaryAliasIndex,
        );
      },
    );
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
            Text('Find videos, creators and more!', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
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
            child: SearchSegmentButton(
              selected: _tabController.index == 0,
              onTap: () => _tabController.animateTo(0),
              icon: Icons.play_circle_outline,
              label: _videoQuery?.totalResults != null ? 'Videos (${_videoQuery!.totalResults})' : 'Videos',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SearchSegmentButton(
              selected: _tabController.index == 1,
              onTap: () => _tabController.animateTo(1),
              icon: Icons.person_outline,
              label: _userQuery?.totalResults != null ? 'Creators (${_userQuery!.totalResults})' : 'Creators',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SearchSegmentButton(
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
      return SearchDictionaryTab(
        entries: _dictionaryEntries,
        subjects: _dictionarySubjects,
        isLoading: _dictionaryLoading,
        query: _dictionaryQuery,
        selectedSubject: _dictionarySelectedSubject,
        colorScheme: Theme.of(context).colorScheme,
        onSubjectChanged: (value) {
          setState(() => _dictionarySelectedSubject = value);
          _loadDictionaryEntries(query: _controller.text);
        },
        onOpenEntry: (entry, entries) => _openEntryDetails(context, entry, entries),
        loadContacts: (entry) async {
          await _prepareShareContacts();
          return _contactsForEntry(entry);
        },
        onShareToContact: (contact, entry) => _shareToContact(contact, entry),
      );
    }

    return const SizedBox.shrink();
  }
}
