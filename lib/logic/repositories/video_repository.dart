import 'dart:convert';

import 'package:lumox/logic/comments/comment.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/tools/supabase_tests/supabase_login_test.dart';

import '../../base_logic.dart';
import 'chat_repository.dart';

VideoRepository videoRepo = VideoRepository();

class VideoRepository {
  Future<Video> getVideoById(String id) async {
    final video = await getVideoByIdSupabase(id);
    if (video == null) throw StateError('Video $id not found');
    return video;
  }

  Future<Video?> getVideoByIdSupabase(String id) async {
    final supabaseVid = await supabaseClient
        .from('videos')
        .select('''
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
        ''')
        .eq('id', id)
        .eq('is_published', true)
        .maybeSingle();
    if (supabaseVid == null) return null;
    return _toVideo(supabaseVid);
  }

  Future<void> publishVideo({
    required String title,
    required String description,
    required String videoUrl,
    String? thumbnailUrl,
    required String authorId,
    List<String> tags = const [],
  }) async {
    await publishVideoSupabase(title: title, description: description, videoUrl: videoUrl, thumbnailUrl: thumbnailUrl, authorId: authorId, tags: tags);
  }

  Future<void> publishVideoSupabase({
    required String title,
    required String description,
    required String videoUrl,
    String? thumbnailUrl,
    required String authorId,
    List<String> tags = const [],
    int commentCount = 0,
  }) async {
    final publishedVideoId =
        (await supabaseClient
                .from('videos')
                .insert({
                  'title': title,
                  'description': description,
                  'video_url': videoUrl,
                  'thumbnail_url': thumbnailUrl ?? '',
                  'author_id': authorId,
                  'is_published': true,
                  'comment_count': commentCount,
                })
                .select('id')
                .single())['id']
            as int;
    if (tags.isNotEmpty) {
      final upsertedTags = await supabaseClient.from('tags').upsert(tags.map((tag) => {'name': tag.toLowerCase()}).toList(), onConflict: 'name').select('id');

      final videoTags = upsertedTags.map((tag) => {'video_id': publishedVideoId, 'tag_id': tag['id']}).toList();
      await supabaseClient.from('video_tags').upsert(videoTags, onConflict: 'video_id, tag_id');
    }
  }

  // Toggles like for the given video and user. Returns true if the video is now liked, false if it's now unliked. Also removes dislike if it exists.
  Future<bool> toggleLike(String videoId) async {
    final String result = await supabaseClient.rpc('toggle_like', params: {'p_video_id': _parseVideoId(videoId)});
    return result == 'liked';
  }

  Future<bool> toggleDislike(String videoId) async {
    final String result = await supabaseClient.rpc('toggle_dislike', params: {'p_video_id': _parseVideoId(videoId)});
    return result == 'disliked';
  }

  Future<void> incrementViewCount(String videoId) async {
    await recordViewSupabase(_parseVideoId(videoId));
  }

  Future<void> recordViewSupabase(int videoId) async {
    await _adjustVideoMetric(videoId, 'view_count', 1);
  }

  Future<void> incrementShareCount(String videoId) async {
    await incrementShareCountSupabase(_parseVideoId(videoId));
  }

  Future<void> incrementShareCountSupabase(int videoId) async {
    print('Skipping share count update for $videoId because the provided videos schema has no share_count column.');
  }

  Future<Comment> addComment(String videoId, Comment comment) async {
    return postCommentSupabase(
      videoId: _parseVideoId(videoId),
      content: comment.message,
      parentId: comment.parentId == null ? null : int.tryParse(comment.parentId!),
    );
  }

  Future<Comment> postCommentSupabase({required int videoId, required String content, int? parentId}) async {
    int insertedId = await supabaseClient.rpc(
      'post_comment',
      params: {'p_author_id': currentUser.id, 'p_video_id': videoId, 'p_parent_id': parentId, 'p_content': content},
    );
    
    
    // structure of errors:
    // < 0: error
    // < -1000 used bad words, the more negative the id, the more bad words were used, so -1005 means 5 bad words, -1010 means 10 bad words, etc.
    // == -5000 user is banned (no further information provided)
    // < -5000 is banned and used bad words, the more negative the id, the more bad words were used, so -5005 means banned with 5 bad words, -5010 means banned with 10 bad words, etc.
    bool isError = insertedId < 0;
    
    bool isUserBanned = insertedId <= -5000;
    int usedBadWords = isError ? (-insertedId - (isUserBanned ? 5000 : 1000)) : 0;

    if (usedBadWords > 0 && isUserBanned) {
      print("User is banned and message contains $usedBadWords content warnings. error message: $insertedId");
      throw UserBannedException("Your account has been banned due to repeated violations of our content guidelines. Additionally, this message contained content that may violate our guidelines. Please contact support for more information.");
    } else if (usedBadWords > 0) {
      throw ContentModerationViolationException(usedBadWords, "Message sent but contains content that may violate our guidelines. Please review the content and try again.");
    } else if(isUserBanned) {
      throw UserBannedException("Your account has been banned due to repeated violations of our content guidelines. Please contact support for more information.");
    }
    
    

    return Comment(
      id: insertedId.toString(),
      userId: currentUser.id,
      username: currentUser.username,
      userProfileImageUrl: currentUser.profileImageUrl,
      message: content,
      date: DateTime.now(),
      parentId: parentId?.toString(),
      depth: parentId == null ? 0 : 1,
      replyCount: 0,
      likeCount: 0,
    );
  }

