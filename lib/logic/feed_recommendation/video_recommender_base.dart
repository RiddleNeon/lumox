import 'package:lumox/base_logic.dart';
import 'package:lumox/logic/feed_recommendation/user_interaction.dart';
import 'package:lumox/logic/feed_recommendation/user_preference_manager.dart';
import 'package:lumox/logic/feed_recommendation/user_preferences.dart';

import '../../tools/supabase_tests/supabase_login_test.dart';
import '../local_storage/local_seen_service.dart';
import '../repositories/video_repository.dart';
import '../video/video.dart';

abstract class VideoRecommenderBase {
  late final UserPreferenceManager preferenceManager;

  VideoRecommenderBase() {
    preferenceManager = UserPreferenceManager();
  }

  Future<UserPreferences> getUserPreferences() async {
    await preferenceManager.loadCache();
    return UserPreferences(
      tagPreferences: preferenceManager.cachedTagPrefs.map((k, v) => MapEntry(k, v.engagementScore)),
      authorPreferences: preferenceManager.cachedAuthorPrefs.map((k, v) => MapEntry(k, v.engagementScore)),
      avgCompletionRate: preferenceManager.cachedAvgCompletion,
      totalInteractions: preferenceManager.cachedTotalInteractions,
    );
  }

  double calculatePersonalizationScore(Video video, UserPreferences userPreferences) {
    final preferredTags = userPreferences.tagPreferences;
    final preferredAuthors = userPreferences.authorPreferences;
    if (preferredTags.isEmpty && preferredAuthors.isEmpty) return 0.5;

    double score = 0.0;
    int factors = 0;

    if (video.tags.isNotEmpty && preferredTags.isNotEmpty) {
      double tagScore = 0.0;
      int matchedTags = 0;
      for (final tag in video.tags) {
        if (preferredTags.containsKey(tag)) {
          tagScore += preferredTags[tag]!;
          matchedTags++;
        }
      }
      if (matchedTags > 0) {
        score += tagScore / matchedTags;
        factors++;
      }
    }

    if (preferredAuthors.containsKey(video.authorId)) {
      score += preferredAuthors[video.authorId]!;
      factors++;
    }

    return factors > 0 ? (score / factors) : 0.5;
  }

  Future<List<Video>> getColdStartVideos({int limit = 20}) async {
    final videos = await videoRepo.getTrendingVideos(limit: limit * 2);
    videos.shuffle();
    return videos.take(limit).toList();
  }

  Future<List<Video>> fetchNewVideos(DateTime? newestSeen, int limit, {bool onlyUnseen = false}) async {
    final snapshot = await supabaseClient.rpc('get_new_videos', params: {
      'p_user_id': currentUser.id,
      'p_cursor': newestSeen?.toIso8601String(),
      'p_limit': limit,
      'p_only_unseen': onlyUnseen,
    }).select(_recommenderVideoSelect);

    var videos = snapshot.map<Video>(_mapVideo).toList();
    videos = videos.where((v) => !_willPlaySoonVideoIds.contains(v.id)).toList();

    if (onlyUnseen && videos.isNotEmpty) {
      await markVideosWillPlaySoon(userId: currentUser.id, videos: videos);
    }

    return videos;
  }

  Future<List<Video>> fetchOldVideos(DateTime? oldestSeen, int limit) async {
    return fetchNewVideos(oldestSeen, limit);
  }

  Future<Set<Video>> fetchTrendingVideos({required int limit, bool onlyUnseen = false, bool useYoutubeVids = false}) async {
    final snapshot = await supabaseClient.rpc('get_trending_candidates', params: {
      'p_user_id': currentUser.id,
      'p_cursor': null,
      'p_limit': limit * 3,
      'p_only_unseen': onlyUnseen,
      'p_days_back': 356,
      'p_use_youtube': useYoutubeVids,
    }).select(_recommenderVideoSelect);

    var videos = snapshot.map<Video>(_mapVideo).toList();

    videos = videos.where((v) => !localSeenService.hasSeen(v.id) && !_willPlaySoonVideoIds.contains(v.id)).toList();

    if (videos.isNotEmpty) {
      videos.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await localSeenService.saveTrendingCursor(videos.first.createdAt);
    }

    videos.sort((a, b) => calculateGlobalEngagementScore(b).compareTo(calculateGlobalEngagementScore(a)));

    final selectedVideos = videos.take(limit).toList();
    if (onlyUnseen && selectedVideos.isNotEmpty) {
      await markVideosWillPlaySoon(userId: currentUser.id, videos: selectedVideos);
    }

    return selectedVideos.toSet();
  }
  
