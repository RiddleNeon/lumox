class SearchQuery<T> {
  Future<List<T>> Function(int limit, int offset) executeQuery;
  Future<int> Function()? countQuery;

  List<T> results = [];
  int totalResults = 0;
  int _offset = 0;
  bool _hasMoreContent = true;
  bool _didLoadTotalCount = false;
  Future<int>? _countTask;
  void Function()? onCountUpdated;

  bool get isCompleted => currentLoadingTask == null;
  bool get hasTotalCount => _didLoadTotalCount;

  SearchQuery(this.executeQuery, this.countQuery, {this.onCountUpdated});

  Future<void>? currentLoadingTask;

  Future<void> preloadMore({int limit = 20}) async {
    if (currentLoadingTask != null) {
      return currentLoadingTask;
    }
    if (!_hasMoreContent) {
      return Future.value();
    }
    currentLoadingTask = _preloadMore(limit: limit).whenComplete(() {
      currentLoadingTask = null;
    });
    return currentLoadingTask;
  }

  Future<void> _preloadMore({int limit = 20}) async {
    final queryResult = await executeQuery(limit, _offset);
    results.addAll(queryResult);
    _offset += queryResult.length;
    _hasMoreContent = queryResult.length == limit;

    if (_didLoadTotalCount || countQuery == null) {
      return;
    }

    if (_offset == queryResult.length && results.isEmpty) {
      totalResults = 0;
      _didLoadTotalCount = true;
      onCountUpdated?.call();
      return;
    }

    if (_countTask != null) {
      return;
    }

    _countTask = countQuery!()
        .then((count) {
          totalResults = count;
          _didLoadTotalCount = true;
          _countTask = null;
          onCountUpdated?.call();
          return count;
        })
        .catchError((_) {
          _countTask = null;
          return 0;
        });
  }
}
