import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';

class CommentButton extends StatefulWidget {
  final void Function()? onComment;

  const CommentButton({super.key, this.onComment});

  @override
  State<CommentButton> createState() => _CommentButtonState();
}

class _CommentButtonState extends State<CommentButton> with SingleTickerProviderStateMixin {
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
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _ctrl.forward(from: 0.0);
    widget.onComment?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                child: Icon(CupertinoIcons.ellipses_bubble_fill, size: 28, color: cs.onSurface.withValues(alpha: 0.9)),
              ),
            );
          },
        ),
      ),
    );
  }
}
