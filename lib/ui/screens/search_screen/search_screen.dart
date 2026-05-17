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
import 'package:lumox/ui/router/router.dart';
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

part 'search_screen_dictionary.dart';
part 'search_screen_search_actions.dart';
part 'search_screen_share.dart';
part 'search_screen_ui.dart';

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
  late PageController _pageController;

  bool _hasSearched = false;
  bool _loading = false;
  String? _skipNextDeepLinkSearchQuery;

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
    print("SearchScreen initState, time: ${DateTime.now().millisecondsSinceEpoch}");
    _dictionarySelectedSubject = widget.initialDictionarySubject?.trim();
    _tabController = TabController(length: 3, vsync: this);
    _pageController = PageController(initialPage: _tabController.index);

    _applyDeepLinkState(triggerSearch: true, notifyTabChange: false);

    if (widget.initialScope == SearchScope.dictionary && (widget.initialQuery == null || widget.initialQuery!.trim().isEmpty)) {
      _hasSearched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureDictionaryData();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPageToTab();
    });
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
    _applyDeepLinkState(triggerSearch: true, notifyTabChange: true);
  }

  void _applyDeepLinkState({required bool triggerSearch, required bool notifyTabChange}) {
    if (widget.initialScope == SearchScope.videos) {
      _setTabIndex(0, notify: notifyTabChange);
    } else if (widget.initialScope == SearchScope.profiles) {
      _setTabIndex(1, notify: notifyTabChange);
    } else if (widget.initialScope == SearchScope.dictionary) {
      _setTabIndex(2, notify: notifyTabChange);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPageToTab();
    });

    final initialQuery = widget.initialQuery?.trim();
    if (initialQuery == null || initialQuery.isEmpty) return;

    _controller.text = initialQuery;
    if (_skipNextDeepLinkSearchQuery == initialQuery) {
      _skipNextDeepLinkSearchQuery = null;
      return;
    }
    if (!triggerSearch) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _search(initialQuery);
    });
  }

  void _syncPageToTab({bool animate = false}) {
    if (!_pageController.hasClients) return;
    final targetIndex = _tabController.index;
    final currentIndex = (_pageController.page ?? _pageController.initialPage.toDouble()).round();
    if (currentIndex == targetIndex) return;
    if (animate) {
      _pageController.animateToPage(targetIndex, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    } else {
      _pageController.jumpToPage(targetIndex);
    }
  }

  void _setTabIndex(int index, {bool notify = true}) {
    if (_tabController.index == index) return;
    _tabController.index = index;
    _scheduleTabLoad(index);
  }

  void _scheduleTabLoad(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index == 2) {
        _ensureDictionaryData();
      }
    });
  }

  @override
  void dispose() {
    disposeThumbnailCache();
    _tabController.dispose();
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }
}
