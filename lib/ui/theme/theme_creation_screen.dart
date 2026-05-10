import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_file_saver/flutter_web_file_saver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:lumox/base_ui.dart';
import 'package:lumox/logic/themes/theme_model.dart';
import 'package:lumox/ui/router/deep_link_builder.dart';
import 'package:lumox/ui/theme/theme_editor_screen.dart';
import 'package:lumox/ui/widgets/overlays/share_button.dart';
import 'package:flutter/services.dart';
import 'package:lumox/logic/chat/chat.dart';
import 'package:lumox/logic/chat/chat_message.dart';
import 'package:lumox/base_logic.dart';
import 'package:lumox/logic/local_storage/local_seen_service.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';

import 'app_theme.dart';

class ThemeManagerScreen extends StatefulWidget {
  const ThemeManagerScreen({super.key, this.initialTabIndex = 0, this.embedded = false, this.initialThemeId});

  final int initialTabIndex;
  final bool embedded;
  final String? initialThemeId;

  @override
  State<ThemeManagerScreen> createState() => _ThemeManagerScreenState();
}

class _ThemeManagerScreenState extends State<ThemeManagerScreen> with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  List<CustomThemeModel> _myThemes = [];
  List<CustomThemeModel> _communityThemes = [];
  Set<ShareContact> _shareContacts = const {};
  final Map<String, Chat> _chatByPartnerId = {};
  final Set<String> _savedThemeIds = {};
  final Set<String> _ownedThemeIds = {};
  final Map<String, String> _creatorNamesById = {};
  String? _selectedThemeId;
  bool _loadingMine = true;
  bool _loadingCommunity = true;

  final Set<String> _likedIds = {};

  static final CustomThemeModel _defaultTheme = CustomThemeModel(
    id: 'default',
    name: 'Default Cappuccino',
    colors: CustomThemeColors.fromPrimary(AppTheme.lightScheme.primary, dark: false),
  );

  static final CustomThemeModel _defaultThemeDark = CustomThemeModel(
    id: 'default-dark',
    name: 'Default Cappuccino - Dark',
    colors: CustomThemeColors.fromPrimary(AppTheme.lightScheme.primary, dark: true),
  );

  String _normalizeThemeId(String id) {
    if (id == defaultLightThemeId) return 'default';
    if (id == defaultDarkThemeId) return 'default-dark';
    return id;
  }

  @override
  void initState() {
    super.initState();
    _selectedThemeId = _normalizeThemeId(appThemeNotifier.value.$2);
    // If an initial theme ID is provided via deep link, set it to be selected
    final shouldAutoApplyTheme = widget.initialThemeId != null && widget.initialThemeId!.isNotEmpty;
    if (shouldAutoApplyTheme) {
      _selectedThemeId = widget.initialThemeId;
    }
    _loadMyThemes();
    _loadCommunityThemes().then((_) {
      // After loading community themes, if this was a deep link, apply the theme
      if (shouldAutoApplyTheme && mounted) {
        applyTheme(widget.initialThemeId!, pushToServer: true);
      }
    });
    _loadLikedIds();
  }

  String? get _uid => _supabase.auth.currentUser?.id;

  bool _isOwnedTheme(CustomThemeModel theme) => _ownedThemeIds.contains(theme.id);

  String? _creatorNameForTheme(CustomThemeModel theme) {
    final creatorId = theme.createdBy;
    if (creatorId == null) return null;
    if (creatorId == _uid) return 'You';
    return _creatorNamesById[creatorId] ?? _shortUserId(creatorId);
  }

  Future<void> _hydrateCreatorNames(Iterable<CustomThemeModel> themes) async {
    final idsToLookup = themes
        .map((t) => t.createdBy)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !_creatorNamesById.containsKey(id))
        .toSet();
    if (idsToLookup.isEmpty) return;

    final resolved = <String, String>{};
    try {
      final rows = await _supabase.from('profiles').select('id, username, display_name').inFilter('id', idsToLookup.toList());
      for (final row in rows as List) {
        final id = row['id'] as String?;
        if (id == null || id.isEmpty) continue;
        final displayName = (row['display_name'] as String?)?.trim();
        final username = (row['username'] as String?)?.trim();
        resolved[id] =
            (displayName != null && displayName.isNotEmpty) ? displayName : (username != null && username.isNotEmpty) ? '@$username' : _shortUserId(id);
      }
    } catch (e) {
      debugPrint('Error loading creator usernames: $e');
    }

    for (final id in idsToLookup) {
      resolved.putIfAbsent(id, () => _shortUserId(id));
    }

    if (!mounted || resolved.isEmpty) return;
    setState(() {
      _creatorNamesById.addAll(resolved);
    });
  }

  Future<bool> _saveThemeReference(String themeId) async {
    if (_uid == null) return false;
    try {
      await _supabase.from('saved_themes').upsert({'user_id': _uid, 'theme_id': themeId}, onConflict: 'user_id,theme_id');
      _savedThemeIds.add(themeId);
      return true;
    } catch (_) {
      final alreadySaved =
          await _supabase.from('saved_themes').select('theme_id').eq('user_id', _uid!).eq('theme_id', themeId).maybeSingle() != null;
      if (alreadySaved) {
        _savedThemeIds.add(themeId);
        return false;
      }

      try {
        await _supabase.from('saved_themes').insert({'user_id': _uid, 'theme_id': themeId});
      } catch (_) {
        await _supabase.from('saved_themes').insert({'user_id': _uid, 'theme_id': themeId});
      }

      _savedThemeIds.add(themeId);
      return true;
    }
  }

  Future<void> _loadMyThemes() async {
    if (_uid == null) {
      if (mounted) setState(() => _loadingMine = false);
      return;
    }
    try {
      final savedRows = await _supabase.from('saved_themes').select('theme_id').eq('user_id', _uid!);
      final savedIds = (savedRows as List).map((e) => e['theme_id'] as String).toSet();

      final ownedRows = await _supabase.from('themes').select().eq('created_by', _uid!);
      final ownedThemes = (ownedRows as List)
          .where((e) => e['id'] != defaultLightThemeId && e['id'] != defaultDarkThemeId)
          .map((e) => CustomThemeModel.fromJson(e))
          .toList();
      final ownedIds = ownedThemes.map((e) => e.id).toSet();

      final savedThemes = savedIds.isEmpty
          ? <CustomThemeModel>[]
          : ((await _supabase.from('themes').select().inFilter('id', savedIds.toList())) as List)
              .where((e) => e['id'] != defaultLightThemeId && e['id'] != defaultDarkThemeId)
              .map((e) => CustomThemeModel.fromJson(e))
              .toList();

      final mergedById = <String, CustomThemeModel>{
        for (final t in savedThemes) t.id: t,
        for (final t in ownedThemes) t.id: t,
      };

      if (mounted) {
        setState(() {
          _savedThemeIds
            ..clear()
            ..addAll(savedIds);
          _ownedThemeIds
            ..clear()
            ..addAll(ownedIds);
          _myThemes = mergedById.values.toList();
          _loadingMine = false;
        });
      }
      await _hydrateCreatorNames(mergedById.values);
    } catch (e) {
      debugPrint('Error loading my themes: $e');
      if (mounted) setState(() => _loadingMine = false);
    }
  }

  Future<void> _loadCommunityThemes() async {
    try {
      final res = await _supabase.from('themes').select().eq('is_public', true).order('likes_count', ascending: false);
      if (mounted) {
        setState(() {
          _communityThemes = (res as List)
              .where((element) => element['id'] != defaultDarkThemeId && element['id'] != defaultLightThemeId)
              .map((e) => CustomThemeModel.fromJson(e))
              .toList();
          _loadingCommunity = false;
        });
      }
      await _hydrateCreatorNames(_communityThemes);
    } catch (e) {
      debugPrint('Error loading community themes: $e');
      if (mounted) setState(() => _loadingCommunity = false);
    }
  }

  Future<void> _loadLikedIds() async {
    if (_uid == null) return;
    try {
      final res = await _supabase.from('theme_likes').select('theme_id').eq('user_id', _uid!);
      if (mounted) {
        setState(() {
          _likedIds.clear();
          _likedIds.addAll((res as List).map((e) => e['theme_id'] as String));
        });
      }
    } catch (_) {}
  }

  Future<void> _saveTheme(CustomThemeModel theme) async {
    try {
      if (_uid == null) return;

      final toSave = theme.copyWith(createdBy: _uid);
      await _supabase.from('themes').upsert(toSave.toJson(), onConflict: 'id');
      await _saveThemeReference(toSave.id);

      await _loadMyThemes();
      await _loadCommunityThemes();
      if (_selectedThemeId == toSave.id) {
        await applyTheme(toSave.id, pushToServer: false, force: true);
      }
      if (!mounted) return;
      showSnackBar(context, 'Theme saved.');
    } catch (e) {
      debugPrint('Error saving theme: $e');
      if (!mounted) return;
      showSnackBar(context, 'Error while saving: $e');
    }
  }

  Future<void> _deleteTheme(CustomThemeModel theme) async {
    final isOwned = _isOwnedTheme(theme);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isOwned ? 'delete theme?' : 'remove from gallery?'),
        content: Text(isOwned ? '"${theme.name}" will be deleted permanently.' : '"${theme.name}" will only be removed from your gallery.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _supabase.from('saved_themes').delete().eq('theme_id', theme.id).eq('user_id', _uid!);
      if (isOwned) {
        await _supabase.from('themes').delete().eq('id', theme.id).eq('created_by', _uid!);
      }
      setState(() {
        _savedThemeIds.remove(theme.id);
        _myThemes.removeWhere((t) => t.id == theme.id);
        if (_selectedThemeId == theme.id) _selectedThemeId = null;
      });
      await _loadCommunityThemes();
    } catch (e) {
      debugPrint('Error deleting theme: $e');
    }
  }

  Future<void> _toggleLike(String themeId) async {
    if (_uid == null) {
      print('User not logged in, cannot toggle like.');
      return;
    }
    try {
      print('Toggling like for theme $themeId');
      final toggleResult = (await _supabase.rpc('toggle_theme_like', params: {'p_theme_id': themeId}).select().maybeSingle()) as bool?;
      if (toggleResult == null) {
        print('Unexpected toggle result: $toggleResult');
        return;
      } else {
        if (!mounted) return;
        setState(() {
          if (toggleResult) {
            _likedIds.add(themeId);
          } else {
            _likedIds.remove(themeId);
          }
        });
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
      await _loadCommunityThemes();
      await _loadLikedIds();
    }
  }

  Future<void> applyTheme(String id, {bool pushToServer = true, bool force = false}) async {
    final normalizedId = _normalizeThemeId(id);
    if (!force && _selectedThemeId == normalizedId) return;

    if (mounted) {
      setState(() => _selectedThemeId = normalizedId);
    }

    final serverThemeId = normalizedId == 'default'
        ? defaultLightThemeId
        : normalizedId == 'default-dark'
            ? defaultDarkThemeId
            : normalizedId;

    appThemeNotifier.value = (getTheme(normalizedId), serverThemeId);
    if (pushToServer && _uid != null) {
      await _supabase.from("applied_themes").upsert({'user_id': _uid, 'theme_id': serverThemeId});
    }

    if (!mounted) return;
    //showSnackBar(context, 'Theme applied!');
  }

  Future<void> _openEditor({CustomThemeModel? existing}) async {
    final result = await Navigator.push<CustomThemeModel>(context, MaterialPageRoute(builder: (_) => ThemeEditorScreen(existingTheme: existing)));
    if (result != null) await _saveTheme(result);
  }

  Future<void> _prepareShareContactsForTheme(CustomThemeModel theme) async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final currentThemeLink = '${Uri.base.origin}/themes/${theme.id}';
    final chats = localSeenService.getChats();
    final contacts = <ShareContact>{};
    final chatMap = <String, Chat>{};

    for (final chat in chats) {
      final messages = await localSeenService.getMessagesWithLocal(
        chat.partnerId,
        limit: 180,
        startOffset: now.add(const Duration(seconds: 1)),
      );
      final myRecentMessages = messages.where((message) => message.isMe && message.timestamp.isAfter(thirtyDaysAgo)).toList();
      final mySharesOfCurrentTheme = messages.where((message) => message.isMe && message.text.trim() == currentThemeLink).toList();
      final lastSharedAt = myRecentMessages.isEmpty ? chat.lastMessageAt : myRecentMessages.last.timestamp;
      final lastSharedThisThemeAt = mySharesOfCurrentTheme.isEmpty ? null : mySharesOfCurrentTheme.last.timestamp;

      contacts.add(
        ShareContact(
          id: chat.partnerId,
          name: chat.partnerName,
          avatarUrl: chat.partnerProfileImageUrl,
          recentShareCount: myRecentMessages.length,
          lastSharedAt: lastSharedAt,
          alreadySharedWithThisVideo: mySharesOfCurrentTheme.isNotEmpty,
          lastSharedThisVideoAt: lastSharedThisThemeAt,
        ),
      );
      chatMap[chat.partnerId] = chat;
    }

    if (!mounted) return;
    setState(() {
      _shareContacts = contacts;
      _chatByPartnerId
        ..clear()
        ..addAll(chatMap);
    });
  }

  Future<void> _shareToContact(ShareContact contact, String link) async {
    final chat = _chatByPartnerId[contact.id];
    if (chat == null) return;

    final message = ChatMessage(
      id: '${contact.id}-${DateTime.now().microsecondsSinceEpoch}',
      text: link,
      isMe: true,
      timestamp: DateTime.now(),
    );

    await chatRepository.sendNotification(chat: chat, message: message);
    if (!mounted) return;
    // We don't eagerly refresh the contacts here; overlays usually refresh after sending.
  }

  Future<void> _openShareForTheme(CustomThemeModel theme) async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(theme.colors.style.radiusXl))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Share "${theme.name}"', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Send to a contact to message them this theme, or copy the link to share anywhere.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
               const SizedBox(height: 8),
               ShareButton(
                 shareUrl: DeepLinkBuilder.themes(themeId: theme.id),
                 loadContacts: () async {
                   await _prepareShareContactsForTheme(theme);
                   return _shareContacts;
                 },
                 onCopyLink: (l) async {
                  await Clipboard.setData(ClipboardData(text: l));
                  if (!ctx.mounted) return;
                  showSnackBar(ctx, 'Link copied to clipboard');
                },
                onShareToContact: (c, l) async {
                  await _shareToContact(c, l);
                  if (!ctx.mounted) return;
                  showSnackBar(ctx, 'Sent');
                },
                onShared: () {},
                emptyStateLabel: 'No recent chats',
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportTheme() async {
    if (_selectedThemeId == null) {
      showSnackBar(context, 'Choose a theme first.');

      return;
    }
    final theme = [_defaultTheme, _defaultThemeDark, ..._myThemes].firstWhere((t) => t.id == _selectedThemeId!, orElse: () => _defaultThemeDark);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(theme.toJson());
    await FlutterWebFileSaver.saveText(content: jsonStr, filename: "${theme.name.replaceAll(' ', '_')}.json");
    if (!mounted) return;
    showSnackBar(context, 'Exported!}');
  }

  Future<void> _importTheme() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (result == null) return;

      final file = result.files.first.bytes!;
      final fileAsString = utf8.decode(file);
      final json = jsonDecode(fileAsString) as Map<String, dynamic>;
      final imported = CustomThemeModel.fromJson(json).copyWith(id: const Uuid().v4(), isPublic: false);
      await _saveTheme(imported);
      if (!mounted) return;
      showSnackBar(context, '"${imported.name}" imported!');
    } catch (e) {
      if (!mounted) return;
      showSnackBar(context, 'Import failed: $e');
    }
  }

  ThemeData getTheme(String id) {
    if (id == 'default' || id == defaultLightThemeId) return AppTheme.light;
    if (id == 'default-dark' || id == defaultDarkThemeId) return AppTheme.dark;
    final theme = [..._myThemes, ..._communityThemes].firstWhere((t) => t.id == id, orElse: () => _defaultTheme);
    return theme.colors.toThemeData();
  }

  @override
  Widget build(BuildContext context) {
    final content = DefaultTabController(
      key: ValueKey(widget.initialTabIndex.clamp(0, 1)),
      initialIndex: widget.initialTabIndex.clamp(0, 1),
      length: 2,
      child: widget.embedded
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Theme Manager', style: Theme.of(context).textTheme.titleLarge),
                      ),
                      IconButton(icon: const Icon(Icons.file_download_outlined), onPressed: _importTheme, tooltip: 'import theme from file'),
                      IconButton(icon: const Icon(Icons.file_upload_outlined), onPressed: _exportTheme, tooltip: 'export selected theme to file'),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _openEditor(),
                        icon: const Icon(Icons.color_lens_outlined),
                        label: const Text('create new'),
                      ),
                    ],
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.palette_outlined), text: 'My Themes'),
                    Tab(icon: Icon(Icons.public), text: 'Community'),
                  ],
                ),
                Expanded(child: TabBarView(children: [_buildMyThemesTab(), _buildCommunityTab()])),
              ],
            )
          : Scaffold(
              appBar: AppBar(
                backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
                title: const Text('Theme Manager'),
                actions: [
                  IconButton(icon: const Icon(Icons.file_download_outlined), onPressed: _importTheme, tooltip: 'import theme from file'),
                  IconButton(icon: const Icon(Icons.file_upload_outlined), onPressed: _exportTheme, tooltip: 'export selected theme to file'),
                ],
                bottom: const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.palette_outlined), text: 'My Themes'),
                    Tab(icon: Icon(Icons.public), text: 'Community'),
                  ],
                ),
              ),
              body: TabBarView(children: [_buildMyThemesTab(), _buildCommunityTab()]),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.color_lens_outlined),
                label: const Text('create new'),
              ),
            ),
    );

    return content;
  }

  Widget _buildMyThemesTab() {
    if (_loadingMine) return const Center(child: CircularProgressIndicator());

    final all = [_defaultTheme, _defaultThemeDark, ..._myThemes];

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(context.uiSpace(16), context.uiSpace(16), context.uiSpace(16), context.uiSpace(96)),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        crossAxisSpacing: context.uiSpace(14),
        mainAxisSpacing: context.uiSpace(14),
        childAspectRatio: 0.85,
      ),
      itemCount: all.length,
      itemBuilder: (context, i) {
        final theme = all[i];
        final isSelected = _selectedThemeId == theme.id;
        final isDefault = theme.id == 'default' || theme.id == 'default-dark';
        final isOwned = _isOwnedTheme(theme);
        final creatorName = _creatorNameForTheme(theme);
        final c = theme.colors;

        return GestureDetector(
          onTap: () => applyTheme(theme.id),
          onLongPress: isDefault ? null : () => _deleteTheme(theme),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(c.style.radiusLg),
              border: Border.all(color: isSelected ? c.primary : Colors.transparent, width: context.uiFocusedBorderWidth),
            ),
            child: ThemePreview(
              c: c,
              theme: theme,
              isDefault: isDefault,
              openEditor: isDefault
                  ? null
                  : ({required CustomThemeModel existing}) async {
                      if (!_isOwnedTheme(existing)) {
                        showSnackBar(context, 'Create a local copy to edit themes from other creators.');
                        final result = await Navigator.push<CustomThemeModel>(
                          context,
                          MaterialPageRoute(builder: (_) => ThemeEditorScreen(existingTheme: existing)),
                        );
                        if (result == null) return;
                        final fork = result.copyWith(
                          id: const Uuid().v4(),
                          createdBy: _uid,
                          isPublic: false,
                          likesCount: 0,
                          originalThemeId: existing.id,
                        );
                        await _saveTheme(fork);
                        return;
                      }
                      await _openEditor(existing: existing);
                    },
              saveTheme: isOwned ? _saveTheme : null,
              deleteTheme: isDefault ? null : _deleteTheme,
              isSelected: isSelected,
              onShare: _openShareForTheme,
              creatorName: isOwned ? 'you' : isDefault ? 'default' : creatorName,
              showCreatorInline: true,
              isPublic: !isDefault && theme.isPublic,
              showVisibilityBadge: !isDefault,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommunityTab() {
    if (_loadingCommunity) return const Center(child: CircularProgressIndicator());
    if (_communityThemes.isEmpty) {
      return const Center(child: Text('No public themes yet! Create and share yours with the community.'));
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(context.uiSpace(16), context.uiSpace(16), context.uiSpace(16), context.uiSpace(96)),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        crossAxisSpacing: context.uiSpace(14),
        mainAxisSpacing: context.uiSpace(14),
        childAspectRatio: 0.85,
      ),
      itemCount: _communityThemes.length,
      itemBuilder: (context, i) {
        final theme = _communityThemes[i];
        final c = theme.colors;
        final isSelected = _selectedThemeId == theme.id;
        final isLiked = _likedIds.contains(theme.id);
        final creatorName = _creatorNameForTheme(theme);

        return GestureDetector(
          onTap: () async {
            try {
              final wasSavedNow = await _saveThemeReference(theme.id);
              if (wasSavedNow) {
                await _loadMyThemes();
              }
              await applyTheme(theme.id);
              if (context.mounted && wasSavedNow) {
                showSnackBar(context, 'Added to your gallery.');
              }
            } catch (e) {
              print("Error applying community theme: $e");
              if (context.mounted) {
                showSnackBar(context, 'Unable to save/apply this theme right now.');
              }
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(c.style.radiusLg),
              border: Border.all(color: isSelected ? c.primary : Colors.transparent, width: context.uiFocusedBorderWidth),
            ),
            child: ThemePreview(
              key: ValueKey(theme.id),
              c: c,
              theme: theme,
              isDefault: false,
              openEditor: null,
              saveTheme: null,
              deleteTheme: null,
              isSelected: isSelected,
              onShare: _openShareForTheme,
              onLikeToggle: _toggleLike,
              likesCount: theme.likesCount,
              initiallyLiked: isLiked,
              creatorName: theme.createdBy == _uid ? 'you' : creatorName,
              showCreatorInline: true,
              isPublic: theme.isPublic,
              showVisibilityBadge: true,
            ),
          ),
        );
      },
    );
  }
}

