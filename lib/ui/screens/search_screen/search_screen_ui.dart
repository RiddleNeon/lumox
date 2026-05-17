part of 'search_screen.dart';

extension _SearchScreenUi on _SearchScreenState {
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
      height: _SearchScreenState._kSearchBarHeight,
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
          hintText: 'Search videos, creators, tags...',
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

  Widget _buildMatteSection(
    ColorScheme cs, {
    required Widget child,
    EdgeInsets margin = const EdgeInsets.fromLTRB(12, 8, 12, 8),
    EdgeInsets padding = const EdgeInsets.all(8),
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }

  Widget _buildResultsBody(ColorScheme cs) {
    print("building results body, search bar visibility: $_searchBarVisibility, time: ${DateTime.now().millisecondsSinceEpoch}");
    return Column(
      children: [
        _buildMatteSection(
          cs,
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: [
              AnimatedSearchBar(
                visibility: _searchBarVisibility,
                slotHeight: _SearchScreenState._kSearchBarSlotHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(_SearchScreenState._kPadding, _SearchScreenState._kPadding + 8, _SearchScreenState._kPadding, _SearchScreenState._kPadding),
                  child: _buildSearchField(cs),
                ),
              ),
              _buildTabBar(cs, margin: const EdgeInsets.fromLTRB(8, 0, 8, 0)),
            ],
          ),
        ),
        Expanded(
          child: _buildMatteSection(
            cs,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(context.uiRadiusLg),
              child: PageView.builder(
                controller: _pageController,
                itemCount: 3,
                allowImplicitScrolling: true,
                onPageChanged: _handlePageChanged,
                itemBuilder: (context, index) => _buildTabPage(index),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabPage(int index) {
    switch (index) {
      case 0:
        return KeyedSubtree(key: const PageStorageKey('search_tab_videos'), child: _buildVideosTab());
      case 1:
        return KeyedSubtree(key: const PageStorageKey('search_tab_creators'), child: _buildCreatorsTab());
      case 2:
        return KeyedSubtree(key: const PageStorageKey('search_tab_dictionary'), child: _buildDictionaryTab());
      default:
        return const SizedBox.shrink();
    }
  }

  void _handleTabTap(int index) {
    if (_tabController.index == index) return;
    if (_pageController.hasClients) {
      _pageController.animateToPage(index, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.animateToPage(index, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      });
    }
    _ensureTabData(index);
  }

  void _handlePageChanged(int index) {
    _setTabIndex(index);
    _ensureTabData(index);
  }

  Widget _buildTabBar(ColorScheme cs, {EdgeInsets? margin}) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, child) {
        return Container(
          margin: margin ?? const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                  onTap: () => _handleTabTap(0),
                  icon: Icons.play_circle_outline,
                  label: _videoQuery != null && _videoQuery!.hasTotalCount ? 'Videos (${_videoQuery!.totalResults})' : 'Videos (...)',
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SearchSegmentButton(
                  selected: _tabController.index == 1,
                  onTap: () => _handleTabTap(1),
                  icon: Icons.person_outline,
                  label: _userQuery != null && _userQuery!.hasTotalCount ? 'Creators (${_userQuery!.totalResults})' : 'Creators (...)',
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SearchSegmentButton(
                  selected: _tabController.index == 2,
                  onTap: () => _handleTabTap(2),
                  icon: Icons.menu_book_outlined,
                  label: _dictionaryEntries.isNotEmpty ? 'Dictionary (${_dictionaryEntries.length})' : 'Dictionary (...)',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideosTab() {
    if (_videoQuery != null) {
      final query = _videoQuery!;
      print("building video list with ${query.results.length} preloaded videos, total count: ${query.totalResults}, time: ${DateTime.now().millisecondsSinceEpoch}");
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

    return const SizedBox.shrink();
  }

  Widget _buildCreatorsTab() {
    if (_userQuery != null) {
      final query = _userQuery!;
      return PreloadingSliverList<UserProfile>(
        key: ValueKey(query),
        query: query,
        emptyStateLabel: 'No creators found',
        itemBuilder: (context, user) => UserCard(initialUser: user, cs: Theme.of(context).colorScheme, key: ValueKey(user.id)),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildDictionaryTab() {
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
}