  Future<({List<Comment> comments, int? nextOffset})> getComments(String videoId, {String? commentId, int offset = 0, int limit = 20}) async {
    final comments = await getCommentsWithLikeSupabase(
      videoId: int.parse(videoId),
      parentCommentId: commentId == null ? null : int.tryParse(commentId),
      limit: limit,
      offset: offset,
    );
    print('Fetched ${comments.length} comments for video $videoId with parentCommentId $commentId, offset $offset, limit $limit');
    return (comments: comments, nextOffset: comments.length < limit ? null : offset + comments.length);
  }

  Future<List<Comment>> getCommentsWithLikeSupabase({required int videoId, int? parentCommentId, int limit = 20, int offset = 0}) async {
    final rpcResult = await supabaseClient.rpc(
      'get_comments_with_like',
      params: {
        'p_video_id': videoId,
        'p_current_user': currentUser.id,
        'p_parent_id': parentCommentId,
        'p_limit': limit,
        'p_offset': offset,
      },
    );

    if (rpcResult == null) {
      print("RPC result is null, returning empty comment list");
      return [];
    }

    if (rpcResult is Map<String, dynamic>) {
      print("RPC result is a single comment, mapping it directly");
      return [_mapComment(rpcResult)];
    }

    late final List rows;
    try {
      rows = (rpcResult.data as List).cast();
    } catch (_) {
      rows = (rpcResult as List).cast();
    }

    print("RPC returned ${rows.length} comments for video $videoId with parentCommentId $parentCommentId, offset $offset, limit $limit");

    return rows.map<Comment>((e) => _mapComment(e)).toList();
  }

  Comment _mapComment(Map<String, dynamic> e) {
    final Map<String, dynamic> profiles = e['profiles'] is String
        ? (jsonDecode(e['profiles']) as Map<String, dynamic>)
        : (e['profiles'] as Map<String, dynamic>);
    final mapped = {
      'id': e['id'],
      'author_id': e['author_id'],
      'profiles': profiles,
      'content': e['content'],
      'created_at': e['created_at'],
      'like_count': e['like_count'],
      'parent_id': e['parent_id'],
      'reply_count': e['reply_count'],
      'liked_by_current_user': e['liked_by_current_user'],
    };
    final liked = (e['liked_by_current_user'] as bool?);
    return Comment.fromSupabase(mapped, likedByMe: liked);
  }

  Future<bool> toggleCommentLike(String commentId) async {
    final parsedCommentId = int.tryParse(commentId);
    if (parsedCommentId == null) {
      throw FormatException('Expected numeric Supabase comment id, got: $commentId');
    }
    final bool result = await supabaseClient.rpc('toggle_like_comment', params: {'p_comment_id': parsedCommentId});
    return result;
  }

  Future<void> saveVideo(String userId, String videoId) async => saveVideoSupabase(userId, _parseVideoId(videoId));

  Future<void> saveVideoSupabase(String userId, int videoId) async {
    await supabaseClient.from('saved_videos').upsert({'user_id': userId, 'video_id': videoId}, onConflict: 'user_id, video_id');
  }

  Future<void> unsaveVideo(String userId, String videoId) async => unsaveVideoSupabase(userId, _parseVideoId(videoId));

  Future<void> unsaveVideoSupabase(String userId, int videoId) async {
    await supabaseClient.from('saved_videos').delete().eq('user_id', userId).eq('video_id', videoId);
  }

  Future<void> reportVideo(String userId, String videoId, String reason) async => reportVideoSupabase(userId, _parseVideoId(videoId), reason);

  Future<void> reportVideoSupabase(String userId, int videoId, String reason) async {
    await supabaseClient.from('video_reports').insert({'user_id': userId, 'video_id': videoId, 'reason': reason, 'status': 'pending'});
  }

  Future<void> flush() async {}

  int get pendingOperations => 0;

  Future<List<Video>> getFollowingFeed(String userId, {int limit = 20}) async {
    return getFollowingFeedSupabase(userId, limit: limit);
  }

