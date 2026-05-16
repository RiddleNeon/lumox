
extension DurationToFuture on Duration {
  Future<void> get future => Future.delayed(this);
}