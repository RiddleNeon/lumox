part of 'search_screen.dart';

extension _SearchScreenSearchActions on _SearchScreenState {
  void _ensureTabData(int index) {
    final trimmedQuery = _controller.text.trim();
    if (trimmedQuery.isEmpty) {
      if (index == 2) _ensureDictionaryData();
      return;
    }

    final requestId = _searchRequestId;

    void onCountUpdated() {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {});
    }

    if (index == 0 && _videoQuery == null) {
      final nextVideoQuery = SearchQuery<Video>((limit, offset) async {
        final videos = widget.initialMode == SearchMode.tags
            ? await videoRepo.searchVideosByTagSupabase(trimmedQuery, limit: limit, offset: offset)
            : (await videoRepo.searchVideos(trimmedQuery, limit: limit, offset: offset, withAuthor: true, showYoutube: widget.showYoutube)).videos;
        return videos;
      }, widget.initialMode == SearchMode.tags ? null : () => videoRepo.countSearchVideos(trimmedQuery), onCountUpdated: onCountUpdated);
      if (mounted) {
        setState(() => _videoQuery = nextVideoQuery);
      } else {
        _videoQuery = nextVideoQuery;
      }
      _videoQuery?.preloadMore().catchError((_) {});
    }

    if (index == 1 && _userQuery == null) {
      final nextUserQuery = SearchQuery<UserProfile>((limit, offset) async {
        final result = await userRepository.searchUsers(trimmedQuery, limit: limit, offset: offset);
        return result.users;
      }, () => userRepository.countSearchUsers(trimmedQuery), onCountUpdated: onCountUpdated);
      if (mounted) {
        setState(() => _userQuery = nextUserQuery);
      } else {
        _userQuery = nextUserQuery;
      }
      _userQuery?.preloadMore().catchError((_) {});
    }

    if (index == 2) {
      _ensureDictionaryData();
    }
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
}

