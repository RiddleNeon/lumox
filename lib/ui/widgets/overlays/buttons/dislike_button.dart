import 'package:flutter/material.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';

class DislikeButton extends StatefulWidget {
  final bool initiallyDisliked;
  final void Function(bool)? onDislikeChanged;
  final bool initiallyPlayingAnimation;

  const DislikeButton({super.key, this.initiallyDisliked = false, this.onDislikeChanged, this.initiallyPlayingAnimation = false});

  @override
  State<DislikeButton> createState() => _DislikeButtonState();
}

class _DislikeButtonState extends State<DislikeButton> with SingleTickerProviderStateMixin {
  late bool disliked = widget.initiallyDisliked;
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0).chain(CurveTween(curve: Curves.easeInBack)), weight: 60),
    ]).animate(_ctrl);

    _rotate = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.15).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -0.15, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 60),
    ]).animate(_ctrl);

    if (widget.initiallyPlayingAnimation) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    setState(() {
      disliked = !disliked;
    });

    _ctrl.forward(from: 0.0).then((value) => widget.onDislikeChanged?.call(disliked));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color iconColor = disliked ? cs.error : cs.onSurfaceVariant;
    final IconData iconData = disliked ? Icons.thumb_down : Icons.thumb_down;

    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        onTap: _onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            return Transform.rotate(
              angle: _rotate.value,
              child: Transform.scale(
                scale: _scale.value,
                child: Icon(iconData, size: 28, color: iconColor),
              ),
            );
          },
        ),
      ),
    );
  }
}
