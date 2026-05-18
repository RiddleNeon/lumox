import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';

class VideoCard extends StatefulWidget {
  const VideoCard({super.key, this.thumbnail, required this.video, required this.onTap, required this.cs});

  final Video video;
  final Future<Uint8List?>? thumbnail;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hovered = false;
  late Future<Uint8List?>? thumbnail = widget.thumbnail;

  String _formatCount(int? count) {
    if (count == null) return '—';
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '';
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = duration.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final video = widget.video;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: _hovered ? cs.surfaceContainerHigh : cs.surfaceContainer,
            borderRadius: BorderRadius.circular(context.uiRadiusMd),
            border: Border.all(color: _hovered ? cs.primary.withValues(alpha: 0.35) : cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(context.uiRadiusMd), bottomLeft: Radius.circular(context.uiRadiusMd)),
                    child: SizedBox(
                      width: 140,
                      height: 110,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildThumbnail(cs),
                          if (video.duration != null)
                            Positioned(
                              bottom: 5,
                              right: 5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(color: cs.scrim.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(context.uiRadiusSm)),
                                child: Text(
                                  _formatDuration(video.duration),
                                  style: TextStyle(color: cs.onSurface, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
                          ),
                          const SizedBox(height: 5),

                          Row(
                            children: [
                              Icon(Icons.person_outline_rounded, size: 13, color: cs.onSurfaceVariant),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  video.authorName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              StatChip(icon: Icons.visibility_outlined, label: _formatCount(video.viewsCount), cs: cs),
                              StatChip(icon: Icons.favorite_border_rounded, label: _formatCount(video.likesCount), cs: cs),
                              StatChip(icon: Icons.chat_bubble_outline_rounded, label: _formatCount(video.commentsCount), cs: cs),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.only(right: 10, top: 10),
                    child: Icon(Icons.chevron_right_rounded, color: _hovered ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.4), size: 20),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              if (video.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: video.tags
                          .take(5)
                          .map(
                            (tag) => Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(context.uiRadiusLg),
                              ),
                              child: Text(
                                '#$tag',
                                style: TextStyle(color: cs.onSecondaryContainer, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(ColorScheme cs) {
    thumbnail ??= thumbnailFor(widget.video);
    return FutureBuilder<Uint8List?>(
      future: thumbnail,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(snapshot.data!, fit: BoxFit.cover),
              if (_hovered)
                Container(
                  color: cs.scrim.withValues(alpha: 0.2),
                  child: Center(child: Icon(Icons.play_circle_fill_rounded, color: cs.onSurface, size: 36)),
                ),
            ],
          );
        }
        return _shimmer(cs);
      },
    );
  }

  Widget _shimmer(ColorScheme cs) => Shimmer(child: Container(color: cs.surfaceContainerHighest));
}

class StatChip extends StatelessWidget {
  const StatChip({super.key, required this.icon, required this.label, required this.cs});

  final IconData icon;
  final String label;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: cs.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

final Map<String, FutureOr<Uint8List?>> _cachedThumbnails = {};

Future<Uint8List?> thumbnailFor(Video video) async {
  return _cachedThumbnails[video.videoUrl] ??= loadThumbnailFor(video);
}

Future<Uint8List?> loadThumbnailFor(Video video) async {
  if (video.thumbnailUrl == null) return Future.value(null);

  var thumbnailUrl = video.thumbnailUrl!;
  if (!thumbnailUrl.startsWith('http')) {
    thumbnailUrl = 'https://$thumbnailUrl';
  }
  http.Response response = await http.get(Uri.parse(video.thumbnailUrl!));
  final data = response.bodyBytes;
  _cachedThumbnails[video.videoUrl] = data;
  return data;
}

void disposeThumbnailCache() {
  _cachedThumbnails.clear();
}
