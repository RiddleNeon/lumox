import 'dart:ui';

class LayoutNode {
  final int id;
  final double width;
  final double height;

  double x;
  double y;

  int layer = 0;
  int order = 0;

  final List<LayoutNode> incoming = [];
  final List<LayoutNode> outgoing = [];

  LayoutNode({
    required this.id,
    required this.width,
    required this.height,
    this.x = 0,
    this.y = 0,
  });

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  Offset get center => Offset(x + width / 2, y + height / 2);
}