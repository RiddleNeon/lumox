import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lumox/base_ui.dart';
import 'package:lumox/logic/themes/theme_model.dart';
import 'package:lumox/tools/supabase_tests/supabase_login_test.dart';
import 'package:lumox/ui/theme/app_theme.dart';
import 'package:lumox/ui/video/view_models/video_feed_view_model.dart';
import 'package:lumox/ui/video/view_models/youtube_feed_view_model.dart';

import 'logic/feed_recommendation/user_preference_manager.dart';
import 'logic/feed_recommendation/video_recommender_base.dart';
import 'logic/local_storage/local_seen_service.dart';
import 'logic/repositories/chat_repository.dart';
import 'logic/repositories/user_repository.dart';
import 'logic/users/user_model.dart';
import 'logic/video/video_provider.dart';

GoTrueClient get auth => supabaseClient.auth;

UserRepository userRepository = UserRepository();
ChatRepository chatRepository = ChatRepository();

UserProfile get currentUser {
  assert(_currentUser != null, "No user is currently logged in!");
  return _currentUser!;
}

set currentUser(UserProfile newUser) {
  _currentUser = newUser;
}

UserProfile? _currentUser;
bool get userLoggedIn => _currentUser != null;

VideoFeedViewModel get feedViewModel => _feedViewModel ??= VideoFeedViewModel();
YoutubeFeedViewModel get youtubeFeedViewModel => _youtubeFeedViewModel ??= YoutubeFeedViewModel();
VideoFeedViewModel? _feedViewModel;
YoutubeFeedViewModel? _youtubeFeedViewModel;

RecommendationVideoProvider? _videoProvider;
RecommendationVideoProvider get videoProvider => _videoProvider ??= RecommendationVideoProvider();

late int currentUserStreak;
bool get hasIncreasedStreakToday => _hasIncreasedStreakToday;
bool _hasIncreasedStreakToday = false;

int get bestUserStreak => _bestUserStreak;
int _bestUserStreak = 0;

Future<void> initLogic() async {
  WidgetsFlutterBinding.ensureInitialized();
  fvp.registerWith();
  if (_currentUser != null) await onUserLogout();
  await ensureSupabaseInitialized();
}

bool isUsersFirstLogin = false;

Future<void> onUserLogin(UserProfile user, bool firstTime) async {
  isUsersFirstLogin = firstTime;
  print("User logged in: ${user.id}");
  _currentUser = user;
  await onUserLoginSupabaseTest();
  useYoutubeVideosOnlyNotifier.value = bool.tryParse(await userRepository.getSetting(user.id, 'show_youtube')) ?? true;
  await clearAllWillPlaySoonReservations(userId: user.id);
  await initLocalSeenService();
  await applyThemeFromServer();
  await syncUserStreak();
}

Future<void> syncUserStreak() async {
  final streakInfo = await userRepository.getStreakInfo();
  
  currentUserStreak = streakInfo.streak;
  _hasIncreasedStreakToday = streakInfo.isUpdatedToday;
  _bestUserStreak = streakInfo.bestStreak;
  
}

Future<bool> requestStreakUpdate([bool force = false]) async {
  if(hasIncreasedStreakToday && !force) return false;
  final newStreak = await userRepository.requestStreakUpdate();
  
  _hasIncreasedStreakToday = true;
  print("Streak update requested. New streak: $newStreak");
  
  if(newStreak != currentUserStreak) {
    currentUserStreak = newStreak;
    return true;
  } else {
    return false;
  }
}

Future<void> applyThemeFromServer() async {
  final response = await supabaseClient.from('applied_themes').select().eq('user_id', currentUser.id).maybeSingle();
  
  if(response == null) {
    bool isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    
    appThemeNotifier.value = isDark ? (AppTheme.dark, defaultDarkThemeId) : (AppTheme.light, defaultLightThemeId);
    await supabaseClient.from('applied_themes').insert({'user_id': currentAuthUserId(), 'theme_id': isDark ? defaultDarkThemeId : defaultLightThemeId});
    return;
  }
  
  final themeId = response['theme_id'] as String? ?? defaultDarkThemeId;
  
  ThemeData resolvedTheme;
  String resolvedThemeId = themeId;
  if (themeId == 'default' || themeId == defaultLightThemeId) {
    resolvedTheme = AppTheme.light;
    resolvedThemeId = defaultLightThemeId;
  } else if (themeId == 'default-dark' || themeId == defaultDarkThemeId) {
    resolvedTheme = AppTheme.dark;
    resolvedThemeId = defaultDarkThemeId;
  } else {
    try {
      final themeData = await supabaseClient.from('themes').select().eq('id', themeId).single();
      resolvedTheme = CustomThemeModel.fromJson(themeData).colors.toThemeData();
    } catch (_) {
      final isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
      resolvedTheme = isDark ? AppTheme.dark : AppTheme.light;
      resolvedThemeId = isDark ? defaultDarkThemeId : defaultLightThemeId;
      await supabaseClient.from('applied_themes').upsert({'user_id': currentUser.id, 'theme_id': resolvedThemeId});
    }
  }

  appThemeNotifier.value = (resolvedTheme, resolvedThemeId);
}

String currentAuthUserId() => auth.currentUser?.id ?? currentUser.id;

String currentAuthUsername() {
  final user = auth.currentUser;
  if (user == null) return currentUser.id;

  final displayName = user.userMetadata?['full_name'];
  if (displayName != null) return displayName;

  final email = user.email;
  if (email != null && email.contains('@')) {
    return email.split('@').first;
  }
  return user.id;
}

Future<void> onUserLogout() async {
  final userId = _currentUser?.id;
  if (userId != null) {
    await clearAllWillPlaySoonReservations(userId: userId);
  }
  await auth.signOut();
  UserPreferenceManager.reset();
  await feedViewModel.dispose();
  await youtubeFeedViewModel.dispose();
  _currentUser = null;
}

bool runningOnMobile = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;

/// When true, recommendation queries should only fetch YouTube-backed videos.
final ValueNotifier<bool> useYoutubeVideosOnlyNotifier = ValueNotifier(false);