class QuestLayoutConfig {
  final double horizontalSpacing;
  final double verticalSpacing;
  final double layerSpacing;
  final double nodeRepulsion;
  final double edgeSpringStrength;
  final double crossingPenalty;
  final double idealEdgeLength;
  final int crossingMinimizationPasses;
  final int forceIterations;
  final int collisionIterations;
  final bool centerGraph;
  final bool allowCycles;

  final bool enableHubLayouts;
  final bool enableCircularClusters;
  final bool enableSymmetryForces;
  final bool enableOrganicShapes;

  final int hubMinConnections;

  final double hubOrbitSpacing;
  final double symmetryStrength;
  final double shapeStrength;

  const QuestLayoutConfig({
    this.horizontalSpacing = 120,
    this.verticalSpacing = 80,
    this.layerSpacing = 350,
    this.nodeRepulsion = 90000,
    this.edgeSpringStrength = 0.02,
    this.crossingPenalty = 1000,
    this.idealEdgeLength = 320,
    this.crossingMinimizationPasses = 12,
    this.forceIterations = 250,
    this.collisionIterations = 8,
    this.centerGraph = true,
    this.allowCycles = true,
    
    this.enableHubLayouts = true,
    this.enableCircularClusters = true,
    this.enableSymmetryForces = true,
    this.enableOrganicShapes = true,

    this.hubMinConnections = 5,

    this.hubOrbitSpacing = 240,
    this.symmetryStrength = 0.08,
    this.shapeStrength = 0.04,
  });
}