class ThemePreview extends StatefulWidget {
  final CustomThemeColors c;
  final CustomThemeModel theme;
  final bool isDefault;
  final Future<void> Function({required CustomThemeModel existing})? openEditor;
  final Future<void> Function(CustomThemeModel)? saveTheme;
  final Future<void> Function(CustomThemeModel)? deleteTheme;
  final Future<void> Function(CustomThemeModel)? onShare;
  final bool isSelected;

  final String? creatorName;
  final bool showCreatorInline;
  final bool isPublic;
  final bool showVisibilityBadge;
  final int? likesCount;
  final void Function(String)? onLikeToggle;
  final bool initiallyLiked;

  const ThemePreview({
    super.key,
    required this.c,
    required this.theme,
    required this.isDefault,
    required this.openEditor,
    required this.saveTheme,
    required this.deleteTheme,
    required this.isSelected,
    this.onShare,
    this.creatorName,
    this.showCreatorInline = false,
    this.isPublic = false,
    this.showVisibilityBadge = false,
    this.likesCount,
    this.onLikeToggle,
    this.initiallyLiked = false,
  });

  @override
  State<ThemePreview> createState() => _ThemePreviewState();
}

class _ThemePreviewState extends State<ThemePreview> {
  late bool isLiked = widget.initiallyLiked;

