import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:lumox/base_logic.dart';
import 'package:lumox/logic/feed_recommendation/video_recommender.dart';
import 'package:lumox/ui/router/deep_link_builder.dart';
import 'package:lumox/logic/repositories/video_repository.dart';
import 'package:lumox/logic/users/user_model.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/ui/misc/avatar.dart';
import 'package:lumox/ui/screens/home/streak_card.dart';

import '../../theme/theme_ui_values.dart';
import '../search_screen/search_screen.dart';
import '../search_screen/widgets/search_video_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Video>? _discoverVideos;

  List<UserProfile> _followedCreators = [];
  final Map<String, List<Video>> _creatorVideos = {};

  late PageController _followingPageController;
  int _currentCreatorIndex = 0;

  bool _loading = true;
  late String _welcomeMessage;
  final TextEditingController _searchController = TextEditingController();
  static const int _dailyGoalTarget = 60;
  int _dailyVideosStarted = 0;
  DateTime _dailyGoalDate = DateTime.now();
  Video? _continueLearningVideo;
  
  late VideoRecommender _videoRecommender;

  final List<String> _rawWelcomeMessages = [
    "Ready to dive into something new today?",
    "Your next favorite video is waiting.",
    "Let's learn something awesome, {username}.",
    "Welcome back! Pick up right where you left off.",
    "Hey {username}, great to see you again.",
    "Time to discover some fresh content.",
    "What are we learning today, {username}?",
    "Keep that learning momentum going!",
    "Welcome back, {username}!",
    "Ready to learn something new today?",
    "Let's make today productive, {username}!",
    "Your next breakthrough starts now!",
    "Great to see you again, {username}!",
    "Time to keep the momentum going!",
    "What are we discovering today?",
    "Another day, another step forward!",
    "Your learning journey continues!",
    "Let's build something awesome today!",
    "Keep growing, {username}!",
    "Today's a great day to learn something new!",
    "You're making real progress!",
    "Let's keep the streak alive!",
    "One more session closer to your goals!",
    "Learning never looked this good!",
    "Back again? Love the consistency!",
    "Let's turn curiosity into progress!",
    "Ready for your next challenge?",
    "Keep showing up, it matters!",
    "New day, new knowledge!",
    "Your future self is cheering for you!",
    "Let's continue where you left off!",
    "Progress starts with showing up!",
    "Something interesting is waiting for you!",
    "Stay curious, {username}!",
    "Another opportunity to improve!",
    "You're doing amazing, keep going!",
    "Let's make today count!",
    "Your journey keeps getting better!",
  ];

  @override
  void initState() {
    super.initState();
    _followingPageController = PageController(viewportFraction: 0.92);
    _setupWelcomeMessage();
    _videoRecommender = VideoRecommender();
    _loadContent();
  }

  @override
  void dispose() {
    _followingPageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _setupWelcomeMessage() {
    final msg = _rawWelcomeMessages[Random().nextInt(_rawWelcomeMessages.length)];
    _welcomeMessage = msg.replaceAll('{username}', currentUser.displayName);
  }

  Future<void> _loadContent() async {
    setState(() => _loading = true);
    try {
      final discover = await _videoRecommender.fetchTrendingVideos(limit: 28, useYoutubeVids: useYoutubeVideosOnlyNotifier.value);
      
      if(discover.isEmpty) {
        throw Exception("No videos found");
      }

      _followedCreators = await userRepository.getFollowing(currentUser.id, limit: 5);

      final learningSnapshot = await videoRepo.getHomeLearningSnapshot(userId: currentUser.id);

      if (mounted) {
        setState(() {
          _discoverVideos = discover.toList();
          _continueLearningVideo = learningSnapshot.continueVideo;
          _dailyGoalDate = DateTime.now();
          _dailyVideosStarted = learningSnapshot.dailyStartedCount;
          _loading = false;
        });

        if (_followedCreators.isNotEmpty) {
          _loadVideosForCreator(_followedCreators.first.id);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _discoverVideos = [];
          _continueLearningVideo = null;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadVideosForCreator(String creatorId) async {
    if (_creatorVideos.containsKey(creatorId)) return;

    try {
      final videos = await userRepository.getPublishedVideos(creatorId, limit: 3);

      if (mounted) {
        setState(() {
          _creatorVideos[creatorId] = videos;
        });
      }
    } catch (e) {
      print("Error loading videos for $creatorId: $e");
      if (mounted) {
        setState(() {
          _creatorVideos[creatorId] = [];
        });
      }
    }
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) return;
    final uri = Uri(path: '/search', queryParameters: {'q': query.trim()});
    GoRouter.of(context).push(uri.toString());
  }

  DateTime _todayOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  void _resetDailyGoalIfNeeded() {
    final today = _todayOnly(DateTime.now());
    if (_todayOnly(_dailyGoalDate) != today) {
      _dailyGoalDate = today;
      _dailyVideosStarted = 0;
    }
  }

  Future<void> _openVideoList(List<Video> videos, {int videoIndex = 0}) async {
    if (videos.isEmpty) {
      GoRouter.of(context).go('/feed');
      return;
    }

    final safeIndex = videoIndex.clamp(0, videos.length - 1);
    final selectedVideo = videos[safeIndex];

    _resetDailyGoalIfNeeded();
    setState(() {
      _dailyVideosStarted += 1;
      _continueLearningVideo = selectedVideo;
    });

    try {
      await videoRepo.recordLearningStart(selectedVideo.id, userId: currentUser.id);
    } catch (_) {
      // Keep UI responsive even if analytics persistence fails.
    }

    if(!mounted) return;
    
    await openVideoPlayer(
      context: context,
      listedVideos: videos,
      videoIndex: safeIndex,
    );
  }

  Future<void> _openContinueLearning() async {
    if (_continueLearningVideo != null) {
      final continueVideo = _continueLearningVideo!;
      final discover = _discoverVideos ?? const <Video>[];
      final idxInDiscover = discover.indexWhere((v) => v.id == continueVideo.id);
      if (idxInDiscover != -1) {
        await _openVideoList(discover, videoIndex: idxInDiscover);
        return;
      }

      await _openVideoList([continueVideo], videoIndex: 0);
      return;
    }

    if (_followedCreators.isNotEmpty) {
      final creatorId = _followedCreators[_currentCreatorIndex].id;
      await _loadVideosForCreator(creatorId);
      final creatorVideos = _creatorVideos[creatorId] ?? const <Video>[];
      if (creatorVideos.isNotEmpty) {
        await _openVideoList(creatorVideos, videoIndex: 0);
        return;
      }
    }

    final discover = _discoverVideos ?? const <Video>[];
    if (discover.isNotEmpty) {
      await _openVideoList(discover, videoIndex: 0);
      return;
    }

    if (mounted) {
      GoRouter.of(context).go('/feed');
    }
  }

  String _continueLearningSubtitle() {
    if (_continueLearningVideo != null) {
      return 'Pick up with "${_continueLearningVideo!.title}"';
    }
    print("_followedCreators: ${_followedCreators.length}, _currentCreatorIndex: $_currentCreatorIndex");

    if (_followedCreators.isNotEmpty) {
      final creator = _followedCreators[_currentCreatorIndex];
      return 'Latest from ${creator.displayName}';
    }
    final discover = _discoverVideos;
    if (discover != null && discover.isNotEmpty) {
      return 'Pick up with "${discover.first.title}"';
    }
    return 'Find your next lesson';
  }

  double _continueLearningProgress() {
    if (_continueLearningVideo != null) {
      return -1.0;
    }

    if (_followedCreators.isNotEmpty) {
      return (_currentCreatorIndex + 1) / _followedCreators.length;
    }
    final discoverCount = _discoverVideos?.length ?? 0;
    return discoverCount == 0 ? 0.0 : 0.35;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadContent,
          color: cs.primary,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              _buildSliverAppBar(cs),

              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.uiSpace(16), vertical: context.uiSpace(8)),
                  child: _buildSearchBar(cs),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: context.uiSpace(24), bottom: context.uiSpace(8), left: 14),
                  child: _buildSectionTitle(cs, 'Your Path', ' Keep progressing'),
                ),
              ),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildStreakCard(cs),
              )),
              SliverToBoxAdapter(child: _buildHorizontalQuestsList(cs)),

              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: context.uiSpace(32), bottom: context.uiSpace(16), left: 14),
                  child: _buildSectionTitle(cs, 'Following', ' Latest from your creators'),
                ),
              ),
              SliverToBoxAdapter(child: _buildFollowingCarousel(cs)),

              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: context.uiSpace(32), bottom: context.uiSpace(16), left: 14),
                  child: _buildSectionTitle(cs, 'Discover', ' Trending right now', onSeeAll: () => GoRouter.of(context).push('/feed')),
                ),
              ),
              SliverToBoxAdapter(child: _buildDiscoverCarouselGrid(cs)),

              SliverToBoxAdapter(child: SizedBox(height: context.uiSpace(60))),
            ],
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar(ColorScheme cs) {
    return SliverAppBar(
      floating: true,
      backgroundColor: cs.surface,
      elevation: 0,
      expandedHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.uiSpace(16)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Avatar(imageUrl: currentUser.profileImageUrl, name: currentUser.username, colorScheme: cs),
              SizedBox(width: context.uiSpace(12)),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _welcomeMessage,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      currentUser.username,
                      style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: _onSearchSubmitted,
      decoration: InputDecoration(
        hintText: 'Search videos, creators or tags...',
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
        prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: EdgeInsets.symmetric(horizontal: context.uiSpace(16), vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.uiRadiusLg), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildFollowingCarousel(ColorScheme cs) {
    if (_loading && _followedCreators.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    }

    if (_followedCreators.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(context.uiSpace(32)),
          child: Text('Follow more creators to see their content here.', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: context.uiSpace(16)),
            itemCount: _followedCreators.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final creator = _followedCreators[index];
              final isSelected = _currentCreatorIndex == index;

              return GestureDetector(
                onTap: () {
                  _followingPageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.all(isSelected ? 3 : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? cs.primary : Colors.transparent, width: 2),
                  ),
                  child: Avatar(imageUrl: creator.profileImageUrl, name: creator.displayName, colorScheme: cs),
                ),
              );
            },
          ),
        ),

        SizedBox(height: context.uiSpace(16)),

        SizedBox(
          height: 340,
          child: PageView.builder(
            controller: _followingPageController,
            onPageChanged: (index) {
              setState(() => _currentCreatorIndex = index);
              _loadVideosForCreator(_followedCreators[index].id);
            },
            itemCount: _followedCreators.length,
            itemBuilder: (context, index) {
              final creator = _followedCreators[index];
              final videos = _creatorVideos[creator.id];

              return Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: _buildCreatorColumn(cs, creator, videos));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProfileButton(ColorScheme cs, dynamic creator, {required bool hasVideos}) {
    return Padding(
      padding: EdgeInsets.only(top: context.uiSpace(8)),
      child: Material(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          onTap: () => GoRouter.of(context).push(DeepLinkBuilder.profile(creator.id)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.uiSpace(14),
              vertical: context.uiSpace(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_rounded,
                  color: cs.onPrimaryContainer,
                  size: 18,
                ),
                SizedBox(width: context.uiSpace(8)),

                Flexible(
                  child: Text(
                    hasVideos
                        ? 'View profile'
                        : 'Check out ${creator.displayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),

                SizedBox(width: context.uiSpace(6)),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreatorColumn(ColorScheme cs, dynamic creator, List<Video>? videos) {
    if (videos == null) {
      return Container(
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(context.uiRadiusLg)),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final profileButton = _buildProfileButton(cs, creator, hasVideos: videos.isNotEmpty);

    if (videos.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(context.uiRadiusLg),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: context.uiSpace(16),
              vertical: context.uiSpace(18),
            ),
            child: Column(
              children: [
                Icon(Icons.video_library_outlined, color: cs.onSurfaceVariant),
                SizedBox(height: context.uiSpace(8)),
                Text(
                  '${creator.displayName} hasn’t posted yet',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: context.uiSpace(4)),
                Text(
                  'Check their profile for updates',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
          profileButton,
        ],
      );
    }

    final previewVideos = videos.take(2).toList();

    return Column(
      children: [
        ...previewVideos
            .map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: _FeedListVideoCard(video: v, videos: videos, onPlayVideo: _openVideoList),
              ),
            ),
        profileButton,
      ],
    );
  }

  Widget _buildSectionTitle(ColorScheme cs, String title, String subtitle, {VoidCallback? onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
          ],
        ),
        if (onSeeAll != null)
          InkWell(
            onTap: onSeeAll,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4.0, top: 4.0, right: 12.0),
              child: Text(
                '  See all',
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHorizontalQuestsList(ColorScheme cs) {
    _resetDailyGoalIfNeeded();
    final dailyGoalProgress = (_dailyVideosStarted / _dailyGoalTarget).clamp(0.0, 1.0);

    return SizedBox(
      height: 140,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: context.uiSpace(16)),
        children: [
          _buildQuestCard(
            cs: cs,
            title: 'Continue learning',
            subtitle: _continueLearningSubtitle(),
            progress: _continueLearningProgress(),
            icon: Icons.play_arrow_rounded,
            color: cs.primaryContainer,
            onColor: cs.onPrimaryContainer,
            width: MediaQuery.of(context).size.width * 0.75,
            onTap: _openContinueLearning,
          ),
          SizedBox(width: context.uiSpace(12)),
          _buildQuestCard(
            cs: cs,
            title: 'Daily Goal',
            subtitle: 'Watch $_dailyGoalTarget videos ($_dailyVideosStarted/$_dailyGoalTarget)',
            progress: dailyGoalProgress,
            icon: Icons.local_fire_department_rounded,
            color: cs.tertiaryContainer,
            onColor: cs.onTertiaryContainer,
            width: MediaQuery.of(context).size.width * 0.75,
            onTap: () async => GoRouter.of(context).go('/feed'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestCard({
    required ColorScheme cs,
    required String title,
    required String subtitle,
    required double progress,
    required IconData icon,
    required Color color,
    required Color onColor,
    required double width,
    required Future<void> Function() onTap,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(context.uiRadiusLg)),
      clipBehavior: Clip.hardEdge,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(context.uiSpace(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: onColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Icon(icon, color: onColor),
                    ),
                    if(progress >= 0) Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(color: onColor, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: onColor, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    Text(subtitle, style: TextStyle(color: onColor.withValues(alpha: 0.8), fontSize: 13), overflow: .ellipsis ,maxLines: 1,),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(context.uiRadiusSm),
                      child: progress >= 0 ? LinearProgressIndicator(value: progress, minHeight: 6, color: onColor, backgroundColor: onColor.withValues(alpha: 0.2)) : const SizedBox(height: 6)
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // a streak card that displays your current learning streak and encourages you to keep it going. It should show the number of consecutive days you've watched videos. it shows these days as flames on pedestals, with the ones you have completed lit up and the current day flashing if you haven't completed it yet. tapping the card takes you to your learning path to continue your streak.
  Widget _buildStreakCard(ColorScheme cs) {
    // This is a placeholder for the streak card. The actual implementation would depend on how you track and store the user's learning streak.
    return Container(
      width: MediaQuery.of(context).size.width * 0.75,
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(context.uiRadiusLg)),
      child: StreakCard(
        completedDays: currentUserStreak,
        longestStreak: bestUserStreak,
        hasIncreasedStreakToday: hasIncreasedStreakToday,
      )
    );
  }
  

  Widget _buildDiscoverCarouselGrid(ColorScheme cs) {
    if (_loading) {
      return const SizedBox(height: 280, child: Center(child: CircularProgressIndicator()));
    }

    final items = _discoverVideos ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    //a third of all of the videos
    final itemsRow1 = items.sublist(0, (items.length / 3).ceil());
    final itemsRow2 = items.sublist(itemsRow1.length, itemsRow1.length + (items.length / 3).floor());
    final itemsRow3 = items.sublist(itemsRow1.length + itemsRow2.length, itemsRow1.length + itemsRow2.length + (items.length / 3).floor());

    return SizedBox(
      height: 800,
      child: Column(
        children: [
          _AutoScrollRow(videos: itemsRow1, speed: 15, onPlayVideo: _openVideoList),
          const SizedBox(height: 16),
          _AutoScrollRow(videos: itemsRow2, speed: 45, onPlayVideo: _openVideoList),
          const SizedBox(height: 16),
          _AutoScrollRow(videos: itemsRow3, speed: 25, onPlayVideo: _openVideoList),
        ],
      ),
    );
  }
}

class _AutoScrollRow extends StatefulWidget {
  final List<Video> videos;
  final double speed;
  final Future<void> Function(List<Video> videos, {int videoIndex}) onPlayVideo;

  const _AutoScrollRow({required this.videos, required this.speed, required this.onPlayVideo});

  @override
  State<_AutoScrollRow> createState() => _AutoScrollRowState();
}

class _AutoScrollRowState extends State<_AutoScrollRow>
    with TickerProviderStateMixin {
  late final ScrollController _controller;
  late final Ticker _ticker;

  late AnimationController _hoverController;
  late Animation<double> _speedFactor;

  @override
  void initState() {
    super.initState();

    _controller = ScrollController();

    _hoverController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

    _speedFactor = Tween<double>(begin: 1.0, end: 0).animate(CurvedAnimation(parent: _hoverController, curve: Curves.easeOut));

    _ticker = createTicker((elapsed) {
      if (!_controller.hasClients) return;

      final effectiveSpeed = widget.speed * _speedFactor.value;
      final offset = _controller.offset + effectiveSpeed * 0.016;

      if (offset >= _controller.position.maxScrollExtent) {
        _controller.jumpTo(0);
      } else {
        _controller.jumpTo(offset);
      }
    });

    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MouseRegion(
        onEnter: (_) => _hoverController.forward(),
        onExit: (_) => _hoverController.reverse(),
        child: ListView.builder(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.videos.length * 3000,
          itemBuilder: (context, index) {
            final video = widget.videos[index % widget.videos.length];

            return Padding(
              key: ValueKey('${video.id}-$index'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 160,
                child: _VerticalVideoCard(
                  key: ValueKey('video-${video.id}-$index'),
                  video: video,
                  videos: widget.videos,
                  ticker: this,
                  onPlayVideo: widget.onPlayVideo,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VerticalVideoCard extends StatefulWidget {
  final Video video;
  final List<Video> videos;
  final TickerProvider ticker;
  final Future<void> Function(List<Video> videos, {int videoIndex}) onPlayVideo;

  const _VerticalVideoCard({
    super.key,
    required this.video,
    required this.videos,
    required this.ticker,
    required this.onPlayVideo,
  });

  @override
  State<_VerticalVideoCard> createState() => _VerticalVideoCardState();
}

class _VerticalVideoCardState extends State<_VerticalVideoCard> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(context.uiRadiusLg)),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: () async => widget.onPlayVideo(widget.videos, videoIndex: widget.videos.indexOf(widget.video)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: FutureBuilder(
                  future: thumbnailFor(widget.video),
                  builder: (context, snap) {
                    if (snap.hasData) {
                      return Image.memory(snap.data!, fit: BoxFit.cover, width: double.infinity);
                    }
                    return Container(color: cs.surfaceContainerHighest);
                  },
                ),
              ),

              Expanded(
                flex: 3,
                child: Padding(
                  padding: EdgeInsets.all(context.uiSpace(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        flex: 3,
                        child: Text(
                          widget.video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 13, height: 1.2),
                        ),
                      ),
                      SizedBox(height: context.uiSpace(4)),
                      Flexible(
                        child: Text(
                          widget.video.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}

class LargeCarouselVideoCard extends StatelessWidget {
  final Video video;
  final List<Video> videos;
  final TickerProvider ticker;

  const LargeCarouselVideoCard({super.key, required this.video, required this.videos, required this.ticker});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: MediaQuery.of(context).size.width * 0.8,
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(context.uiRadiusLg)),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () async => await openVideoPlayer(
          context: context,
          listedVideos: videos,
          videoIndex: videos.indexOf(video),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: FutureBuilder(
                future: thumbnailFor(video),
                builder: (context, snap) {
                  if (snap.hasData) return Image.memory(snap.data!, fit: BoxFit.cover, width: double.infinity);
                  return Container(color: cs.surfaceContainerHighest);
                },
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(video.authorName, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedListVideoCard extends StatelessWidget {
  final Video video;
  final List<Video> videos;
  final Future<void> Function(List<Video> videos, {int videoIndex}) onPlayVideo;

  const _FeedListVideoCard({required this.video, required this.videos, required this.onPlayVideo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () async => onPlayVideo(videos, videoIndex: videos.indexOf(video)),
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: FutureBuilder(
                future: thumbnailFor(video),
                builder: (context, snap) {
                  if (snap.hasData) return Image.memory(snap.data!, fit: BoxFit.cover);
                  return Container(color: cs.surfaceContainerHighest);
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      video.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
