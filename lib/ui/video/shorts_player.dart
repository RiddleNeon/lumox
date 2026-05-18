import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:lumox/base_logic.dart';
import 'package:lumox/logic/feed_recommendation/video_recommender_base.dart';
import 'package:lumox/logic/local_storage/local_seen_service.dart';
import 'package:lumox/logic/repositories/video_repository.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/logic/video/video_provider.dart';
import 'package:lumox/ui/widgets/overlays/video_info/overlays.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../router/router.dart';

class YoutubeVideoContainer {
  final YoutubePlayerController controller;
  final Video video;

  YoutubeVideoContainer({required this.controller, required this.video});
}

class ShortsFeed extends StatefulWidget {
  const ShortsFeed({super.key, required this.videoProvider, this.initialPage = 0, this.itemCount = 5000});

  final VideoProvider videoProvider;
  final int initialPage;
  final int itemCount;

  @override
  State<ShortsFeed> createState() => _ShortsFeedState();
}

class _ShortsFeedState extends State<ShortsFeed> {
  late final PageController _pageController;

  final Map<int, YoutubeVideoContainer> _controllers = {};

  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareInitialPage());
    });
  }

  Future<void> _prepareInitialPage() async {
    final initial = await getControllerAt(_currentIndex);
    initial.playVideo();
    unawaited(_warmNextController());
  }

  Future<void> _warmNextController() async {
    try {
      await getControllerAt(_currentIndex + 1);
    } catch (_) {}
  }

  YoutubePlayerController _createController(String videoId) {
    return YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        loop: true,
        pointerEvents: .none,
        enableCaption: false,
        enableKeyboard: false,
        strictRelatedVideos: true,
        showVideoAnnotations: false,
      ),
    )..loadVideoById(videoId: videoId);
  }

  void _onPageChanged(int index) async {
    if (index == _currentIndex) return;

    _controllers[_currentIndex]?.controller.close();
    _controllers.remove(_currentIndex);

    await getControllerAt(index);
    _controllers[index]!.controller.playVideo();

    _currentIndex = index;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.controller.close();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      controller: _pageController,
      onPageChanged: _onPageChanged,
      itemCount: widget.itemCount,
      physics: const PageScrollPhysics(),
      itemBuilder: (context, index) {
        return FutureBuilder(
          future: getControllerAt(index),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.error != null && snapshot.error is VideoNotFoundException) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.video_library_outlined, size: 80, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                      const SizedBox(height: 20),
                      Text('No More Videos', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        'You have seen all available videos! check again tomorrow!',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton(onPressed: () => routerConfig.go('/search'), child: const Text('Explore videos')),
                    ],
                  ),
                ),
              );
            } else if (snapshot.error != null) {
              return Center(child: Text('Error loading video: ${snapshot.error}'));
            }
            return ShortVideoPage(controller: _controllers[index]!.controller, video: _controllers[index]!.video, index: index);
          },
        );
      },
    );
  }

  Future<YoutubePlayerController> getControllerAt(int index) async {
    if (_controllers.containsKey(index)) {
      return _controllers[index]!.controller;
    } else {
      final video = await widget.videoProvider.getVideoByIndex(index, useYoutubeVideos: true);

      if (video == null) {
        throw VideoNotFoundException(index);
      }

      final controller = _createController(YoutubePlayerController.convertUrlToId(video.videoUrl)!);
      _controllers[index] = YoutubeVideoContainer(controller: controller, video: video);
      return controller;
    }
  }
}

class ShortVideoPage extends StatefulWidget {
  final YoutubePlayerController controller;
  final String? thumbnailUrl;
  final Video video;
  final int index;
  final void Function(bool)? onLikeChanged;

  const ShortVideoPage({super.key, required this.controller, this.thumbnailUrl, required this.video, required this.index, this.onLikeChanged});

  @override
  State<ShortVideoPage> createState() => _ShortVideoPageState();
}

class _ShortVideoPageState extends State<ShortVideoPage> with SingleTickerProviderStateMixin {
  bool _startedPlaying = false;

