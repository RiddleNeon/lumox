import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SlideMorphTransitions {
  static const Curve _curve = Curves.easeOutCubic;
  static const Curve _reverseCurve = Curves.easeInCubic;

  static Widget build(
    Animation<double> animation,
    Widget child, {
    Offset beginOffset = const Offset(0, 0.06),
    double beginScale = 0.985,
    bool fadeOnReverse = true,
    double reverseFadeEndOpacity = 0.0,
  }) {
    final curved = CurvedAnimation(parent: animation, curve: _curve, reverseCurve: _reverseCurve);
    final transitionedChild = SlideTransition(
      position: Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(curved),
      child: ScaleTransition(
        scale: Tween<double>(begin: beginScale, end: 1).animate(curved),
        child: child,
      ),
    );

    if (!fadeOnReverse) {
      return transitionedChild;
    }

    return FadeTransition(
      opacity: Tween<double>(begin: reverseFadeEndOpacity, end: 1.0).animate(curved),
      child: transitionedChild,
    );
  }

  static Widget switcher(
    Widget child,
    Animation<double> animation, {
    Offset beginOffset = const Offset(0, 0.12),
    double beginScale = 0.96,
    bool fadeOnReverse = true,
    double reverseFadeEndOpacity = 0.0,
  }) {
    return build(
      animation,
      child,
      beginOffset: beginOffset,
      beginScale: beginScale,
      fadeOnReverse: fadeOnReverse,
      reverseFadeEndOpacity: reverseFadeEndOpacity,
    );
  }

  static CustomTransitionPage<T> page<T>({
    required LocalKey key,
    required Widget child,
    Duration duration = const Duration(milliseconds: 280),
    Duration reverseDuration = const Duration(milliseconds: 220),
    Offset beginOffset = const Offset(0.04, 0.02),
    double beginScale = 0.985,
    bool fadeOnReverse = false,
    double reverseFadeEndOpacity = 0.0,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
        return build(
          animation,
          pageChild,
          beginOffset: beginOffset,
          beginScale: beginScale,
          fadeOnReverse: fadeOnReverse,
          reverseFadeEndOpacity: reverseFadeEndOpacity,
        );
      },
    );
  }
}

class SlideMorphPageTransitionsBuilder extends PageTransitionsBuilder {
  const SlideMorphPageTransitionsBuilder({this.beginOffset = const Offset(0.035, 0.015), this.beginScale = 0.99});

  final Offset beginOffset;
  final double beginScale;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return SlideMorphTransitions.build(animation, child, beginOffset: beginOffset, beginScale: beginScale);
  }
}
