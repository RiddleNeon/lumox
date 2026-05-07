
import 'package:flutter/material.dart';
import 'package:lumox/ui/misc/avatar.dart';

class MessageAvatarWidget extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool isOnline;
  final double radius;
  final ColorScheme colorScheme;

  const MessageAvatarWidget({super.key, required this.name, required this.isOnline, required this.radius, required this.colorScheme, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Stack(
      children: [
        SizedBox(
            width: radius * 2,
            height: radius * 2,
            child: Avatar(imageUrl: imageUrl, name: name, colorScheme: colorScheme)),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
              decoration: BoxDecoration(
                color: cs.tertiary,
                shape: BoxShape.circle,
                border: Border.all(color: cs.surface, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}