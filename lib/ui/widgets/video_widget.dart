import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumox/logic/feed_recommendation/video_recommender_base.dart';
import 'package:lumox/logic/video/video_provider.dart';
import 'package:lumox/ui/video/video_controller.dart';

import '../../base_logic.dart';
import '../../logic/local_storage/local_seen_service.dart';
import '../../logic/repositories/video_repository.dart';
import '../../logic/video/video.dart';
import 'overlays/video_info/overlays.dart';

class VideoItem extends StatefulWidget {
  final VideoController controller;
  final Video video;
  final String userId;
  final TickerProvider provider;
  final VideoProvider videoProvider;
  final int index;
  final void Function(bool)? onLikeChanged;

  const VideoItem({
    super.key,
    required this.controller,
    required this.video,
    required this.userId,
    required this.provider,
    required this.videoProvider,
    required this.index,
    this.onLikeChanged,
  });

  @override
  State<VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<VideoItem> {
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
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    if (widget.controller.isPlaying) {
      _wasPlaying = true;
      _startTracking();
    }
  }

  @override
  void didUpdateWidget(VideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _trackingTimer?.cancel();
    _saveInteraction();
    super.dispose();
  }

  void _onControllerUpdate(bool isPlaying) {
    if(!mounted) return;
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
        if (widget.controller.isPlaying && mounted) {
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
    final videoDuration = widget.controller.duration.inSeconds.toDouble();

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
    // Interaction will be saved when video stops playing
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
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: widget.controller.buildVideoWidget(context, thumbnailUrl: widget.video.thumbnailUrl),
          ),
          PageOverlay(
            provider: widget.provider,
            video: widget.video,
            onLikeChanged: onLikeChanged,
            onDislikeChanged: onDislikeChanged,
            onShareChanged: onShareChanged,
            onSaveChanged: onSaveChanged,
            onCommentChanged: onCommentChanged,
            initiallyLiked: localSeenService.isLiked(widget.video.id),
            initiallyDisliked: localSeenService.isDisliked(widget.video.id),
            isPaused: !widget.controller.isPlaying,
            onTogglePause: () {
              if (widget.controller.isPlaying) {
                widget.controller.pause();
              } else {
                widget.controller.play();
              }
            },
            index: widget.index,
          ),
        ],
      ),
    );
  }
}
