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
  });
}