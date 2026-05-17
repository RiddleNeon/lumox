class DeepLinkBuilder {
  const DeepLinkBuilder._();

  static String search({
    String? query,
    DeepLinkSearchScope scope = DeepLinkSearchScope.all,
    DeepLinkSearchMode mode = DeepLinkSearchMode.text,
  }) {
    final params = <String, String>{
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (scope != DeepLinkSearchScope.all) 'scope': scope.value,
      if (mode != DeepLinkSearchMode.text) 'mode': mode.value,
    };
    return Uri(
      path: '/search',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  static String feed({String? videoId}) {
    if (videoId == null || videoId.trim().isEmpty) return '/feed';
    return '/feed/${videoId.trim()}';
  }

  static String chat({String? partnerId}) {
    if (partnerId == null || partnerId.trim().isEmpty) return '/chat';
    return '/chat/${partnerId.trim()}';
  }

  static String quests({List<int>? focusIds, String? subject}) {
    final focus = (focusIds ?? const <int>[])
        .where((id) => id > 0)
        .toSet()
        .toList();
    final normalizedSubject = subject?.trim();
    final params = <String, String>{
      if (focus.isNotEmpty) 'focus': focus.join(','),
      if (normalizedSubject != null && normalizedSubject.isNotEmpty)
        'subject': normalizedSubject,
    };
    return Uri(
      path: '/quests',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  static String profile(
    String userId, {
    DeepLinkProfileTab tab = DeepLinkProfileTab.videos,
  }) {
    final normalizedId = userId.trim();
    final params = <String, String>{
      if (tab != DeepLinkProfileTab.videos) 'tab': tab.value,
    };
    return Uri(
      path: '/u/$normalizedId',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  static String ownProfile({
    DeepLinkProfileTab tab = DeepLinkProfileTab.videos,
  }) {
    final params = <String, String>{
      if (tab != DeepLinkProfileTab.videos) 'tab': tab.value,
    };
    return Uri(
      path: '/profile',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  static String themes({
    String? themeId,
    DeepLinkThemeTab tab = DeepLinkThemeTab.community,
  }) {
    if (themeId != null && themeId.trim().isNotEmpty) {
      return '/themes/${themeId.trim()}';
    }
    final params = <String, String>{
      if (tab != DeepLinkThemeTab.community) 'tab': tab.value,
    };
    return Uri(
      path: '/themes',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  static String logout() => '/logout';
}

enum DeepLinkSearchScope {
  videos('videos'),
  profiles('profiles'),
  dictionary('dictionary'),
  all('all');

  const DeepLinkSearchScope(this.value);
  final String value;
}

enum DeepLinkSearchMode {
  text('text'),
  tags('tags');

  const DeepLinkSearchMode(this.value);
  final String value;
}

enum DeepLinkProfileTab {
  videos('videos'),
  followers('followers'),
  following('following');

  const DeepLinkProfileTab(this.value);
  final String value;
}

enum DeepLinkThemeTab {
  own('own'),
  community('community');

  const DeepLinkThemeTab(this.value);
  final String value;
}
