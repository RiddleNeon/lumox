import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';

class StreakCard extends StatefulWidget {
  final int completedDays;
  final int additionalShownDays;
  final int maxCompletedDaysShown;

  final int longestStreak;
  final int totalActiveDays;
  final DateTime? streakStartDate;
  final int? rankPercentile;
  final int? freezesLeft;

  final bool hasIncreasedStreakToday;

  const StreakCard({
    super.key,
    required this.completedDays,
    this.additionalShownDays = 8,
    this.maxCompletedDaysShown = 5,
    this.hasIncreasedStreakToday = false,

    this.longestStreak = 0,
    this.totalActiveDays = 0,
    this.streakStartDate,
    this.rankPercentile,
    this.freezesLeft,
  });

  @override
  State<StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<StreakCard> {
  late ScrollController _scrollController;
  final double _itemHeight = 100.0;

  bool expanded = false;

  bool _isDoneExpanding = false;

  final List<String> _messages = [
    "Keep going, you're doing great!",
    "Consistency beats motivation",
    "Small steps every day!",
    "Every day counts, keep it up!",
    "Your future self will thank you.",
    "Streaks are the new black!",
    "Don't break the chain!",
    "One day at a time.",
    "Your dedication is inspiring!",
    "Keep the momentum going!",
    "You're on fire, keep it up!",
    "Streaks: the secret to success!",
    "Your streak is your superpower!",
  ];

  late String _currentMessage;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _currentMessage = (_messages..shuffle()).first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _setInitialScroll());
  }

  @override
  void didUpdateWidget(covariant StreakCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.completedDays != widget.completedDays ||
        oldWidget.additionalShownDays != widget.additionalShownDays ||
        oldWidget.maxCompletedDaysShown != widget.maxCompletedDaysShown ||
        oldWidget.hasIncreasedStreakToday != widget.hasIncreasedStreakToday) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setInitialScroll());
    }
  }

  bool get _showUpcomingDay => !widget.hasIncreasedStreakToday;

  void _setInitialScroll() {
    final height = expanded ? 400.0 : 200.0;

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_computeOffset(height));
    }
  }

  int _computeFirstShownDay() {
    final int lastDay = widget.completedDays;
    final int completedWindowStart = (lastDay - widget.maxCompletedDaysShown).clamp(0, lastDay + 1);
    return completedWindowStart;
  }

  int _computeTotalItems(int firstShownDay) {
    final int completedShown = widget.completedDays - firstShownDay;
    return completedShown + widget.additionalShownDays;
  }

  double _computeOffset(double viewportHeight) {
    final firstShownDay = _computeFirstShownDay() + (widget.hasIncreasedStreakToday ? 1 : 0);
    final totalItems = _computeTotalItems(firstShownDay);

    final currentIndex = widget.completedDays - firstShownDay;

    final maxScrollExtent = math.max(0.0, (totalItems * _itemHeight) - viewportHeight);

    final targetOffset = (currentIndex * _itemHeight) - (viewportHeight / 2) + (_itemHeight / 2);

    return targetOffset.clamp(0.0, maxScrollExtent);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int firstShownDay = _computeFirstShownDay();
    final int totalItems = _computeTotalItems(firstShownDay);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isDoneExpanding = false;
            expanded = !expanded;
          });

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final height = expanded ? 400.0 : 200.0;

            await _scrollController.animateTo(_computeOffset(height), duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
            await Future.delayed(const Duration(milliseconds: 100));
            if (!mounted) return;
            setState(() {
              _isDoneExpanding = true;
            });
          });
        },
        child: AnimatedContainer(
          height: expanded ? 400 : 200.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    ScrollConfiguration(
                      behavior: const MaterialScrollBehavior()
                          .copyWith(scrollbars: _isDoneExpanding && expanded),
                      child: ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: EdgeInsets.only(
                          top: expanded ? 90 : 120,
                          bottom: 20,
                        ),
                        physics: expanded
                            ? const BouncingScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        itemCount: totalItems,
                        itemBuilder: (context, index) {
                          final day = firstShownDay + index + 1;
                          final isCompleted = day <= widget.completedDays;
                          final isCurrent =
                              _showUpcomingDay && day == widget.completedDays + 1;

                          final isPrevCompleted =
                              (day - 1) <= (widget.completedDays) &&
                                  (day - 1) > 0 &&
                                  !(widget.hasIncreasedStreakToday &&
                                      (day - 1) == widget.completedDays);

                          final drawPathToNext =
                              (day + 1) <= widget.completedDays ||
                                  !widget.hasIncreasedStreakToday &&
                                      (day + 1) == widget.completedDays + 1;

                          final hasNextItem = index < totalItems - 1;

                          return StreakItem(
                            index: index,
                            day: day,
                            isCompleted: isCompleted,
                            isCurrent: isCurrent,
                            isPrevCompleted: isPrevCompleted,
                            hasNextItem: hasNextItem,
                            itemHeight: _itemHeight,
                            drawPathToNext: drawPathToNext,
                          );
                        },
                      ),
                    ),

                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      top: expanded ? 16 : 18,
                      left: expanded ? -22 : 18,
                      child: AnimatedScale(
                        scale: expanded ? 0.8 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: _buildOverlay(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    final bool showDetails = expanded;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),

          FractionallySizedBox(
            widthFactor: 0.8,
            child: Text(_currentMessage, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.3)),
          ),

          if (showDetails) ...[const SizedBox(height: 16), _buildStatsGrid()],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const Row(
      children: [
        Text(
          "Your Streak",
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildMiniStat(CupertinoIcons.flame, "Current", "${widget.completedDays}d", 0),
        _buildMiniStat(Icons.emoji_events, "Best", "${widget.longestStreak}d", 1),

        if (widget.streakStartDate != null) _buildMiniStat(Icons.flag, "Since", DateFormat('dd MMM yyyy').format(widget.streakStartDate!), 2),

        if (widget.totalActiveDays > 0) _buildMiniStat(Icons.insights, "Total", "${widget.totalActiveDays}d", 3),

        if (widget.rankPercentile != null) _buildMiniStat(Icons.trending_up, "Rank", "Top ${100 - widget.rankPercentile!}%", 4),

        if (widget.freezesLeft != null) _buildMiniStat(Icons.ac_unit, "Freezes", "${widget.freezesLeft} left", 5),
      ],
    );
  }

  Widget _buildMiniStat(IconData icon, String label, String value, int index) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    const baseDuration = Duration(milliseconds: 260);
    final delay = Duration(milliseconds: 40 * index);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: expanded ? 1 : 0),
      duration: baseDuration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final slide = Offset(0, (1 - t) * 0.2);
        final scale = 0.98 + (t * 0.02);
        return AnimatedOpacity(
          duration: baseDuration,
          opacity: t,
          child: AnimatedSlide(
            duration: baseDuration,
            curve: Curves.easeOutCubic,
            offset: slide,
            child: AnimatedScale(duration: baseDuration, curve: Curves.easeOutCubic, scale: scale, child: child),
          ),
        );
      },
      onEnd: () {},
      child: AnimatedContainer(
        duration: baseDuration + delay,
        curve: Curves.easeOutCubic,
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: colors.onSurface),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: colors.onSurface.withValues(alpha: 0.55), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Offset _computeOverlayPosition({required double width}) {
    if (expanded) {
      return const Offset(-22, 16);
    }

    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

    final visibleIndex = ((scrollOffset + 40) / _itemHeight).floor();

    final laneX = math.sin(visibleIndex * 0.8) * 80.0;

    final bool itemsAreLeft = laneX < 0;

    const horizontalPadding = 18.0;
    const topPadding = 18.0;
    const overlayWidth = 220.0;

    if (itemsAreLeft) {
      return Offset(width - overlayWidth - horizontalPadding, topPadding);
    }

    return const Offset(horizontalPadding, topPadding);
  }
}

