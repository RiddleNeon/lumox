import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumox/main.dart';
import 'package:lumox/transcription/uploading/video_upload_screen.dart';
import 'package:lumox/ui/misc/animations/slide_morph_transitions.dart';
import 'package:lumox/ui/auth/auth_screen.dart';
import 'package:lumox/ui/screens/profile_screen.dart';
import 'package:lumox/ui/search_screen/search_screen.dart';
import 'package:lumox/ui/settings/settings_screen.dart';
import 'package:lumox/ui/theme/theme_creation_screen.dart';
import 'package:lumox/ui/video/short_video_player.dart';
import 'package:lumox/ui/widgets/bottom_navigation_bar.dart';

import '../../base_logic.dart';
import '../../logic/feed_recommendation/search_video_result_recommender.dart';
import '../../logic/repositories/video_repository.dart';
import '../../logic/video/video.dart';
import '../chat/chat_managing_screen.dart';
import '../home/home_screen.dart';
import '../quests/quest_screen.dart';

late final GoRouter routerConfig;

void initRouter() {
  bool firstRoute = true;
  routerConfig = GoRouter(
    navigatorKey: appNavigatorKey,
    redirect: (context, state) async {
      if(state.uri.path == '/login-force') return '/login'; 
      
      if (firstRoute && state.uri.path == '/feed') {
        firstRoute = false;
        return '/home';
      }
      firstRoute = false;

      final canonicalNavPath = _canonicalNavPath(state.uri.path);
      final navBarItem = _navigationBarItems.where((element) => element.id == canonicalNavPath).firstOrNull;
      if (navBarItem != null) {
        int navBarIndex = _navigationBarItems.indexOf(navBarItem);
        if (navBarIndex != -1 && navBarKey.currentState?.currentSelectedIndex != navBarIndex) {
          if (navBarKey.currentState == null) {
            WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
              navBarKey.currentState?.switchToIndex(navBarIndex);
            });
          } else {
            navBarKey.currentState?.switchToIndex(navBarIndex);
          }
        }
      }

      final path = state.uri.path;

      final onLogin = path == '/login';
      final onResetPassword = path == '/reset-password';
      final onSignupOnboarding = path == '/signup-onboarding';
      final onLogout = path == '/logout';
      final hasSession = auth.currentSession != null;
      final onboardingDone = userLoggedIn && currentUser.onboardingCompleted && currentUser.hasAcceptedRequiredAgreements;

      if (onLogout) {
        if (hasSession || userLoggedIn) {
          await onUserLogout();
        }
        return '/login';
      }

      final from = state.uri.toString();
      final loginLocation = Uri(path: '/login', queryParameters: {'from': from}).toString();
      final onboardingLocation = Uri(path: '/signup-onboarding', queryParameters: {'from': from}).toString();

      if (!hasSession && !onLogin && !onResetPassword) {
        return loginLocation;
      }
      if (hasSession && !userLoggedIn && !onSignupOnboarding && !onResetPassword) {
        return onboardingLocation;
      }
      if (userLoggedIn && !onboardingDone && !onSignupOnboarding) {
        return onboardingLocation;
      }
      if (userLoggedIn && onboardingDone && (onLogin || onSignupOnboarding || state.matchedLocation == '/')) {
        final requested = state.uri.queryParameters['from'];
        if (requested != null && requested.startsWith('/')) {
          return requested;
        }
        return '/home';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return Scaffold(body: child, bottomNavigationBar: _bottomNavBar);
        },
        routes: [
          GoRoute(
            path: '/feed',
            pageBuilder: (context, state) =>
                SlideMorphTransitions.page<void>(key: state.pageKey, child: const VideoFeed(), beginOffset: const Offset(0.02, 0.0), beginScale: 0.995),
          ),
          GoRoute(
            path: '/feed/:videoId',
            pageBuilder: (context, state) => SlideMorphTransitions.page<void>(
              key: state.pageKey,
              child: _DeepLinkVideoScreen(videoId: state.pathParameters['videoId'] ?? '', sharedVideoIds: _parseVideoIds(state.uri.queryParameters['ids'])),
              beginOffset: const Offset(0.02, 0.0),
              beginScale: 0.995,
            ),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) {
              final scope = _searchScopeFromQuery(state.uri.queryParameters['scope']);
              final mode = _searchModeFromQuery(state.uri.queryParameters['mode']);
              final subject = state.uri.queryParameters['subject']?.trim();
              final entryId = int.tryParse(state.uri.queryParameters['id'] ?? '');
              return SlideMorphTransitions.page<void>(
                key: state.pageKey,
                child: SearchScreen(
                  initialQuery: state.uri.queryParameters['q'],
                  initialScope: scope,
                  initialMode: mode,
                  showYoutube: useYoutubeVideosOnlyNotifier.value,
                  initialDictionarySubject: subject == null || subject.isEmpty ? null : subject,
                  initialDictionaryEntryId: entryId,
                ),
                beginOffset: const Offset(0.03, 0.0),
                beginScale: 0.993,
              );
            },
          ),
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                SlideMorphTransitions.page<void>(key: state.pageKey, child: const HomeScreen(), beginOffset: const Offset(0.03, 0.0), beginScale: 0.993),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => SlideMorphTransitions.page<void>(
              key: state.pageKey,
              child: ProfileScreen(
                initialProfile: currentUser,
                ownProfile: true,
                onFollowChange: (bool followed) {},
                initialTabIndex: _profileTabIndexFromQuery(state.uri.queryParameters['tab']),
              ),
              beginOffset: const Offset(0.03, 0.0),
              beginScale: 0.993,
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => SlideMorphTransitions.page<void>(
              key: state.pageKey,
              child: const GeneralSettingsScreen(),
              beginOffset: const Offset(0.03, 0.0),
              beginScale: 0.993,
            ),
          ),
          GoRoute(
            path: '/themes',
            pageBuilder: (context, state) => SlideMorphTransitions.page<void>(
              key: state.pageKey,
              child: ThemeManagerScreen(
                initialTabIndex: _themeTabIndexFromQuery(state.uri.queryParameters['tab']),
                embedded: false,
              ),
              beginOffset: const Offset(0.03, 0.0),
              beginScale: 0.993,
            ),
          ),
          GoRoute(
            path: '/themes/:themeId',
            pageBuilder: (context, state) => SlideMorphTransitions.page<void>(
              key: state.pageKey,
              child: ThemeManagerScreen(
                initialTabIndex: _themeTabIndexFromQuery(state.uri.queryParameters['tab']),
                embedded: false,
                initialThemeId: state.pathParameters['themeId'],
              ),
              beginOffset: const Offset(0.03, 0.0),
              beginScale: 0.993,
            ),
          ),
          GoRoute(
            path: '/chat',
            pageBuilder: (context, state) => SlideMorphTransitions.page<void>(
              key: state.pageKey,
              child: ChatManagingScreen(
                preloadMoreChats: (current) => chatRepository.getChats(currentUser.id, offset: current ?? 0, limit: 15),
                initialChatPartnerId: state.uri.queryParameters['user'],
              ),
              beginOffset: const Offset(0.03, 0.0),
              beginScale: 0.993,
            ),
          ),
          GoRoute(
            path: '/chat/:userId',
            redirect: (context, state) {
              final userId = state.pathParameters['userId'];
              if (userId == null || userId.isEmpty) return '/chat';
              return Uri(path: '/chat', queryParameters: {'user': userId}).toString();
            },
          ),
          GoRoute(
            path: '/create',
            pageBuilder: (context, state) => SlideMorphTransitions.page<void>(
              key: state.pageKey,
              child: const Scaffold(body: VideoUploadWidget()),
              beginOffset: const Offset(0.03, 0.0),
              beginScale: 0.993,
            ),
          ),
          GoRoute(
            path: '/quests',
            builder: (context, state) {
              final focusIds = _parseQuestIds(state.uri.queryParameters['focus']);
              final zoomOutIfNeeded = _parseZoomOut(state.uri.queryParameters['zoom']);
              final subjectParam = state.uri.queryParameters['subject']?.trim();
              final subject = subjectParam == null || subjectParam.isEmpty ? 'General' : subjectParam;
              return QuestScreen(subject: subject, focusQuestIds: focusIds, zoomOutIfNeeded: zoomOutIfNeeded);
            },
          ),
          GoRoute(
            path: '/dictionary',
            pageBuilder: (context, state) {
              final subject = state.uri.queryParameters['subject']?.trim();
              final entryId = int.tryParse(state.uri.queryParameters['id'] ?? '');
              print("Navigating to dictionary with subject: $subject and entryId: $entryId");
              return SlideMorphTransitions.page<void>(
                key: state.pageKey,
                child: SearchScreen(
                  initialScope: SearchScope.dictionary,
                  initialMode: SearchMode.text,
                  initialDictionarySubject: subject == null || subject.isEmpty ? null : subject,
                  initialDictionaryEntryId: entryId,
                  showYoutube: useYoutubeVideosOnlyNotifier.value,
                ),
                beginOffset: const Offset(0.03, 0.0),
                beginScale: 0.993,
              );
            },
          ),
          GoRoute(
            path: '/u/:userId',
            pageBuilder: (context, state) => SlideMorphTransitions.page<void>(
              key: state.pageKey,
              child: _DeepLinkProfileScreen(
                userId: state.pathParameters['userId'] ?? '',
                initialTabIndex: _profileTabIndexFromQuery(state.uri.queryParameters['tab']),
              ),
              beginOffset: const Offset(0.03, 0.0),
              beginScale: 0.993,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) {
          return SlideMorphTransitions.page<void>(key: state.pageKey, child: const LoginScreen(), beginOffset: const Offset(0.0, 0.07), beginScale: 0.985);
        },
      ),
      GoRoute(
        path: '/signup-onboarding',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(key: state.pageKey, child: const SignupOnboardingScreen());
        },
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => const NoTransitionPage(child: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) {
          return SlideMorphTransitions.page<void>(
            key: state.pageKey,
            child: const ResetPasswordScreen(),
            beginOffset: const Offset(0.0, 0.07),
            beginScale: 0.985,
          );
        },
      ),
      GoRoute(
        path: '/logout',
        pageBuilder: (context, state) => const NoTransitionPage(child: SizedBox.shrink()),
      ),
    ],
  );
}

