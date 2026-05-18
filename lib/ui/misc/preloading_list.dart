import 'package:flutter/material.dart';
import 'package:lumox/ui/search_screen/search_query.dart';
import 'package:lumox/ui/search_screen/widgets/empty_search_state.dart';
import 'package:lumox/ui/search_screen/widgets/scroll_area.dart';

class PreloadingList<T> extends StatefulWidget {
  final SearchQuery<T> query;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String? emptyStateLabel;

  const PreloadingList({super.key, required this.query, required this.itemBuilder, this.emptyStateLabel});

  @override
  State<PreloadingList<T>> createState() => _PreloadingListState<T>();
}

class PreloadingSliverList<T> extends PreloadingList<T> {
  const PreloadingSliverList({super.key, required super.query, required super.itemBuilder, super.emptyStateLabel});

  @override
  State<PreloadingList<T>> createState() => _SliverPreloadingListState<T>();
}

class _PreloadingListState<T> extends State<PreloadingList<T>> {
  late final ScrollController _scrollController;
  bool _didInit = false;

  bool _loading = false;
  bool _preloading = false;
  bool _preloadingGuard = false;
  int _currentLoadedCount = 0;
  
  final DateTime _queryInitTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    print("PreloadingList initialized with query: ${widget.query}");
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _init();
    }
  }

  Future<void> _init() async {
    if (widget.query.isCompleted) {
      print("Query already completed with results: ${widget.query.results.length}");
      print("Query init time: ${DateTime.now().difference(_queryInitTime)}");
      setState(() => _currentLoadedCount = widget.query.results.length);
      return;
    }

    setState(() => _loading = true);
    await widget.query.preloadMore();
    if (mounted) {
      setState(() {
        _currentLoadedCount = widget.query.results.length;
        _loading = false;
      });
    }
  }

  void _onScroll() {
    if (!mounted) return;
    final controller = _scrollController;
    if (!controller.hasClients) return;
    final currentPosition = controller.positions.last;
    if (!_loading && !_preloading) {
      if (currentPosition.extentAfter <= 300) {
        _preloadMore();
      }
    }
  }

  Future<void> _preloadMore() async {
    if (_preloadingGuard) return;
    _preloadingGuard = true;
    setState(() => _preloading = true);

    await widget.query.preloadMore();
    if (mounted) {
      setState(() {
        _preloading = false;
        _currentLoadedCount = widget.query.results.length;
      });
    }

    _preloadingGuard = false;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const SizedBox.shrink();
    }

    return ScrollConfiguration(
      behavior: SmoothScrollBehavior(),
      child: ScrollArea(
        scrollController: _scrollController,
        child: Scrollbar(
          controller: _scrollController,
          interactive: true,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            itemCount: widget.query.results.length,
            itemBuilder: (context, index) {
              if (widget.query.results.isEmpty) return EmptyState(label: widget.emptyStateLabel ?? 'Nothing found', cs: cs);
              if (index == _currentLoadedCount) {
                return const SizedBox.shrink();
              }
              if (index < widget.query.results.length) {
                return widget.itemBuilder(context, widget.query.results[index]);
              }
              return null;
            },
          ),
        ),
      ),
    );
  }
}

class _SliverPreloadingListState<T> extends _PreloadingListState<T> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const SizedBox.shrink();
    }

    return ScrollConfiguration(
      behavior: SmoothScrollBehavior(),
      child: ScrollArea(
        scrollController: _scrollController,
        child: Scrollbar(
          controller: _scrollController,
          interactive: true,
          thumbVisibility: true,
          child: CustomScrollView(controller: _scrollController, slivers: [_buildSliver(cs)]),
        ),
      ),
    );
  }

  Widget _buildSliver(ColorScheme cs) {
    final items = widget.query.results;
    final loadedCount = _currentLoadedCount.clamp(0, items.length);
    if (items.isEmpty) {
      return SliverFillRemaining(
        child: EmptyState(label: widget.emptyStateLabel ?? 'Nothing found', cs: cs),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index == loadedCount) {
            return const SizedBox.shrink();
          }
          if (index >= items.length) {
            return const SizedBox.shrink();
          }
          return widget.itemBuilder(context, items[index]);
        }, childCount: loadedCount + 1),
      ),
    );
  }
}

typedef AnimatedItemBuilder<T> = Widget Function(BuildContext context, T item, Animation<double> animation, int index);

class AnimatedPreloadingList<T> extends StatefulWidget {
  final SearchQuery<T> query;
  final Widget Function(BuildContext context, T item, Animation<double> animation, int index, List<T?> allKnownValues) itemBuilder;
  final String? emptyStateLabel;
  final Duration animationDuration;
  final Widget? notFoundWidget;

  const AnimatedPreloadingList({
    super.key,
    required this.query,
    required this.itemBuilder,
    this.emptyStateLabel,
    this.animationDuration = const Duration(milliseconds: 350),
    this.notFoundWidget,
  });

  @override
  AnimatedPreloadingListState<T> createState() => AnimatedPreloadingListState<T>();
}

class AnimatedPreloadingListState<T> extends State<AnimatedPreloadingList<T>> with AutomaticKeepAliveClientMixin {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late final ScrollController _scrollController;
  bool _didInit = false;

  final List<T> items = [];

  bool _loading = false;
  bool _preloading = false;
  bool _guard = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _init();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _loading = true);

    await widget.query.preloadMore();
    _syncItems(widget.query.results);

    setState(() => _loading = false);
  }

  void _syncItems(List<T> newItems) {
    final startIndex = items.length;

    for (int i = startIndex; i < newItems.length; i++) {
      items.add(newItems[i]);
      _listKey.currentState?.insertItem(i, duration: widget.animationDuration);
    }
  }

  Future<void> preloadMore({int limit = 20}) async {
    if (_guard) return;
    _guard = true;

    setState(() => _preloading = true);

    await widget.query.preloadMore(limit: limit);
    _syncItems(widget.query.results);

    setState(() => _preloading = false);
    _guard = false;
  }

  void _onScroll() {
    if (_loading || _preloading) return;
    final controller = _scrollController;
    if (!controller.hasClients) return;
    final currentPosition = controller.positions.last;

    if (currentPosition.extentAfter <= 300) {
      preloadMore();
    }
  }

  @override
  bool get wantKeepAlive => true;

  void removeItem(int index, Widget Function(BuildContext, Animation<double>) removedBuilder) {
    if (index < 0 || index >= items.length) return;

    items.removeAt(index);

    _listKey.currentState?.removeItem(index, (context, animation) => removedBuilder(context, animation), duration: widget.animationDuration);
  }

  void addItem(T item) {
    setState(() {
      items.add(item);
      final int insertIndex = items.indexOf(item);
      _listKey.currentState?.insertItem(insertIndex, duration: widget.animationDuration);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const SizedBox.shrink();
    }

    if (items.isEmpty) {
      return widget.notFoundWidget ?? Center(child: Text(widget.emptyStateLabel ?? 'Nothing found'));
    }

    return AnimatedList(
      key: _listKey,
      controller: _scrollController,
      initialItemCount: items.length,
      itemBuilder: (context, index, animation) {
        if (index == items.length) {
          return const SizedBox.shrink();
        }

        return widget.itemBuilder(context, items[index], animation, index, items);
      },
    );
  }
}