  Future<List<Video>> fetchVideosByTag(String tag, {required int limit, required void Function() onTagVideosEmpty, bool onlyUnseen = false}) async {
    final snapshot = await supabaseClient.rpc('get_videos_by_tag', params: {
      'p_tag_name': tag,
      'p_user_id': currentUser.id,
      'p_limit': limit,
      'p_offset': 0,
      'p_only_unseen': onlyUnseen,
    }).select(_recommenderVideoSelect);

    final List<Video> videos = snapshot.map<Video>(_mapVideo).toList();

    var unseen = videos.where((v) => !localSeenService.hasSeen(v.id) && !_willPlaySoonVideoIds.contains(v.id)).toList();
    if (unseen.isEmpty) {
      onTagVideosEmpty();
    }

    if (onlyUnseen && unseen.isNotEmpty) {
      await markVideosWillPlaySoon(userId: currentUser.id, videos: unseen);
    }

    return unseen;
  }

  double calculateGlobalEngagementScore(Video video) {
    int views = video.viewsCount ?? 1;
    final likes = video.likesCount ?? 0;
    final comments = video.commentsCount ?? 0;
    if (views == 0) views = 1;

    final engagementRate = (likes + comments * 1.5 + 1) / views;
    return (engagementRate * 100).clamp(0.0, 1.0);
  }
}

Future<void> trackInteraction({
  required String userId,
  required Video video,
  required double watchTime,
  required double videoDuration,
  bool liked = false,
  bool disliked = false,
  bool shared = false,
  bool commented = false,
  bool saved = false,
}) async {
  await releaseVideosWillPlaySoon(userId: userId, videoIds: [video.id]);

  await supabaseClient.from('user_interactions').insert({
    'user_id': userId,
    'video_id': video.id,
    'created_at': DateTime.now().toIso8601String(),
    'interaction_type': _interactionTypeView,
    'liked': liked,
    'watch_time': watchTime,
  });
  
  await UserPreferenceManager().updatePreferences(
    video: video,
    normalizedEngagementScore: calculateNormalizedEngagementScore(
      calculateEngagementScore(liked: liked, disliked: disliked, shared: shared, commented: commented, saved: saved, completionRate: watchTime / videoDuration),
    ),
  );
  
  if(!hasIncreasedStreakToday) {
    await requestStreakUpdate();
    print("Streak updated after interaction.");
  }
}

Future<void> markVideosWillPlaySoon({
  required String userId,
  required Iterable<Video> videos,
}) async {
  final now = DateTime.now().toIso8601String();
  final payload = <Map<String, dynamic>>[];

  for (final video in videos) {
    if (_willPlaySoonVideoIds.contains(video.id)) continue;
    _willPlaySoonVideoIds.add(video.id);
    payload.add({
      'user_id': userId,
      'video_id': video.id,
      'created_at': now,
      'interaction_type': _interactionTypeWillPlaySoon,
      'liked': false,
      'watch_time': 0.0,
    });
  }

  if (payload.isEmpty) return;

  try {
    await supabaseClient.from('user_interactions').insert(payload);
  } catch (error) {
    for (final row in payload) {
      final videoId = row['video_id']?.toString();
      if (videoId != null) _willPlaySoonVideoIds.remove(videoId);
    }
    // Keep feed loading even if backend has not been migrated to this interaction type yet.
    print('Failed to reserve play-soon videos: $error');
  }
}

Future<void> releaseVideosWillPlaySoon({
  required String userId,
  required Iterable<String> videoIds,
}) async {
  final ids = videoIds.where((id) => id.isNotEmpty).toSet().toList();
  if (ids.isEmpty) return;

  _willPlaySoonVideoIds.removeAll(ids);

  try {
    await supabaseClient
        .from('user_interactions')
        .delete()
        .eq('user_id', userId)
        .eq('interaction_type', _interactionTypeWillPlaySoon)
        .inFilter('video_id', ids);
  } catch (error) {
    print('Failed to release play-soon videos: $error');
  }
}

Future<void> clearAllWillPlaySoonReservations({required String userId}) async {
  _willPlaySoonVideoIds.clear();
  try {
    await supabaseClient
        .from('user_interactions')
        .delete()
        .eq('user_id', userId)
        .eq('interaction_type', _interactionTypeWillPlaySoon);
  } catch (error) {
    print('Failed to clear play-soon reservations: $error');
  }
}

Video _mapVideo(Map<String, dynamic> data) {
  final profile = (data['profiles'] as Map<String, dynamic>? ?? const {});
  final authorName = profile['display_name'] ?? profile['username'] ?? '';
  final tags = (data['video_tags'] as List? ?? const []).map((vt) => vt['tags']?['name'] as String?).whereType<String>().toList();
  return Video.fromSupabase(data, authorName, tags);
}

const String _recommenderVideoSelectInner = '''
  *,
  profiles!videos_author_id_fkey (
    display_name,
    username
  ),
  video_tags (
    tags (
      name
    )
  )
''';

const String _recommenderVideoSelect = _recommenderVideoSelectInner;

const String _interactionTypeView = 'view';
const String _interactionTypeWillPlaySoon = 'will_play_soon';
final Set<String> _willPlaySoonVideoIds = <String>{};