GlobalObjectKey<BottomNavBarState> navBarKey = const GlobalObjectKey('bottomNavBarKey');
final BottomNavBar _bottomNavBar = BottomNavBar(
  initialIndex: 2,
  key: navBarKey,
  onSelectionChange: (p0) {
    routerConfig.go(p0);
  },
  items: _navigationBarItems,
);

List<({IconData icon, String label, String id})> _navigationBarItems = [
  (icon: Icons.swipe_up_rounded, label: 'Feed', id: '/feed'),
  (icon: Icons.search, label: 'Discover', id: '/search'),
  (icon: Icons.home, label: 'Home', id: '/home'),
  (icon: Icons.person_outline, label: 'Profile', id: '/profile'),
  (icon: Icons.chat, label: 'Chat', id: '/chat'),
  (icon: CupertinoIcons.map, label: 'Quests', id: '/quests'),
];

class RouteObserver extends NavigatorObserver {
  Timer? _resumeFeedTimer;
  int _resumeFeedToken = 0;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    super.didChangeTop(topRoute, previousTopRoute);
    _resumeFeedTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final routeName = topRoute.settings.name ?? '';
      final activePath = routeName.isNotEmpty ? routeName : routerConfig.routeInformationProvider.value.uri.path;
      final navPath = _canonicalNavPath(activePath);
      navBarKey.currentState?.switchToId(navPath);

