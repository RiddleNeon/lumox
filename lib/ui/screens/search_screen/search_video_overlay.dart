import 'package:flutter/material.dart';
import 'package:lumox/logic/feed_recommendation/search_video_result_recommender.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/ui/animations/slide_morph_transitions.dart';
import 'package:lumox/ui/video/short_video_player.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';

/// Returns the number of likes added (can be negative if user unliked videos)
Future<int> openVideoPlayer({required BuildContext context, required List<Video> listedVideos, required int videoIndex}) async {
  int likes = 0;
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'VideoOverlay',
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, _) => SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(context.uiRadiusLg),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                VideoFeed(
                  customVideoProvider: SearchVideoResultRecommender(listedVideos: listedVideos),
                  itemCount: listedVideos.length,
                  initialPage: videoIndex,
                  onLikeChanged: (liked) => likes += liked ? 1 : -1,
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.inverseSurface.withValues(alpha: 0.85), shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onInverseSurface, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      return SlideMorphTransitions.build(animation, child, beginOffset: const Offset(0, 0.08), beginScale: 0.88);
    },
  );
  return likes;
}

