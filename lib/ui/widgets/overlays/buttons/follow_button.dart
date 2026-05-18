import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumox/logic/local_storage/local_seen_service.dart';
import 'package:lumox/logic/users/user_model.dart';

import '../../../../base_logic.dart';
import '../../../theme/theme_ui_values.dart';

enum FollowButtonDesign { floating, docked, compact }

class FollowButton extends StatefulWidget {
  final bool initialSubscribed;
  final UserProfile user;
  final Future<void> Function(bool)? onChanged;
  final FollowButtonDesign design;

  const FollowButton({super.key, this.initialSubscribed = false, this.onChanged, this.design = .floating, required this.user});

  @override
  State<FollowButton> createState() => FollowButtonState();
}

class FollowButtonState extends State<FollowButton> with SingleTickerProviderStateMixin {
  late bool _subscribed = widget.initialSubscribed;
  bool _isLoading = false;
  bool _showLoadingIndicator = false;
  Timer? _loadingIndicatorDelayTimer;
  late AnimationController _controller;
  late Animation<double> _pressScaleAnimation;
  late Animation<double> _iconPopAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

    _pressScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.94).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.94, end: 1.03).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.03, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35,
      ),
    ]).animate(_controller);

    _iconPopAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.12, 0.78, curve: Curves.easeOutBack),
    );
  }

  @override
  void didUpdateWidget(covariant FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSubscribed != widget.initialSubscribed) {
      _subscribed = widget.initialSubscribed;
    }
  }

  void _toggle() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _showLoadingIndicator = false;
    });

    _loadingIndicatorDelayTimer?.cancel();
    _loadingIndicatorDelayTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || !_isLoading) return;
      setState(() {
        _showLoadingIndicator = true;
      });
    });

    await _controller.forward(from: 0);

    try {
      final subscribed = await userRepository.toggleFollowUser(widget.user.id);
      if (!mounted) return;

      setState(() {
        _subscribed = subscribed;
      });

      if (subscribed) {
        localSeenService.followUser(widget.user.id);
      } else {
        localSeenService.unfollowUser(widget.user.id);
      }

      await widget.onChanged?.call(subscribed);
    } finally {
      _loadingIndicatorDelayTimer?.cancel();
      setState(() {
        _isLoading = false;
        _showLoadingIndicator = false;
      });
    }
  }

  void setFollowed(bool followed) {
    setState(() {
      _subscribed = followed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = widget.design == FollowButtonDesign.compact;

    final backgroundColor = _subscribed ? theme.colorScheme.tertiaryContainer : theme.colorScheme.primaryContainer;

    final foregroundColor = _subscribed ? theme.colorScheme.onTertiaryContainer : theme.colorScheme.onPrimaryContainer;

    final borderRadius = widget.design == FollowButtonDesign.docked
        ? BorderRadius.only(topLeft: Radius.circular(context.uiRadiusMd), topRight: Radius.circular(context.uiRadiusMd))
        : BorderRadius.circular(isCompact ? context.uiRadiusXl : context.uiRadiusMd);

    final containerPadding = isCompact ? const EdgeInsets.symmetric(horizontal: 11, vertical: 8) : const EdgeInsets.symmetric(horizontal: 24, vertical: 14);

    final iconSize = isCompact ? 14.0 : null;
    final labelStyle = (isCompact ? theme.textTheme.labelMedium : theme.textTheme.labelLarge)?.copyWith(color: foregroundColor, fontWeight: FontWeight.bold);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _pressScaleAnimation.value,
          child: child,
        );
      },
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _isLoading ? null : _toggle,
          borderRadius: borderRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeInOutCubic,
            padding: containerPadding,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: borderRadius,
              border: isCompact ? Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.32)) : null,
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      ...previousChildren,
                      ?currentChild,
                    ],
                  );
                },
                child: _showLoadingIndicator
                    ? SizedBox(
                        key: const ValueKey('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                        ),
                      )
                    : Row(
                        key: const ValueKey('label'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.scale(
                            scale: 0.92 + (_iconPopAnimation.value * 0.14),
                            child: Icon(
                              _subscribed ? (isCompact ? Icons.check : Icons.check_circle) : Icons.notifications,
                              color: foregroundColor,
                              size: iconSize,
                            ),
                          ),
                          SizedBox(width: isCompact ? 4 : 10),
                          Text(
                            _subscribed ? (isCompact ? "Following" : "Followed") : "Follow",
                            style: labelStyle,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _loadingIndicatorDelayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }
}