      if (activePath.startsWith('/feed')) {
        final token = ++_resumeFeedToken;
        _resumeFeedTimer = Timer(const Duration(milliseconds: 250), () {
          if (token != _resumeFeedToken) return;
          if (!routerConfig.routeInformationProvider.value.uri.path.startsWith('/feed')) return;
          unawaited(
            Future.microtask(() async {
              feedViewModel.ensureCurrentVideoPlays(
                (await videoProvider.getVideoByIndex(feedViewModel.currentIndex, useYoutubeVideos: useYoutubeVideosOnlyNotifier.value))!,
              );
            }),
          );
        });
      }
    });
  }
}


class _DeepLinkProfileScreen extends StatelessWidget {
  const _DeepLinkProfileScreen({required this.userId, required this.initialTabIndex});

  final String userId;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder(
      future: userRepository.getUser(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final profile = snapshot.data!;
        final ownProfile = profile.id == currentUser.id;
        return ProfileScreen(
          initialProfile: profile,
          ownProfile: ownProfile,
          hasBackButton: true,
          initialTabIndex: initialTabIndex,
          onFollowChange: (followed) {},
        );
      },
    );
  }
}


class _DeepLinkVideoScreen extends StatelessWidget {
  const _DeepLinkVideoScreen({required this.videoId, this.sharedVideoIds = const []});