  Future<List<Video>> getFollowingFeedSupabase(String userId, {int limit = 20, int offset = 0}) async {
    final followingIds = (await supabaseClient.from('follows').select('following_id').eq('follower_id', userId))
        .map((e) => e['following_id'] as String)
        .toList();
    if (followingIds.isEmpty) return [];

    final result = await supabaseClient
        .from('videos')
        .select(_videoSelect)
        .inFilter('author_id', followingIds)
        .eq('is_published', true)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return result.map<Video>(_toVideo).toList();
  }

  Future<List<Video>> getTrendingVideos({int limit = 20}) async => getTrendingVideosSupabase(limit: limit);

  Future<List<Video>> getTrendingVideosSupabase({int limit = 20}) async {
    final result = await supabaseClient
        .from('videos')
        .select(_videoSelect)
        .eq('is_published', true)
        .gte('created_at', DateTime.now().subtract(const Duration(days: 300)).toIso8601String())
        .order('view_count', ascending: false)
        .limit(limit);
    return result.map<Video>(_toVideo).toList();
  }

  /// searches all videos where title, description or tags contain the query (case-insensitive), ordered by relevance desc then creation date and popularity desc. Also contains unprecise full text search, so "funny" will match "funny videos". For more precise tag search, use [searchVideosByTag].
  Future<({List<Video> videos, int? nextOffset})> searchVideos(String query, {int limit = 20, int offset = 0, bool withAuthor = false, bool showYoutube = false}) async {
    final videos = await searchVideosSupabase(query, limit: limit, offset: offset, withAuthor: withAuthor, showYoutube: showYoutube);
    return (videos: videos, nextOffset: videos.length < limit ? null : offset + videos.length);
  }

  Future<List<Video>> searchVideosSupabase(String query, {int limit = 20, int offset = 0, bool withAuthor = false, bool showYoutube = false}) async {
    final result = await supabaseClient.rpc(
      withAuthor ? 'search_videos_with_author' : 'search_videos',
      params: {'search_query': query, 'p_limit': limit, 'p_offset': offset, 'p_show_youtube': showYoutube},
    );

    return (result as List).map<Video>((e) => _toVideo(e)).toList();
  }

  /// returns the total length of the search result of the search query, without pagination. Useful for showing total result count in the UI.
  Future<int> countSearchVideos(String query) async {
    final result = await supabaseClient.rpc('count_search_videos', params: {'search_query': query});
    return result as int;
  }

  ///searches all videos with a given tag, ordered by creation date desc. Warning: only outputs videos with that exact tag, so "funny" won't match "funny videos". Use [searchVideos] for more flexible search.
  Future<({List<Video> videos, int? nextOffset})> searchVideosByTag(String tag, {int limit = 20, int offset = 0}) async {
    final videos = await searchVideosByTagSupabase(tag, limit: limit, offset: offset);
    return (videos: videos, nextOffset: videos.length < limit ? null : offset + videos.length);
  }

  Future<List<Video>> searchVideosByTagSupabase(String tag, {int limit = 20, int offset = 0, bool onlyUnseen = false}) async {
    final userId = onlyUnseen ? supabaseClient.auth.currentUser?.id : null;

    final result = await supabaseClient
        .rpc('get_filtered_video_tags', params: {
      'p_tag_name': tag,
      'p_user_id': userId,
      'p_limit': limit,
      'p_offset': offset,
    })
        .select('''
        videos (
          $_videoSelectInner
        )
      ''');

    return result
        .where((e) => e['videos'] != null)
        .map((e) => _toVideo(e['videos'] as Map<String, dynamic>))
        .toList();
  }
  Future<List<Video>> getVideosByTags(List<String> tags, {int limit = 20}) async {
    return getVideosByTagsSupabase(tags, limit: limit);
  }

  Future<List<Video>> getVideosByTagsSupabase(List<String> tags, {int limit = 20, int offset = 0}) async {
    final taggedVideoIds = await supabaseClient.from('video_tags').select('video_id, tags!inner(name)').inFilter('tags.name', tags);
    final videoIds = taggedVideoIds.map((e) => e['video_id']).toSet().toList();
    if (videoIds.isEmpty) return [];

    final result = await supabaseClient
        .from('videos')
        .select(_videoSelect)
        .inFilter('id', videoIds)
        .eq('is_published', true)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return result.map<Video>(_toVideo).toList();
  }

  Future<List<Video>> getRelatedVideos(Video video, {int limit = 10}) async => getRelatedVideosSupabase(video, limit: limit);

