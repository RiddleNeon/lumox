import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/logic/video/video_provider.dart';
import 'package:lumox/ui/router/router.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';
import 'package:lumox/ui/video/shorts_player.dart';
import 'package:lumox/ui/video/video_container.dart';
import 'package:lumox/ui/video/view_models/video_feed_view_model.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../../base_logic.dart';
import '../widgets/video_widget.dart';

bool _isYoutubeUrl(String url) => url.contains('youtube.com') || url.contains('youtu.be');

Future<VideoContainer?> _loadRegularContainer(int index, VideoProvider videoProvider, VideoFeedViewModel feedModel) async {
  final video = await videoProvider.getVideoByIndex(index, useYoutubeVideos: useYoutubeVideosOnlyNotifier.value);
  if (video == null) return null;
  return feedModel.getVideoContainerAt(index, video);
}

Future<void> _switchToRegularIndex(int index, VideoProvider videoProvider, VideoFeedViewModel feedModel) async {
  final currentVideo = await videoProvider.getVideoByIndex(index, useYoutubeVideos: useYoutubeVideosOnlyNotifier.value);
  if (currentVideo == null) return;
  final nextVideoFuture = videoProvider.getVideoByIndex(index + 1, useYoutubeVideos: useYoutubeVideosOnlyNotifier.value);
  final prevVideoFuture = index > 0
      ? videoProvider.getVideoByIndex(index - 1, useYoutubeVideos: useYoutubeVideosOnlyNotifier.value)
      : Future<Video?>.value(null);
  final nextVideo = await nextVideoFuture;
  final prevVideo = await prevVideoFuture;
  await feedModel.switchToVideoContainerAt(index, currentVideo, nextVideo: nextVideo, lastVideo: prevVideo);
}

Widget feedVideos(
  TickerProvider tickerProvider,
  BuildContext context, {
  required VideoProvider videoProvider,
  required VideoFeedViewModel feedModel,
  int itemCount = 5000,
  int initialPage = 0,
  void Function(bool)? onLikeChanged,
  PreloadPageController? pageController,
  void Function(int)? onPageChanged,
}) {
  return Stack(
    children: [
      ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, multitouchDragStrategy: .sumAllPointers),
        child: PreloadPageView.builder(
          controller: pageController ?? PreloadPageController(initialPage: initialPage),
          itemCount: itemCount,
          preloadPagesCount: 1,
          scrollDirection: Axis.vertical,
          itemBuilder: (context, index) {
            Widget? specialWidget = _checkForSpecialIndex(index, context);
            if (specialWidget != null) {
              return specialWidget;
            }

            return FutureBuilder(
              future: _loadRegularContainer(index, videoProvider, feedModel),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return FutureBuilder(
                    future: videoProvider.getVideoByIndex(index, useYoutubeVideos: useYoutubeVideosOnlyNotifier.value),
                    builder: (context, videoSnapshot) {
                      if (!videoSnapshot.hasData || videoSnapshot.data?.thumbnailUrl == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return FittedBox(
                        fit: BoxFit.fitHeight,
                        child: CachedNetworkImage(imageUrl: videoSnapshot.data!.thumbnailUrl!),
                      );
                    },
                  );
                }

                if (snapshot.hasError) {
                  print("Error loading video at index $index: ${snapshot.error}");
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 72, color: Theme.of(context).colorScheme.error),
                          const SizedBox(height: 16),
                          Text('Error loading Video', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                            'An error occurred when loading the videos. Please try again later!',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: () => routerConfig.go('/search'), child: const Text('Back')),
                        ],
                      ),
                    ),
                  );
                }

                final container = snapshot.data;
                if (container?.video == null || container?.controller == null) {
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
                }
                
                final videoData = container!.video!;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoItem(
                      controller: container.controller!,
                      video: videoData,
                      provider: tickerProvider,
                      videoProvider: videoProvider,
                      userId: currentAuthUserId(),
                      index: index,
                      onLikeChanged: onLikeChanged,
                    ),
                  ],
                );
              },
            );
          },
          onPageChanged: (value) {
            unawaited(_switchToRegularIndex(value, videoProvider, feedModel));
            onPageChanged?.call(value);
          },
        ),
      ),
    ],
  );
}