  bool get _isLightSurface => widget.c.background.computeLuminance() > 0.55;

  Color get _overlayForeground => _isLightSurface ? Colors.black87 : Colors.white;

  Color get _overlayBackground => _isLightSurface ? Colors.white.withValues(alpha: 0.84) : Colors.black.withValues(alpha: 0.54);

  Color get _overlayBorder => _isLightSurface ? Colors.black.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.18);

  @override
  void didUpdateWidget(covariant ThemePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme.id != widget.theme.id || oldWidget.initiallyLiked != widget.initiallyLiked) {
      isLiked = widget.initiallyLiked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final radiusLg = widget.c.style.radiusLg;
    final radiusMd = widget.c.style.radiusMd;
    final radiusSm = widget.c.style.radiusSm;
    return Card(
      color: widget.c.background,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: widget.c.background)),

          AnimatedPositioned(
            top: 10,
            left: widget.isSelected ? 34 : 10,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeIn,
            child: Row(
              children: [
                _OverlayBadge(
                  icon: widget.c.isDark ? Icons.dark_mode : Icons.light_mode,
                  label: widget.c.isDark ? 'Dark' : 'Light',
                  foreground: _overlayForeground,
                  background: _overlayBackground,
                  borderColor: _overlayBorder,
                ),
                if (widget.showVisibilityBadge) ...[
                  const SizedBox(width: 6),
                  _OverlayBadge(
                    icon: widget.isPublic ? Icons.public : Icons.lock_outline,
                    label: widget.isPublic ? 'Public' : 'Private',
                    foreground: _overlayForeground,
                    background: _overlayBackground,
                    borderColor: _overlayBorder,
                  ),
                ],
              ],
            ),
          ),

          Positioned.fill(
            top: 32,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 20,
                    decoration: BoxDecoration(color: widget.c.primary, borderRadius: BorderRadius.circular(radiusSm)),
                  ),
            
                  const SizedBox(height: 8),
            
                  Container(
                    height: 8,
                    width: 80,
                    decoration: BoxDecoration(color: widget.c.onBackground.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(radiusSm * 0.66)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 8,
                    width: 50,
                    decoration: BoxDecoration(color: widget.c.onBackground.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(radiusSm * 0.66)),
                  ),
            
                  const Spacer(),
            
                  Container(
                    height: 26,
                    decoration: BoxDecoration(color: widget.c.secondary, borderRadius: BorderRadius.circular(radiusMd)),
                    child: Center(
                      child: Text(
                        "Button",
                        style: TextStyle(color: widget.c.onSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
            
                  const SizedBox(height: 8),
            
                  Text(
                    widget.theme.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: widget.c.onBackground),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.creatorName == 'default' ? "default theme" : widget.showCreatorInline && widget.creatorName != null ? 'by ${widget.creatorName}' : '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9, color: widget.creatorName == 'you' ? Colors.greenAccent : widget.c.onBackground.withValues(alpha: 0.7)),
                        ),
                      ),
                      if (widget.likesCount != null)
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                widget.onLikeToggle?.call(widget.theme.id);
                                setState(() {
                                  isLiked = !isLiked;
                                });
                              },
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  isLiked ? Icons.favorite : Icons.favorite_border,
                                  key: ValueKey(isLiked),
                                  color: isLiked ? Colors.redAccent : Colors.grey,
                                  size: 20,
                                ),
                              ),
                            ),
                            Text('${widget.likesCount}', style: TextStyle(fontSize: 9, color: widget.c.onBackground.withValues(alpha: 0.7))),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Positioned(top: 10, left: 8, child: AnimatedOpacity(opacity: widget.isSelected ? 1 : 0, duration: const Duration(milliseconds: 400), curve: Curves.fastEaseInToSlowEaseOut, child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20))),

          if (!widget.isDefault)
            Positioned(
              top: 8,
              right: 8,
              width: 26,
              height: 26,
              child: Material(
                color: _overlayBackground,
                shape: const CircleBorder(),
                child: PopupMenuButton<String>(
                  tooltip: 'Theme options',
                  icon: Transform.translate(offset: const Offset(-7, -7), child: Icon(Icons.more_horiz, opticalSize: 14, color: _overlayForeground)),
                  color: Theme.of(context).colorScheme.surface,
                  onSelected: (val) async {
                    if (val == 'edit' && widget.openEditor != null) {
                      await widget.openEditor!(existing: widget.theme);
                      return;
                    }
                    if (val == 'share' && widget.saveTheme != null) {
                      await widget.saveTheme!(widget.theme.copyWith(isPublic: true));
                      if (context.mounted) {
                        showSnackBar(context, 'Shared with the Community!');
                      }
                      return;
                    }
                    if (val == 'copy_link') {
                      final link = '${Uri.base.origin}/themes/${widget.theme.id}';
                      await Clipboard.setData(ClipboardData(text: link));
                      if (context.mounted) showSnackBar(context, 'Link copied to clipboard');
                      return;
                    }
                    if (val == 'share_link' && widget.onShare != null) {
                      await widget.onShare!(widget.theme);
                      return;
                    }
                    if (val == 'details') {
                      _showThemeDetails(context, widget.theme, creatorName: widget.creatorName);
                      return;
                    }
                    if (val == 'delete' && widget.deleteTheme != null) {
                      await widget.deleteTheme!(widget.theme);
                    }
                  },
                  itemBuilder: (_) => [
                    if (widget.openEditor != null)
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(leading: Icon(Icons.edit), title: Text('Edit'), dense: true),
                      ),
                    if (widget.saveTheme != null && !widget.theme.isPublic)
                      const PopupMenuItem(
                        value: 'share',
                        child: ListTile(leading: Icon(Icons.public), title: Text('share with Community'), dense: true),
                      ),
                    const PopupMenuItem(
                      value: 'copy_link',
                      child: ListTile(leading: Icon(Icons.copy_outlined), title: Text('Copy link'), dense: true),
                    ),
                    const PopupMenuItem(
                      value: 'share_link',
                      child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Share'), dense: true),
                    ),
                    const PopupMenuItem(
                      value: 'details',
                      child: ListTile(leading: Icon(Icons.info_outline), title: Text('Details'), dense: true),
                    ),
                    if (widget.deleteTheme != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Delete', style: TextStyle(color: Colors.red)),
                          dense: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverlayBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final Color borderColor;

  const _OverlayBadge({required this.icon, required this.label, required this.foreground, required this.background, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    final radius = context.uiRadiusSm;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.uiSpace(8), vertical: context.uiSpace(4)),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius * 8),
        border: Border.all(color: borderColor, width: context.uiBorderWidth),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: radius, offset: const Offset(0, 1))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: foreground)),
        ],
      ),
    );
  }
}

