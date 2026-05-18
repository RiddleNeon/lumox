import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lumox/logic/repositories/user_repository.dart' as user_repo;
import 'package:lumox/logic/users/user_model.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/ui/misc/animations/slide_morph_transitions.dart';
import 'package:lumox/ui/router/deep_link_builder.dart';
import 'package:lumox/ui/misc/avatar.dart';
import 'package:lumox/ui/misc/preloading_list.dart';
import 'package:lumox/ui/router/router.dart';
import 'package:lumox/ui/widgets/logout_button.dart';
import 'package:lumox/ui/widgets/overlays/buttons/follow_button.dart';

import '../../base_logic.dart';
import '../../logic/local_storage/local_seen_service.dart';
import '../misc/basic_player.dart';
import '../misc/profile_image_picker.dart';
import '../misc/rolling_digit_counter.dart';
import '../search_screen/search_query.dart';
import '../search_screen/search_video_overlay.dart';
import '../search_screen/widgets/search_user_card.dart';
import '../search_screen/widgets/search_video_card.dart';
import '../theme/theme_ui_values.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile initialProfile;
  final bool ownProfile;
  final bool hasBackButton;
  final void Function(bool followed) onFollowChange;
  final bool initialFollowed;
  final int initialTabIndex;

  const ProfileScreen({
    super.key,
    required this.initialProfile,
    required this.ownProfile,
    this.hasBackButton = false,
    required this.onFollowChange,
    this.initialFollowed = false,
    this.initialTabIndex = 0,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  bool _editingMode = false;
  late final TabController _tabController;
  late UserProfile user = widget.initialProfile;

  late final SearchQuery<UserProfile> _followingQuery;
  late final SearchQuery<UserProfile> _followersQuery;
  late final SearchQuery<Video> _videoQuery;

  final GlobalKey<AnimatedPreloadingListState<UserProfile>> _followingListKey = GlobalKey<AnimatedPreloadingListState<UserProfile>>();
  final GlobalKey<AnimatedPreloadingListState<UserProfile>> _followersListKey = GlobalKey<AnimatedPreloadingListState<UserProfile>>();
  final GlobalKey<AnimatedPreloadingListState<UserProfile>> _videoListKey = GlobalKey<AnimatedPreloadingListState<UserProfile>>();
  StreamSubscription<user_repo.FollowChangeEvent>? _followChangesSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.index = widget.initialTabIndex.clamp(0, 2);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _videoQuery = SearchQuery(
      (limit, offset) {
        return userRepository.getPublishedVideos(user.id, limit: limit, offset: offset);
      },
      () {
        return userRepository.getPublishedVideosCount(user.id);
      },
    );
    _followingQuery = SearchQuery(
      (limit, offset) {
        return userRepository.getFollowing(user.id, limit: limit, offset: offset);
      },
      () {
        return userRepository.getFollowingCount(user.id);
      },
    );
    _followersQuery = SearchQuery(
      (limit, offset) {
        return userRepository.getFollowers(user.id, limit: limit, offset: offset);
      },
      () {
        return userRepository.getFollowersCount(user.id);
      },
    );
    _followingQuery.preloadMore(limit: 8);
    _followersQuery.preloadMore(limit: 8);

    if (widget.ownProfile) {
      _followChangesSub = userRepository.followChanges.listen(_onOwnFollowChanged);
    }
  }

  @override
  void dispose() {
    _followChangesSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex == widget.initialTabIndex) return;
    _tabController.animateTo(widget.initialTabIndex.clamp(0, 2));
  }

  Future<void> _onOwnFollowChanged(user_repo.FollowChangeEvent event) async {
    if (!mounted || event.followerId != user.id) return;

    final listState = _followingListKey.currentState;
    final containsInList = listState?.items.any((u) => u.id == event.targetUserId) ?? false;

    if (event.followed) {
      UserProfile? followedUser = event.targetUser;
      followedUser ??= _followingQuery.results.where((u) => u.id == event.targetUserId).firstOrNull;
      followedUser ??= localSeenService.getAuthorFromCache(event.targetUserId);
      followedUser ??= await userRepository.getUserSupabase(event.targetUserId);
      if (!mounted || followedUser == null) {
        _syncOwnFollowingCount();
        return;
      }
      final targetUser = followedUser;

      if (!_followingQuery.results.any((u) => u.id == targetUser.id)) {
        _followingQuery.results.insert(0, targetUser);
      }

      if (listState != null && !containsInList) {
        listState.addItem(targetUser);
      }
    } else {
      _followingQuery.results.removeWhere((u) => u.id == event.targetUserId);
      if (listState != null) {
        final currentIndex = listState.items.indexWhere((u) => u.id == event.targetUserId);
        if (currentIndex != -1) {
          final removedUser = listState.items[currentIndex];
          final cs = Theme.of(context).colorScheme;
          listState.removeItem(currentIndex, (context, anim) => _buildSqueezeItem(removedUser, anim, cs));
        }
      }
    }

    _syncOwnFollowingCount();
  }

  void _syncOwnFollowingCount() {
    if (!mounted) return;
    setState(() {
      user = user.copyWith(followingCount: currentUser.followingCount ?? user.followingCount);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              floating: false,
              automaticallyImplyLeading: widget.hasBackButton,
              expandedHeight: 380,
              backgroundColor: cs.surface,
              surfaceTintColor: cs.surfaceTint.withValues(alpha: 0),
              elevation: 0,
              titleSpacing: 0,
              title: _buildCollapsedTitle(cs),
              flexibleSpace: FlexibleSpaceBar(collapseMode: CollapseMode.pin, background: _buildProfileHeader(cs)),
              bottom: PreferredSize(preferredSize: const Size.fromHeight(60), child: _buildTabBar(cs)),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              AnimatedPreloadingList<Video>(
                key: _videoListKey,
                query: _videoQuery,
                notFoundWidget: _buildTab(cs, Icons.grid_on_rounded, 'No published videos'),
                itemBuilder: (context, video, animation, index, videos) {
                  return SizeTransition(
                    sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
                    axisAlignment: -1.0,
                    child: SlideMorphTransitions.build(
                      animation,
                      VideoCard(
                        video: video,
                        onTap: () async {
                          int likesChanged = await openVideoPlayer(context: context, listedVideos: videos.whereType<Video>().toList(), videoIndex: index);
                          if (likesChanged != 0) {
                            setState(() {
                              user = user.copyWith(totalLikesCount: max((user.totalLikesCount ?? 0) + likesChanged, 0));
                            });
                          }
                        },
                        cs: cs,
                      ),
                      beginOffset: const Offset(0, 0.08),
                      beginScale: 0.98,
                    ),
                  );
                },
              ),
              AnimatedPreloadingList<UserProfile>(
                key: _followersListKey,
                query: _followersQuery,
                notFoundWidget: _buildTab(cs, FontAwesomeIcons.users, 'No followers'),
                itemBuilder: (context, itemUser, animation, index, users) {
                  return SizeTransition(
                    sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
                    axisAlignment: -1.0,
                    child: SlideMorphTransitions.build(
                      animation,
                      UserCard(
                        initialUser: itemUser,
                        cs: cs,
                        key: ValueKey(itemUser.id),
                        onFollowChange: (followed) {
                          if (user.id != currentUser.id) return;
                          setState(() {
                            if (followed) {
                              user = user.copyWith(followingCount: (user.followingCount ?? 0) + 1);
                              _followingListKey.currentState?.addItem(itemUser);
                            } else {
                              user = user.copyWith(followingCount: max((user.followingCount ?? 0) - 1, 0));
                              final currentIndex = _followingListKey.currentState?.items.indexOf(itemUser) ?? -1;
                              if (currentIndex != -1) {
                                _followingListKey.currentState?.removeItem(currentIndex, (context, anim) => _buildSqueezeItem(itemUser, anim, cs));
                                //_followingListKey.currentState?.preloadMore(limit: 1); //fixme
                                print('Removed user ${itemUser.username} from following list');
                              } else {
                                print('Tried to remove user ${itemUser.username} from following list, but they were not found in the list');
                              }
                            }
                          });
                        },
                      ),
                      beginOffset: const Offset(0, 0.08),
                      beginScale: 0.98,
                    ),
                  );
                },
              ),
              AnimatedPreloadingList<UserProfile>(
                key: _followingListKey,
                query: _followingQuery,
                notFoundWidget: _buildTab(cs, Icons.person_add_alt_1, 'Not following anyone yet'),
                itemBuilder: (context, itemUser, animation, index, users) {
                  return SizeTransition(
                    sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
                    axisAlignment: -1.0,
                    child: SlideMorphTransitions.build(
                      animation,
                      UserCard(
                        initialUser: itemUser,
                        cs: cs,
                        key: ValueKey(itemUser.id),
                        onFollowChange: (followed) {
                          if (!followed) {
                            final currentIndex = _followingListKey.currentState?.items.indexOf(itemUser) ?? -1;
                            if (currentIndex != -1) {
                              _followingListKey.currentState?.removeItem(currentIndex, (context, anim) => _buildSqueezeItem(itemUser, anim, cs));
                              //_followingListKey.currentState?.preloadMore(limit: 1); //fixme
                            }
                          }
                          setState(() {
                            if (followed) {
                              user = user.copyWith(followingCount: (user.followingCount ?? 0) + 1);
                            } else {
                              user = user.copyWith(followingCount: max((user.followingCount ?? 0) - 1, 0));
                            }
                          });
                        },
                      ),
                      beginOffset: const Offset(0, 0.08),
                      beginScale: 0.98,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSqueezeItem(UserProfile user, Animation<double> animation, ColorScheme cs) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeInOutQuart),
      axisAlignment: -1.0,
      child: SizeTransition(
        sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeInOutQuart),
        axis: Axis.horizontal,
        child: SlideMorphTransitions.build(
          animation,
          UserCard(initialUser: user, cs: cs),
          beginOffset: const Offset(-0.08, 0),
          beginScale: 0.98,
        ),
      ),
    );
  }

  Widget _buildCollapsedTitle(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: 0.95),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(context.uiRadiusMd), bottomRight: Radius.circular(context.uiRadiusMd)),
      ),
      height: kToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.ownProfile) ...[const SizedBox(width: 16), const LogoutButton()] else const SizedBox(width: 48),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    user.username,
                    style: TextStyle(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (widget.ownProfile) ...[
            IconButton(
              icon: Icon(Icons.settings, color: cs.onSurface),
              onPressed: () {
                routerConfig.push('/settings');
              },
              onLongPress: () {
                showRickDialog(context);
              },
            ),
            const SizedBox(width: 16),
          ] else
            const SizedBox(width: 96),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(ColorScheme cs) {
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.only(top: kToolbarHeight),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _buildAvatar(cs),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user.displayName,
                style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3),
              ),
              if (user.isBot) ...[const SizedBox(width: 8), _buildBotBadge(cs)],
            ],
          ),
          Text(
            '@${user.username}',
            style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3),
          ),
          widget.ownProfile ? const SizedBox(height: 16) : const SizedBox(height: 5),
          _buildStatsRow(cs),
          const SizedBox(height: 8),
          _buildActionRow(cs),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildAvatar(ColorScheme cs) {
    final avatar = SizedBox(
      width: 92,
      height: 92,
      child: InkWell(
        onTap: () => openAvatarFullScreen(context, user.profileImageUrl, user.username),
        child: Hero(
          tag: 'avatar_${user.username}',
          child: Avatar(name: user.username, colorScheme: cs, imageUrl: user.profileImageUrl),
        ),
      ),
    );

    if (widget.ownProfile && _editingMode) {
      return Stack(
        children: [
          avatar,
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _showProfileImageChangeOverlay,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                child: Icon(Icons.edit_rounded, size: 14, color: cs.onPrimary),
              ),
            ),
          ),
        ],
      );
    }

    return avatar;
  }

  Future<void> openAvatarFullScreen(BuildContext context, String? imageUrl, String username) async {
    if (imageUrl == null || imageUrl.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        pageBuilder: (_, _, _) {
          final cs = Theme.of(context).colorScheme;

          return GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: FractionallySizedBox(
                    heightFactor: 0.7,
                    widthFactor: 0.7,
                    child: Card(
                      child: Hero(
                        tag: 'avatar_$username',
                        child: Avatar(name: username, colorScheme: cs, imageUrl: imageUrl),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsRow(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStatItem(cs, user.followersCount, 'Followers'),
        _buildStatDivider(cs),
        _buildStatItem(cs, user.followingCount ?? 0, 'Following'),
        _buildStatDivider(cs),
        _buildStatItem(cs, user.totalLikesCount ?? 0, 'Likes'),
      ],
    );
  }

  Widget _buildStatItem(ColorScheme cs, int value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          RollingDigitCounter(
            value: value,
            style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider(ColorScheme cs) {
    return Container(width: 1, height: 22, color: cs.outlineVariant);
  }

  Widget _buildBotBadge(ColorScheme cs, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.65)),
      ),
      child: Text(
        'bot',
        style: TextStyle(color: cs.onTertiaryContainer, fontSize: compact ? 10 : 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildActionRow(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.ownProfile)
          _ActionButton(
            label: _editingMode ? 'Save' : 'Edit profile',
            width: 148,
            filled: _editingMode,
            cs: cs,
            onTap: () => setState(() {
              _editingMode = !_editingMode;
              if (!_editingMode && newPPUrl != null) {
                userRepository.updateProfileImageUrl(currentUser, newPPUrl).then((value) {
                  currentUser = value;
                  user = value;
                  if (mounted) setState(() {});
                });
                newPPUrl = null;
              }
            }),
          ),
        if (!widget.ownProfile) ...[
          const SizedBox(width: 8),
          FollowButton(
            design: FollowButtonDesign.docked,
            initialSubscribed: widget.initialFollowed,
            onChanged: (followed) async {
              WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
                if (mounted) {
                  setState(() {
                    user = user.copyWith(followersCount: user.followersCount + (followed ? 1 : -1));

                    if (followed) {
                      if (_followersListKey.currentState == null) {
                        _followersQuery.results.add(currentUser);
                      } else {
                        _followersListKey.currentState?.addItem(currentUser);
                      }
                    } else {
                      if (_followersListKey.currentState == null) {
                        _followersQuery.results.removeWhere((element) => element.id == currentUser.id);
                      } else {
                        final currentIndex =
                            _followersListKey.currentState?.items.indexOf(
                              _followersListKey.currentState?.items.where((element) => element.id == currentUser.id).singleOrNull ?? currentUser,
                            ) ??
                            -1;
                        if (currentIndex != -1) {
                          _followersListKey.currentState?.removeItem(currentIndex, (context, anim) => _buildSqueezeItem(currentUser, anim, cs));
                        }
                      }
                    }

                    widget.onFollowChange(followed);
                  });
                }
              });
            },
            user: user,
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Report user',
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 46,
                height: 38,
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(context.uiRadiusSm), topRight: Radius.circular(context.uiRadiusSm)),
                ),
                child: Icon(Icons.flag_rounded, size: 20, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Chat with User',
            child: GestureDetector(
              onTap: () {
                routerConfig.go(DeepLinkBuilder.chat(partnerId: user.id));
              },
              child: Container(
                width: 46,
                height: 38,
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(context.uiRadiusSm), topRight: Radius.circular(context.uiRadiusSm)),
                ),
                child: Icon(Icons.chat, size: 20, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      height: 54,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ProfileSegmentButton(
              icon: Icons.grid_on_rounded,
              selected: _tabController.index == 0,
              tooltip: 'published videos',
              onTap: () => _tabController.animateTo(0),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ProfileSegmentButton(
              icon: FontAwesomeIcons.users,
              selected: _tabController.index == 1,
              tooltip: 'followers',
              onTap: () => _tabController.animateTo(1),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ProfileSegmentButton(
              icon: Icons.person_add_alt_1,
              selected: _tabController.index == 2,
              tooltip: 'following',
              onTap: () => _tabController.animateTo(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(ColorScheme cs, IconData icon, String label, [List<Widget>? items]) {
    if (items == null || items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return ListView(children: items);
  }

  Widget _buildAnimatedUserCard(
    UserProfile item,
    Animation<double> animation,
    int index,
    GlobalKey<AnimatedListState> listKey,
    List<UserProfile> currentList,
    ColorScheme cs,
  ) {
    final curvedAnimation = CurvedAnimation(parent: animation, curve: Curves.easeInOutQuart);

    return SizeTransition(
      sizeFactor: curvedAnimation,
      axis: Axis.vertical,
      axisAlignment: -1.0,
      child: SizeTransition(
        sizeFactor: curvedAnimation,
        axis: Axis.horizontal,
        axisAlignment: 0.0,
        child: SlideMorphTransitions.build(
          curvedAnimation,
          UserCard(
            key: ValueKey(item.id),
            initialUser: item,
            cs: cs,
            onFollowChange: (followed) {
              if (!followed) {
                _removeItemWithAnimation(index, listKey, currentList, cs);
              }
            },
          ),
          beginOffset: const Offset(-0.08, 0),
          beginScale: 0.98,
        ),
      ),
    );
  }

  void _removeItemWithAnimation(int index, GlobalKey<AnimatedListState> listKey, List<UserProfile> currentList, ColorScheme cs) {
    if (index < 0 || index >= currentList.length) return;

    final removedItem = currentList[index];

    listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildAnimatedUserCard(removedItem, animation, index, listKey, currentList, cs),
      duration: const Duration(milliseconds: 450),
    );

    currentList.removeAt(index);

    setState(() {
      user = user.copyWith(followingCount: max((user.followingCount ?? 0) - 1, 0));
    });
  }

  String? newPPUrl;

  void _showProfileImageChangeOverlay() async {
    newPPUrl = await showProfileImagePicker(context);
    setState(() {
      user = user.copyWith(profileImageUrl: newPPUrl);
    });
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.width, required this.filled, required this.cs, required this.onTap});

  final String label;
  final double width;
  final bool filled;
  final ColorScheme cs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: 38,
        decoration: BoxDecoration(
          color: filled ? cs.primary : cs.surfaceContainerLowest,
          border: Border.all(color: filled ? cs.primary : cs.outlineVariant, width: 1.5),
          borderRadius: BorderRadius.circular(context.uiRadiusSm),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: filled ? cs.onPrimary : cs.onSurface, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          ),
        ),
      ),
    );
  }
}

class _ProfileSegmentButton extends StatelessWidget {
  const _ProfileSegmentButton({required this.icon, required this.selected, required this.tooltip, required this.onTap});

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? cs.secondaryContainer.withValues(alpha: 0.75) : Colors.transparent,
            borderRadius: BorderRadius.circular(context.uiRadiusMd),
            border: selected ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)) : null,
          ),
          child: Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              scale: selected ? 1.06 : 1.0,
              child: Icon(icon, size: 20, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