  final String videoId;
  final List<String> sharedVideoIds;

  Future<({List<Video> videos, int initialIndex})?> _loadSharedFeedContext() async {
    if (sharedVideoIds.isEmpty) return null;

    final fetched = await videoRepo.fetchVideosByIds(sharedVideoIds);
    if (fetched.isEmpty) return null;

    final byId = {for (final video in fetched) video.id: video};
    final ordered = <Video>[];
    final seen = <String>{};
    for (final id in sharedVideoIds) {
      final video = byId[id];
      if (video != null && seen.add(video.id)) {
        ordered.add(video);
      }
    }
    if (ordered.isEmpty) return null;

    var initialIndex = ordered.indexWhere((video) => video.id == videoId);
    if (initialIndex == -1) {
      final deepLinked = await videoRepo.getVideoByIdSupabase(videoId);
      if (deepLinked != null && seen.add(deepLinked.id)) {
        ordered.insert(0, deepLinked);
        initialIndex = 0;
      } else {
        initialIndex = 0;
      }
    }

    return (videos: ordered, initialIndex: initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (videoId.isEmpty) {
      return const VideoFeed();
    }

    return FutureBuilder(
      future: _loadSharedFeedContext(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final sharedContext = snapshot.data;
        if (sharedContext != null && sharedContext.videos.isNotEmpty) {
          return VideoFeed(
            customVideoProvider: SearchVideoResultRecommender(listedVideos: sharedContext.videos),
            initialPage: sharedContext.initialIndex,
            itemCount: sharedContext.videos.length,
          );
        }

        return FutureBuilder<Video>(
          future: videoRepo.getVideoById(videoId),
          builder: (context, fallbackSnapshot) {
            if (fallbackSnapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!fallbackSnapshot.hasData) {
              return const VideoFeed();
            }
            return VideoFeed(customVideoProvider: SingleVideoProvider(fallbackSnapshot.data!), initialPage: 0, itemCount: 1);
          },
        );
      },
    );
  }
}

String _canonicalNavPath(String path) {
  if (path.startsWith('/feed')) return '/feed';
  if (path.startsWith('/home')) return '/home';
  if (path.startsWith('/search')) return '/search';
  if (path.startsWith('/chat')) return '/chat';
  if (path.startsWith('/profile')) return '/profile';
  if (path.startsWith('/quests')) return '/quests';
  if (path.startsWith('/dictionary')) return '/search';
  return path;
}

SearchScope _searchScopeFromQuery(String? value) {
  switch (value) {
    case 'videos':
      return SearchScope.videos;
    case 'profiles':
      return SearchScope.profiles;
    case 'dictionary':
      return SearchScope.dictionary;
    default:
      return SearchScope.all;
  }
}

SearchMode _searchModeFromQuery(String? value) {
  switch (value) {
    case 'tags':
      return SearchMode.tags;
    default:
      return SearchMode.text;
  }
}

int _profileTabIndexFromQuery(String? value) {
  switch (value) {
    case 'followers':
      return 1;
    case 'following':
      return 2;
    default:
      return 0;
  }
}

List<int> _parseQuestIds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw.split(',').map((id) => int.tryParse(id.trim())).whereType<int>().toList();
}

bool _parseZoomOut(String? value) {
  if (value == null) return true;
  return value == 'out' || value == 'true' || value == '1';
}

int _themeTabIndexFromQuery(String? value) {
  switch (value) {
    case 'community':
      return 1;
    case 'own':
      return 0;
    default:
      return 1;
  }
}

List<String> _parseVideoIds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final seen = <String>{};
  final ids = <String>[];
  for (final part in raw.split(',')) {
    final id = part.trim();
    if (id.isEmpty) continue;
    if (seen.add(id)) {
      ids.add(id);
    }
  }
  return ids;
}