  Future<List<Video>> getRelatedVideosSupabase(Video video, {int limit = 10}) async {
    if (video.tags.isEmpty) return [];
    final taggedVideoIds = await supabaseClient.from('video_tags').select('video_id, tags!inner(name)').inFilter('tags.name', video.tags.take(5).toList());
    final videoIds = taggedVideoIds.map((e) => e['video_id']).where((id) => id.toString() != video.id).toSet().toList();
    if (videoIds.isEmpty) return [];

    final result = await supabaseClient
        .from('videos')
        .select(_videoSelect)
        .inFilter('id', videoIds)
        .eq('is_published', true)
        .order('created_at', ascending: false)
        .limit(limit);
    return result.map<Video>(_toVideo).toList();
  }

  Future<List<Video>> getSavedVideos(String userId, {int limit = 20}) async => getSavedVideosSupabase(userId, limit: limit);

  Future<List<Video>> getSavedVideosSupabase(String userId, {int limit = 20, int offset = 0}) async {
    final result = await supabaseClient
        .from('saved_videos')
        .select('''
          video_id,
          videos (
            $_videoSelectInner
          )
        ''')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return result.where((e) => e['videos'] != null).map((e) => _toVideo(e['videos'] as Map<String, dynamic>)).toList();
  }

  Future<List<Video>> fetchVideosByIds(List<String> ids) async {
    final parsedIds = ids.map(int.tryParse).whereType<int>().toList();
    return fetchVideosByIdsSupabase(parsedIds);
  }

  Future<List<Video>> fetchVideosByIdsSupabase(List<int> ids) async {
    if (ids.isEmpty) return [];
    final result = await supabaseClient.from('videos').select(_videoSelect).inFilter('id', ids);
    return result.map<Video>(_toVideo).toList();
  }

  Future<void> _adjustVideoMetric(int videoId, String column, int delta) async {
    await supabaseClient.rpc('increment_video_metric', params: {'p_video_id': videoId, 'p_column': column, 'p_delta': delta});
  }

  Video _toVideo(Map<String, dynamic> data) {
    final profile = (data['profiles'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final authorName = profile['display_name'] ?? profile['username'] ?? data['display_name'] ?? data['username'] ?? data['profile_display_name'] ?? data['profile_username'] ?? 'Unknown';
    final tags = (data['tags'] as List? ?? const []).map<String>((e) => e.toString()).toList();
    return Video.fromSupabase(data, authorName, tags);
  }

  int _parseVideoId(String videoId) {
    final parsedVideoId = int.tryParse(videoId);
    if (parsedVideoId == null) {
      throw FormatException('Expected numeric Supabase video id, got: $videoId');
    }
    return parsedVideoId;
  }

  Future<({Video? continueVideo, int dailyStartedCount})> getHomeLearningSnapshot({
    required String userId,
    DateTime? now,
  }) async {
    final continueVideoFuture = getContinueLearningVideo(userId: userId);
    final dailyCountFuture = getDailyStartedCount(userId: userId, day: now);
    final continueVideo = await continueVideoFuture;
    final dailyCount = await dailyCountFuture;
    return (continueVideo: continueVideo, dailyStartedCount: dailyCount);
  }

  Future<Video?> getContinueLearningVideo({required String userId}) async {
    final row = await supabaseClient
        .from('user_interactions')
        .select('''
          video_id,
          videos (
            $_videoSelectInner
          )
        ''')
        .eq('user_id', userId)
        .eq('interaction_type', 'view')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    final rawVideo = row['videos'];
    if (rawVideo is! Map<String, dynamic>) return null;
    return _toVideo(rawVideo);
  }

  Future<int> getDailyStartedCount({required String userId, DateTime? day}) async {
    final local = (day ?? DateTime.now()).toLocal();
    final start = DateTime(local.year, local.month, local.day);
    final end = start.add(const Duration(days: 1));

    final rows = await supabaseClient
        .from('user_interactions')
        .select('video_id')
        .eq('user_id', userId)
        .eq('interaction_type', 'view')
        .gte('created_at', start.toUtc().toIso8601String())
        .lt('created_at', end.toUtc().toIso8601String());

    return rows.length;
  }

  Future<void> recordLearningStart(String videoId, {required String userId}) async {
    final parsedVideoId = _parseVideoId(videoId);
    await supabaseClient.from('user_interactions').insert({
      'user_id': userId,
      'video_id': parsedVideoId,
      'interaction_type': 'view',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'liked': false,
      'watch_time': 0,
      'additional_data': {'source': 'home'},
    });
  }
}

const String _videoSelectInner = '''
  *,
  profiles!videos_author_id_fkey (
    display_name,
    username,
    avatar_url,
    followers_count,
    following_count,
    total_videos_count,
    total_likes_count,
    created_at,
    bio,
    id
  ),
  video_tags (
    tags (
      name
    )
  )
''';

const String _videoSelect = _videoSelectInner;
