import 'package:lumox/logic/quests/quest.dart';
import 'package:lumox/logic/quests/quest_connection.dart';
import 'package:lumox/logic/quests/quest_layout/custom/custom_layout_config.dart';
import 'package:lumox/logic/quests/quest_system.dart';

class CustomLayoutSystem {
  QuestSystem questSystem;

  CustomLayoutConfig config;

  CustomLayoutSystem(this.questSystem, this.config);

  void layout() {
    
    final nodes = _getNodes();
    final rootNodes = _getRootNodes(nodes);
    
    print("tree: ");
    for (var node in rootNodes) {
      _printNodeTree(node);
    }
    
    print("Root nodes: ${rootNodes.map((e) => e.id).toList()}");
    
    final crossConnections = <QuestConnection>{};
    for (var rootNode in rootNodes) {
      crossConnections.addAll(_detectCrossConnections(rootNode));
    }
    print("Cross connections: ${crossConnections.map((e) => '(${e.fromQuestId} -> ${e.toQuestId})').toList()}");
  }

  Set<_CustomLayoutNode> _getNodes() {
    Set<_CustomLayoutNode> nodes = questSystem.quests.map((quest) => _CustomLayoutNode.fromQuest(quest, questSystem)).toSet();
    List<QuestConnection> connections = questSystem.getConnections();

    for (var value in nodes) {
      final questPrerequisites = connections
          .where((conn) => conn.toQuestId == value.id)
          .map((e) => nodes.where((element) => element.id == e.fromQuestId).firstOrNull)
          .whereType<_CustomLayoutNode>();
      
      value.prerequisites.addAll(questPrerequisites);
      
      for(var prerequisite in questPrerequisites) {
        prerequisite.children.add(value);
      }
    }
    
    return nodes;
  }

  Set<_CustomLayoutNode> _getRootNodes(Set<_CustomLayoutNode> nodes) {
    
    final Set<_CustomLayoutNode> out = {};
    
    for (var value in nodes) {
      
      if(value.prerequisites.isEmpty) {
        out.add(value);
      } else {
        out.addAll(_getRootNodes(value.prerequisites));        
      }
      
    }
    
    return out;
  }
  
  
  Set<QuestConnection> _detectCrossConnections(_CustomLayoutNode rootNode, [List<_CustomLayoutNode>? visited]) {
    visited ??= [];
    Set<QuestConnection> crossConnections = {};
    visited = [...visited, rootNode];
    
    if(rootNode.prerequisites.length > 1) {
      for (var prerequisite in rootNode.prerequisites) {
        if(!visited.contains(prerequisite)) {
          crossConnections.add(QuestConnection(fromQuestId: prerequisite.id, toQuestId: rootNode.id));
        }
      }
    }
    
    for (var child in rootNode.children) {
      crossConnections.addAll(_detectCrossConnections(child, visited));      
    }
    
    return crossConnections;
  }
  

  void _printNodeTree(_CustomLayoutNode node, [String indent = '']) {
    print('$indent- Node ${node.id} (x: ${node.x}, y: ${node.y}, d: ${node.depth})');
    for (var child in node.children) {
      _printNodeTree(child, '$indent  ');
    }
  }


}

class _CustomLayoutNode {
  double x;
  double y;

  double width;
  double height;

  Set<_CustomLayoutNode> prerequisites = {};
  Set<_CustomLayoutNode> children = {};
  int depth = 0x8000000000000000;

  int id;

  _CustomLayoutNode({required this.x, required this.y, required this.width, required this.height, this.id = 0});

  factory _CustomLayoutNode.fromQuest(Quest quest, QuestSystem questSystem) {
    return _CustomLayoutNode(x: quest.posX, y: quest.posY, width: quest.sizeX, height: quest.sizeY, id: quest.id);
  }
  
  @override
  String toString() => 'Node(id: $id, x: $x, y: $y, width: $width, height: $height, prerequisites: ${prerequisites.map((e) => e.id).toList()}, children: ${children.map((e) => e.id).toList()})';
}
