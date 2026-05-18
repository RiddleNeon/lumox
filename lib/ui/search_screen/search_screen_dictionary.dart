part of 'search_screen.dart';

extension _SearchScreenDictionary on _SearchScreenState {
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
}

