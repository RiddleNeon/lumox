import 'package:flutter/material.dart';

class VideoDescription extends StatelessWidget {
  final String username;
  final String videoTitle;
  final String songInfo;

  const VideoDescription(this.username, this.videoTitle, this.songInfo, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        height: 120.0,
        padding: const EdgeInsets.only(left: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '@$username',
              style: TextStyle(fontSize: 16, color: cs.onInverseSurface, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 7),
            Text(videoTitle, style: TextStyle(fontSize: 16, color: cs.onInverseSurface)),
            const SizedBox(height: 7),
            Row(
              children: [
                Icon(Icons.music_note, size: 15.0, color: cs.secondaryContainer),
                Text(songInfo, style: TextStyle(color: cs.onInverseSurface.withValues(alpha: 0.92), fontSize: 14.0)),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
