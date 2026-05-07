import 'package:lumox/logic/quests/quest_layout/quest_layout_node.dart';

class LayoutEdge {
  final LayoutNode from;
  final LayoutNode to;

  bool reversed = false;

  LayoutEdge({
    required this.from,
    required this.to,
  });
}