Widget _buildStopWidget(String label, IconData icon, BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.all(28.0),
    child: Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: cs.primary, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

Widget? _checkForSpecialIndex(int index, BuildContext context) {
  if (index == 50) {
    return _buildStopWidget('why are you still watching? Is it really THAT interesting???', CupertinoIcons.question_diamond_fill, context);
  }
  if (index == 100) return _buildStopWidget('come on man, are you still doing this?', CupertinoIcons.exclamationmark, context);
  if (index == 150) {
    return _buildStopWidget('dont you have better things to do???', CupertinoIcons.exclamationmark_circle_fill, context); //
  }
  if (index == 200) return _buildStopWidget('ok this is getting out of hand', Icons.warning_amber_outlined, context);
  if (index == 250) {
    return _buildStopWidget(
      'alright thats it, stop watching videos and go touch some grass or something',
      Icons.warning_amber_outlined,
      context,
    ); // also at this point you should probably seek help, maybe you have an addiction or something
  }
  if (index == 300) {
    return _buildStopWidget(
      'bro wtf',
      Icons.warning_amber_outlined,
      context,
    ); // 300 is the point of no return, if you watch 300 videos in a row you are officially a lost cause
  }
  if (index == 350) return _buildStopWidget('this is just sad now', Icons.warning, context);
  if (index == 400) return _buildStopWidget('ok you win, you can keep watching but I will pray for you', Icons.warning, context);
  if (index == 449) return _buildStopWidget('congrats you made it to the end of the feed, you can stop now', Icons.warning_sharp, context);
  if (index == 450) {
    Future.delayed(const Duration(seconds: 4), () {
      userRepository.selfBanUserSupabase();
      if (context.mounted) {
        routerConfig.go('/login-force');
      }
    });
    return _buildStopWidget(
      'well youre banned now. invest your time into something better, like therapy or sth. idk. \n Here is the number of the National Rehab Hotline of the Us: 866-210-1303. lol',
      Icons.celebration_outlined,
      context,
    );
  }
  if (index > 450) {
    return _buildStopWidget('Bye!', Icons.door_back_door_outlined, context);
  }

  return null; // no special widget for this index
}

class VideoFeed extends StatefulWidget {
  final int? initialPage;
  final int itemCount;
  final VideoProvider? customVideoProvider;
  final void Function(bool)? onLikeChanged;

  const VideoFeed({super.key, this.initialPage, this.itemCount = 5000, this.customVideoProvider, this.onLikeChanged});

  @override
  State<VideoFeed> createState() => _VideoFeedState();
}

class _VideoFeedState extends State<VideoFeed> with TickerProviderStateMixin {
  late final PreloadPageController _pageController;
  late final int _initialPage;
  late final VideoFeedViewModel _feedModel;
  late final VideoProvider _videoSource;
  late final Future<bool> _isYoutubeFeed;

  Future<bool> _detectYoutubeFeed() async {
    final firstVideo = await _videoSource.getVideoByIndex(_initialPage, useYoutubeVideos: useYoutubeVideosOnlyNotifier.value);
    if (firstVideo == null) return false;
    return _isYoutubeUrl(firstVideo.videoUrl);
  }

  @override
  void initState() {
    super.initState();
    _videoSource = widget.customVideoProvider ?? videoProvider;
    _feedModel = VideoFeedViewModel();
    _initialPage = widget.initialPage ?? 0;
    _pageController = PreloadPageController(initialPage: _initialPage, viewportFraction: 1);
    _isYoutubeFeed = _detectYoutubeFeed();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isYoutubeFeed = await _isYoutubeFeed;
      if (isYoutubeFeed) return;
      unawaited(_switchToRegularIndex(_initialPage, _videoSource, _feedModel));
    });
  }

  @override
  void dispose() {
    unawaited(_feedModel.pauseAll());
    unawaited(_feedModel.dispose());

    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isYoutubeFeed,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.data == true) {
          return Scaffold(
            body: ShortsFeed(videoProvider: _videoSource, initialPage: _initialPage, itemCount: widget.itemCount),
          );
        }

        return Scaffold(
          body: feedVideos(
            this,
            context,
            videoProvider: _videoSource,
            feedModel: _feedModel,
            itemCount: widget.itemCount,
            initialPage: _initialPage,
            onLikeChanged: widget.onLikeChanged,
            pageController: _pageController,
          ),
        );
      },
    );
  }
}

class SingleVideoProvider implements VideoProvider {
  SingleVideoProvider(this.video);

  final Video video;

  @override
  Future<Video?> getVideoByIndex(int index, {bool useYoutubeVideos = false}) async {
    if (index != 0) return null;
    return video;
  }

  @override
  Future<void> preloadVideos(int count, {bool useYoutubeVideos = false}) async {}
}