  @override
  void initState() {
    super.initState();

    widget.controller.listen((event) {
      if (event.playerState == PlayerState.playing && !_startedPlaying && mounted) {
        setState(() {
          _startedPlaying = true;
          _wasPlaying = true;
          _startTracking();
        });
      }
    });

    Future.doWhile(() {
      return Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && widget.controller.value.playerState != PlayerState.playing) {
          widget.controller.playVideo();
          return true;
        }
        return !mounted;
      });
    });

    // Future.delayed(const Duration(milliseconds: 1500), () {
    //   if (mounted && widget.controller.value.playerState == PlayerState.buffering) {
    //     setState(() {
    //       widget.controller.playVideo();
    //       _startedPlaying = true;
    //       _wasPlaying = true;
    //       _startTracking();
    //     });
    //   }
    // });
  }

  DateTime? _startWatchTime;
  Timer? _trackingTimer;
  double _totalWatchTime = 0.0;
  bool _hasTrackedView = false;
  bool _isLiked = false;
  bool _isDisliked = false;
  bool _hasShared = false;
  bool _hasCommented = false;
  bool _hasSaved = false;
  bool _wasPlaying = false;

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _saveInteraction();
    super.dispose();
  }

  void _onControllerUpdate(bool isPlaying) {
    if (!mounted) return;
    if (isPlaying && !_wasPlaying) {
      _wasPlaying = true;
      _startTracking();
      setState(() {});
    } else if (!isPlaying && _wasPlaying) {
      _wasPlaying = false;
      _stopTracking();
      setState(() {});
    }
  }

  void _startTracking() {
    _startWatchTime = DateTime.now();

    // Track view after 3 seconds
    if (!_hasTrackedView) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (widget.controller.value.playerState == .playing && mounted) {
          _trackView();
          _hasTrackedView = true;
        }
      });
    }

    // Update watch time every second
    _trackingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateWatchTime();
      }
    });
  }

  void _stopTracking() {
    _trackingTimer?.cancel();
    _saveInteraction();
    _startWatchTime = null;
  }

  void _updateWatchTime() {
    if (_startWatchTime != null) {
      final elapsed = DateTime.now().difference(_startWatchTime!).inSeconds.toDouble();
      _totalWatchTime += elapsed;
      _startWatchTime = DateTime.now();
    }
  }

  /// Track view count on video document only (lightweight)
  void _trackView() {
    videoRepo.incrementViewCount(widget.video.id);
  }

  bool currentlySaving = false;

  /// Save complete interaction when user leaves video
  /// This creates ONE interaction document with all data
  void _saveInteraction() async {
    if (currentlySaving) return;
    if (_startWatchTime != null) {
      final elapsed = DateTime.now().difference(_startWatchTime!).inSeconds.toDouble();
      _totalWatchTime += elapsed;
    }
    currentlySaving = true;
    final videoDuration = widget.video.duration?.inSeconds.toDouble() ?? 0;

    try {
      // Use VideoRecommender to track interaction
      // This handles BOTH recent_interactions AND preference updates
      await trackInteraction(
        video: widget.video,
        watchTime: _totalWatchTime,
        videoDuration: videoDuration > 0 ? videoDuration : 1.0,
        liked: _isLiked,
        disliked: _isDisliked,
        shared: _hasShared,
        commented: _hasCommented,
        saved: _hasSaved,
        userId: currentAuthUserId(),
      );

      // Reset for next viewing session
      _totalWatchTime = 0.0;
    } catch (e) {
      print("Error saving interaction: $e");
    }
    currentlySaving = false;
  }

  /// Update interaction state when user likes/dislikes
  void onLikeChanged(bool isLiked) {
    setState(() {
      _isLiked = isLiked;
      if (isLiked) _isDisliked = false; // Can't like and dislike
    });
    if (isLiked) {
      localSeenService.saveLike(widget.video.id);
    } else {
      localSeenService.removeLike(widget.video.id);
    }
    // Interaction will be saved when video stops playing
    widget.onLikeChanged?.call(isLiked);
  }

  void onDislikeChanged(bool isDisliked) {
    setState(() {
      _isDisliked = isDisliked;
      if (isDisliked) _isLiked = false; // Can't like and dislike
    });
    if (isDisliked) {
      localSeenService.saveDislike(widget.video.id);
    } else {
      localSeenService.removeDislike(widget.video.id);
    }
  }

  void onShareChanged(bool hasShared) {
    setState(() {
      _hasShared = hasShared;
    });
  }

  void onSaveChanged(bool hasSaved) {
    setState(() {
      _hasSaved = hasSaved;
    });
  }

  void onCommentChanged(bool hasCommented) {
    setState(() {
      _hasCommented = hasCommented;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget out = Center(
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _startedPlaying ? 1.0 : 0.1,
                child: YoutubePlayer(controller: widget.controller, aspectRatio: 9 / 16),
              ),

              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _startedPlaying ? 0 : 0.95,
                child: CachedNetworkImage(
                  imageUrl:
                      widget.video.thumbnailUrl ?? 'https://img.youtube.com/vi/${YoutubePlayerController.convertUrlToId(widget.video.videoUrl)}/hqdefault.jpg',
                  fit: BoxFit.cover,
                ),
              ),

              PointerInterceptor(child: const AspectRatio(aspectRatio: 9 / 16)),
              PageOverlay(
                provider: this,
                video: widget.video,
                index: widget.index,
                initiallyLiked: localSeenService.isLiked(widget.video.id),
                initiallyDisliked: localSeenService.isLiked(widget.video.id),
                onLikeChanged: onLikeChanged,
                onDislikeChanged: onDislikeChanged,
                onShareChanged: onShareChanged,
                onSaveChanged: onSaveChanged,
                onCommentChanged: onCommentChanged,

                onTogglePause: () {
                  if (widget.controller.value.playerState == PlayerState.playing) {
                    widget.controller.pauseVideo();
                    _onControllerUpdate(false);
                  } else {
                    widget.controller.playVideo();
                    _onControllerUpdate(true);
                  }
                },
                isPaused: widget.controller.value.playerState != PlayerState.playing,
              ),
            ],
          ),
        ),
      ),
    );
    return out;
  }
}

class VideoNotFoundException implements Exception {
  final int index;

  VideoNotFoundException(this.index);

  @override
  String toString() => "Video at index $index not found";
}