class StreakItem extends StatelessWidget {
  final int index;
  final int day;
  final bool isCompleted;
  final bool isCurrent;
  final bool isPrevCompleted;
  final bool drawPathToNext;
  final bool hasNextItem;
  final double itemHeight;

  const StreakItem({
    super.key,
    required this.index,
    required this.day,
    required this.isCompleted,
    required this.isCurrent,
    required this.isPrevCompleted,
    required this.hasNextItem,
    required this.itemHeight,
    required this.drawPathToNext,
  });

  double _getOffsetX(int idx) {
    return math.sin(idx * 0.8) * 80.0;
  }

  @override
  Widget build(BuildContext context) {
    final double currentX = _getOffsetX(index);
    final double prevX = index > 0 ? _getOffsetX(index - 1) : currentX;
    final double nextX = _getOffsetX(index + 1);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final Color cardColor = isCompleted ? colors.primaryContainer : (isCurrent ? colors.secondaryContainer : colors.surface);

    final Color textColor = colors.onInverseSurface;
    final Color textColorDark = colors.onSurface;

    return SizedBox(
      height: itemHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            height: itemHeight,
            child: CustomPaint(
              painter: PathPainter(
                currentX: currentX,
                prevX: prevX,
                nextX: nextX,
                isCompleted: isCompleted,
                drawPathToPrev: isPrevCompleted,
                hasNextItem: hasNextItem,
                isFirst: index == 0 && !isPrevCompleted,
                drawPathToNext: drawPathToNext,
              ),
            ),
          ),

          Transform.translate(
            offset: Offset(currentX, 0),
            child: Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX(0.5)
                ..rotateZ(-0.3),
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 60,
                height: 80,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(context.uiRadiusXl),
                  border: Border.all(color: Colors.black87, width: 2.5),
                  boxShadow: const [BoxShadow(color: Colors.black87, offset: Offset(-5, 7), blurRadius: 0)],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$day",
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColorDark),
                    ),
                    if (isCurrent && !isCompleted)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(color: textColorDark, borderRadius: BorderRadius.circular(40)),
                        child: Text(
                          "today",
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor),
                        ),
                      ),
                    if (isCompleted)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(Icons.check, color: Colors.black87, size: 20),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PathPainter extends CustomPainter {
  final double currentX;
  final double prevX;
  final double nextX;
  final bool isCompleted;
  final bool drawPathToPrev;
  final bool drawPathToNext;
  final bool hasNextItem;
  final bool isFirst;

  PathPainter({
    required this.currentX,
    required this.prevX,
    required this.nextX,
    required this.isCompleted,
    required this.drawPathToPrev,
    required this.drawPathToNext,
    required this.hasNextItem,
    required this.isFirst,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    final paint = Paint()
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter;

    if (!isFirst) {
      paint.color = drawPathToPrev ? const Color(0xFF4ADE80) : Colors.black26;
      final pathBottom = Path()
        ..moveTo(centerX + currentX, size.height / 2)
        ..lineTo(centerX + (currentX + prevX) / 2, size.height);
      canvas.drawPath(pathBottom, paint);
    }

    if (hasNextItem) {
      paint.color = drawPathToNext ? const Color(0xFF4ADE80) : Colors.black26;
      final pathTop = Path()
        ..moveTo(centerX + currentX, size.height / 2)
        ..lineTo(centerX + (currentX + nextX) / 2, 0);
      canvas.drawPath(pathTop, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PathPainter oldDelegate) {
    return currentX != oldDelegate.currentX ||
        prevX != oldDelegate.prevX ||
        nextX != oldDelegate.nextX ||
        isCompleted != oldDelegate.isCompleted ||
        drawPathToPrev != oldDelegate.drawPathToPrev ||
        hasNextItem != oldDelegate.hasNextItem ||
        isFirst != oldDelegate.isFirst;
  }
}