void _showThemeDetails(BuildContext context, CustomThemeModel theme, {String? creatorName}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(theme.colors.style.radiusXl))),
    builder: (ctx) {
      final c = theme.colors;
      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(context.uiSpace(24), context.uiSpace(12), context.uiSpace(24), context.uiSpace(32)),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(theme.colors.style.radiusSm * 0.66)),
              ),
            ),
            const SizedBox(height: 16),
            Text(theme.name, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Created by: ${creatorName ?? _shortUserId(theme.createdBy)}', style: Theme.of(ctx).textTheme.bodySmall),
            Text('Visibility: ${theme.isPublic ? "Public" : "Private"}', style: Theme.of(ctx).textTheme.bodySmall),
            Text('Likes: ${theme.likesCount}', style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 20),
            Text('Palette', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DetailSwatch('Primary', c.primary),
                _DetailSwatch('Secondary', c.secondary),
                _DetailSwatch('Tertiary', c.tertiary),
                _DetailSwatch('Background', c.background),
                _DetailSwatch('Surface', c.surface),
                _DetailSwatch('Error', c.error),
              ],
            ),
          ],
        ),
      );
    },
  );
}

String _shortUserId(String? id) {
  if (id == null || id.isEmpty) return 'Unknown';
  if (id.length <= 8) return id;
  return '${id.substring(0, 6)}...';
}

class _DetailSwatch extends StatelessWidget {
  final String label;
  final Color color;

  const _DetailSwatch(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    final radius = context.uiRadiusMd;
    final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final isLight = color.computeLuminance() > 0.45;
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.black.withValues(alpha: 0.07), width: context.uiBorderWidth),
          ),
          child: Center(
            child: Text(
              hex.substring(1, 3),
              style: TextStyle(color: isLight ? Colors.black54 : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
        Text(
          hex,
          style: const TextStyle(fontSize: 9, color: Colors.grey, fontFamily: 'monospace'),
        ),
      ],
    );
  }
}

void showSnackBar(BuildContext context, String message, {Duration duration = const Duration(seconds: 1)}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: duration),
    snackBarAnimationStyle: const AnimationStyle(curve: Curves.ease, duration: Duration(milliseconds: 400)),
  );
}
