import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lumox/base_logic.dart';
import 'package:lumox/logic/repositories/video_repository.dart';
import 'package:lumox/logic/themes/theme_model.dart';
import 'package:lumox/logic/users/user_model.dart';
import 'package:lumox/logic/video/video.dart';
import 'package:lumox/ui/router/deep_link_builder.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';
import 'package:lumox/ui/widgets/camera/camera_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ChatAttachmentAction { fileImage, urlImage, cameraImage, deepLink }

typedef ChatImageUpload =
    Future<String> Function(Uint8List bytes, {String? filename});

Future<ChatAttachmentAction?> showChatAttachmentActionSheet(
  BuildContext context,
) {
  return showModalBottomSheet<ChatAttachmentAction>(
    context: context,
    useSafeArea: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Add image from file'),
              onTap: () =>
                  Navigator.of(ctx).pop(ChatAttachmentAction.fileImage),
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Add image via URL'),
              onTap: () => Navigator.of(ctx).pop(ChatAttachmentAction.urlImage),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Add image from camera'),
              onTap: () =>
                  Navigator.of(ctx).pop(ChatAttachmentAction.cameraImage),
            ),
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: const Text('Send Lumox Action'),
              onTap: () => Navigator.of(ctx).pop(ChatAttachmentAction.deepLink),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<String?> showChatFileImageUploadSheet(
  BuildContext context, {
  required ChatImageUpload uploadImage,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ImageUploadSheet(
      title: 'Upload from File',
      actionLabel: 'choose File',
      icon: Icons.upload_file_outlined,
      uploadImage: uploadImage,
      pickMode: _ImagePickMode.file,
    ),
  );
}

Future<String?> showChatCameraImageUploadSheet(
  BuildContext context, {
  required ChatImageUpload uploadImage,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ImageUploadSheet(
      title: 'Camera-Upload',
      actionLabel: kIsWeb ? 'capture photo' : 'choose from your gallery',
      icon: Icons.camera_alt_outlined,
      uploadImage: uploadImage,
      pickMode: _ImagePickMode.camera,
    ),
  );
}

Future<String?> showChatUrlImageUploadSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _UrlImageSheet(),
  );
}

Future<String?> showChatDeepLinkBuilderSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _DeepLinkBuilderSheet(),
  );
}

enum _ImagePickMode { file, camera }

class _ImageUploadSheet extends StatefulWidget {
  const _ImageUploadSheet({
    required this.title,
    required this.actionLabel,
    required this.icon,
    required this.uploadImage,
    required this.pickMode,
  });

  final String title;
  final String actionLabel;
  final IconData icon;
  final ChatImageUpload uploadImage;
  final _ImagePickMode pickMode;

  @override
  State<_ImageUploadSheet> createState() => _ImageUploadSheetState();
}

class _ImageUploadSheetState extends State<_ImageUploadSheet> {
  Uint8List? _pickedBytes;
  bool _uploading = false;

  Future<void> _pickImage() async {
    if (widget.pickMode == _ImagePickMode.camera && kIsWeb) {
      final bytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const WebCameraDialog(preferFrontCamera: false),
      );
      if (!mounted || bytes == null) return;
      setState(() => _pickedBytes = bytes);
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final bytes = result?.files.first.bytes;
    if (bytes != null && mounted) {
      setState(() => _pickedBytes = bytes);
    }
  }

  Future<void> _confirmUpload() async {
    if (_pickedBytes == null || _uploading) return;
    setState(() => _uploading = true);
    try {
      final url = await widget.uploadImage(
        _pickedBytes!,
        filename: 'chat_image.jpg',
      );
      if (!mounted) return;
      Navigator.of(context).pop(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload Failed: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(context.uiRadiusMd),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: _pickedBytes == null
                      ? Icon(widget.icon, size: 48, color: cs.onSurfaceVariant)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(
                            context.uiRadiusMd,
                          ),
                          child: Image.memory(_pickedBytes!, fit: BoxFit.cover),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pickImage,
                icon: Icon(widget.icon),
                label: Text(widget.actionLabel),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (_pickedBytes == null || _uploading)
                    ? null
                    : _confirmUpload,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _uploading ? 'Uploading Image...' : 'Send!',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrlImageSheet extends StatefulWidget {
  const _UrlImageSheet();

  @override
  State<_UrlImageSheet> createState() => _UrlImageSheetState();
}

class _UrlImageSheetState extends State<_UrlImageSheet> {
  final TextEditingController _controller = TextEditingController();
  String _url = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (!mounted) return;
      setState(() => _url = _controller.text.trim());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isValidImageUrl {
    final uri = Uri.tryParse(_url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp') ||
        path.endsWith('.bmp') ||
        path.endsWith('.svg') ||
        uri.host.contains('cloudinary.com');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Append Image-URL',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(hintText: 'https://...'),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(context.uiRadiusMd),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: _isValidImageUrl
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(context.uiRadiusMd),
                        child: CachedNetworkImage(
                          imageUrl: _url,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          placeholder: (_, _) => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          'Enter a valid image url (ending with .png, .jpg, .jpeg, .gif, .webp, .bmp, .svg or from cloudinary)',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isValidImageUrl
                    ? () => Navigator.of(context).pop(_url)
                    : null,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send as Image URL'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DeepLinkType { feed, profile, chat, themes, search, quests }

class _DeepLinkBuilderSheet extends StatefulWidget {
  const _DeepLinkBuilderSheet();

  @override
  State<_DeepLinkBuilderSheet> createState() => _DeepLinkBuilderSheetState();
}

class _DeepLinkBuilderSheetState extends State<_DeepLinkBuilderSheet> {
  _DeepLinkType _type = _DeepLinkType.feed;
  Video? _selectedVideo;
  UserProfile? _selectedProfile;
  CustomThemeModel? _selectedTheme;
  DeepLinkProfileTab _profileTab = DeepLinkProfileTab.videos;
  DeepLinkThemeTab _themeTab = DeepLinkThemeTab.community;
  DeepLinkSearchScope _searchScope = DeepLinkSearchScope.all;
  DeepLinkSearchMode _searchMode = DeepLinkSearchMode.text;
  final TextEditingController _searchQueryController = TextEditingController();
  final TextEditingController _questSubjectController = TextEditingController();

  @override
  void dispose() {
    _searchQueryController.dispose();
    _questSubjectController.dispose();
    super.dispose();
  }

  String _buildCurrentRoute() {
    switch (_type) {
      case _DeepLinkType.feed:
        return DeepLinkBuilder.feed(videoId: _selectedVideo?.id);
      case _DeepLinkType.profile:
        final profile = _selectedProfile;
        if (profile == null) return '/u';
        return DeepLinkBuilder.profile(profile.id, tab: _profileTab);
      case _DeepLinkType.chat:
        return DeepLinkBuilder.chat(partnerId: _selectedProfile?.id);
      case _DeepLinkType.themes:
        return _selectedTheme != null
            ? DeepLinkBuilder.themes(themeId: _selectedTheme!.id)
            : DeepLinkBuilder.themes(tab: _themeTab);
      case _DeepLinkType.search:
        final hasQuery = _searchQueryController.text.trim().isNotEmpty;
        return DeepLinkBuilder.search(
          query: _searchQueryController.text.trim(),
          scope: hasQuery ? _searchScope : DeepLinkSearchScope.all,
          mode: hasQuery ? _searchMode : DeepLinkSearchMode.text,
        );
      case _DeepLinkType.quests:
        return DeepLinkBuilder.quests(
          subject: _questSubjectController.text.trim(),
        );
    }
  }

  Future<void> _pickVideo() async {
    final selected = await showModalBottomSheet<Video>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _VideoPickerSheet(),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedVideo = selected);
  }

  Future<void> _pickProfile() async {
    final selected = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ProfilePickerSheet(),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedProfile = selected);
  }

  Future<void> _pickTheme() async {
    final selected = await showModalBottomSheet<CustomThemeModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ThemePickerSheet(initialTab: _themeTab),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedTheme = selected);
  }

  bool _canSubmit() {
    return switch (_type) {
      _DeepLinkType.feed => _selectedVideo != null,
      _DeepLinkType.profile => _selectedProfile != null,
      _DeepLinkType.chat => _selectedProfile != null,
      _DeepLinkType.themes => true,
      _DeepLinkType.search => true,
      _DeepLinkType.quests => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deep-Link Builder',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<_DeepLinkType>(
                key: ValueKey(_type),
                initialValue: _type,
                items: const [
                  DropdownMenuItem(
                    value: _DeepLinkType.feed,
                    child: Text('video'),
                  ),
                  DropdownMenuItem(
                    value: _DeepLinkType.profile,
                    child: Text('profile'),
                  ),
                  DropdownMenuItem(
                    value: _DeepLinkType.chat,
                    child: Text('chat with user'),
                  ),
                  DropdownMenuItem(
                    value: _DeepLinkType.themes,
                    child: Text('theme'),
                  ),
                  DropdownMenuItem(
                    value: _DeepLinkType.search,
                    child: Text('search'),
                  ),
                  DropdownMenuItem(
                    value: _DeepLinkType.quests,
                    child: Text('quests'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _type = value);
                },
              ),
              const SizedBox(height: 14),
              _buildTypeOptions(),
              const SizedBox(height: 12),
              SelectableText(
                _buildCurrentRoute(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _canSubmit()
                    ? () => Navigator.of(context).pop(_buildCurrentRoute())
                    : null,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send Link to Action'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeOptions() {
    switch (_type) {
      case _DeepLinkType.feed:
        return _SelectionButton(
          icon: Icons.play_circle_outline,
          label: _selectedVideo == null
              ? 'select video'
              : '${_selectedVideo!.title} • ${_selectedVideo!.authorName}',
          onTap: _pickVideo,
        );
      case _DeepLinkType.profile:
        return Column(
          children: [
            _SelectionButton(
              icon: Icons.person_outline,
              label: _selectedProfile == null
                  ? 'Select profile'
                  : '${_selectedProfile!.displayName} (@${_selectedProfile!.username})',
              onTap: _pickProfile,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<DeepLinkProfileTab>(
              key: ValueKey(_profileTab),
              initialValue: _profileTab,
              items: const [
                DropdownMenuItem(
                  value: DeepLinkProfileTab.videos,
                  child: Text('tab: videos'),
                ),
                DropdownMenuItem(
                  value: DeepLinkProfileTab.followers,
                  child: Text('tab: follower'),
                ),
                DropdownMenuItem(
                  value: DeepLinkProfileTab.following,
                  child: Text('tab: following'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _profileTab = value);
              },
            ),
          ],
        );
      case _DeepLinkType.chat:
        return _SelectionButton(
          icon: Icons.chat_bubble_outline,
          label: _selectedProfile == null
              ? 'select chat partner'
              : '${_selectedProfile!.displayName} (@${_selectedProfile!.username})',
          onTap: _pickProfile,
        );
      case _DeepLinkType.themes:
        final canChangeThemeTab = _selectedTheme == null;
        return Column(
          children: [
            _SelectionButton(
              icon: Icons.palette_outlined,
              label: _selectedTheme == null
                  ? 'select theme (optional)'
                  : _selectedTheme!.name,
              onTap: _pickTheme,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<DeepLinkThemeTab>(
              key: ValueKey(_themeTab),
              initialValue: _themeTab,
              onTap: canChangeThemeTab ? null : () {},
              items: const [
                DropdownMenuItem(
                  value: DeepLinkThemeTab.community,
                  child: Text('Tab: community'),
                ),
                DropdownMenuItem(
                  value: DeepLinkThemeTab.own,
                  child: Text('Tab: Own'),
                ),
              ],
              onChanged: canChangeThemeTab
                  ? (value) {
                      if (value == null) return;
                      setState(() => _themeTab = value);
                    }
                  : null,
            ),
            if (!canChangeThemeTab)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Tab selection is disabled while a specific theme is selected.',
                ),
              ),
            if (!canChangeThemeTab)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _selectedTheme = null),
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Use tab link instead'),
                ),
              ),
          ],
        );
      case _DeepLinkType.search:
        final hasQuery = _searchQueryController.text.trim().isNotEmpty;
        final canUseTagMode =
            hasQuery && _searchScope == DeepLinkSearchScope.videos;
        return Column(
          children: [
            TextField(
              controller: _searchQueryController,
              onChanged: (_) => setState(() {
                if (_searchScope != DeepLinkSearchScope.videos) {
                  _searchMode = DeepLinkSearchMode.text;
                }
              }),
              decoration: const InputDecoration(
                hintText: 'search text (optional)',
              ),
            ),
            if (hasQuery) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<DeepLinkSearchScope>(
                key: ValueKey(_searchScope),
                initialValue: _searchScope,
                items: const [
                  DropdownMenuItem(
                    value: DeepLinkSearchScope.all,
                    child: Text('Scope: all'),
                  ),
                  DropdownMenuItem(
                    value: DeepLinkSearchScope.videos,
                    child: Text('Scope: videos'),
                  ),
                  DropdownMenuItem(
                    value: DeepLinkSearchScope.profiles,
                    child: Text('Scope: profile'),
                  ),
                  DropdownMenuItem(
                    value: DeepLinkSearchScope.dictionary,
                    child: Text('Scope: dictionary'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _searchScope = value;
                    if (_searchScope != DeepLinkSearchScope.videos) {
                      _searchMode = DeepLinkSearchMode.text;
                    }
                  });
                },
              ),
            ],
            if (canUseTagMode) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<DeepLinkSearchMode>(
                key: ValueKey(_searchMode),
                initialValue: _searchMode,
                items: const [
                  DropdownMenuItem(
                    value: DeepLinkSearchMode.text,
                    child: Text('Mode: text'),
                  ),
                  DropdownMenuItem(
                    value: DeepLinkSearchMode.tags,
                    child: Text('Mode: tags'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _searchMode = value);
                },
              ),
            ],
          ],
        );
      case _DeepLinkType.quests:
        return TextField(
          controller: _questSubjectController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Subject (optional, e.g. Math)',
            prefixIcon: Icon(Icons.subject_outlined),
          ),
        );
    }
  }
}

class _SelectionButton extends StatelessWidget {
  const _SelectionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _VideoPickerSheet extends StatefulWidget {
  const _VideoPickerSheet();

  @override
  State<_VideoPickerSheet> createState() => _VideoPickerSheetState();
}

class _VideoPickerSheetState extends State<_VideoPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Video> _items = const [];
  bool _loading = true;
  Timer? _searchDebounce;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), _load);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onQueryChanged)
      ..dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final query = _searchController.text.trim();
    final requestId = ++_requestId;
    setState(() => _loading = true);
    try {
      final results = query.isEmpty
          ? await videoRepo.getTrendingVideos(limit: 30)
          : (await videoRepo.searchVideos(
              query,
              limit: 30,
              withAuthor: true,
              showYoutube: useYoutubeVideosOnlyNotifier.value,
            )).videos;
      if (!mounted || requestId != _requestId) return;
      setState(() => _items = results);
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PickerScaffold(
      title: 'select video',
      controller: _searchController,
      hint: 'search videos',
      loading: _loading,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final video = _items[index];
        return ListTile(
          leading: video.thumbnailUrl?.isNotEmpty == true
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: video.thumbnailUrl!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const SizedBox(width: 56, height: 56),
                  ),
                )
              : const Icon(Icons.play_circle_outline),
          title: Text(
            video.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            video.authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(video),
        );
      },
    );
  }
}

class _ProfilePickerSheet extends StatefulWidget {
  const _ProfilePickerSheet();

  @override
  State<_ProfilePickerSheet> createState() => _ProfilePickerSheetState();
}

class _ProfilePickerSheetState extends State<_ProfilePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<UserProfile> _items = const [];
  bool _loading = true;
  Timer? _searchDebounce;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), _load);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onQueryChanged)
      ..dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final query = _searchController.text.trim();
    final requestId = ++_requestId;
    setState(() => _loading = true);
    try {
      final results = (await userRepository.searchUsers(
        query,
        limit: 50,
      )).users;
      if (!mounted || requestId != _requestId) return;
      setState(() => _items = results);
    } catch (_) {
      if (query.isEmpty) {
        final fallback = await userRepository.getFollowing(
          currentUser.id,
          limit: 50,
        );
        if (!mounted || requestId != _requestId) return;
        setState(() => _items = fallback);
      }
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PickerScaffold(
      title: 'select profile',
      controller: _searchController,
      hint: 'search profiles',
      loading: _loading,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final profile = _items[index];
        return ListTile(
          leading: CircleAvatar(
            foregroundImage: profile.profileImageUrl.isNotEmpty
                ? NetworkImage(profile.profileImageUrl)
                : null,
            child: profile.displayName.isNotEmpty
                ? Text(profile.displayName[0].toUpperCase())
                : const Text('?'),
          ),
          title: Text(
            profile.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '@${profile.username}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(profile),
        );
      },
    );
  }
}

class _ThemePickerSheet extends StatefulWidget {
  const _ThemePickerSheet({required this.initialTab});

  final DeepLinkThemeTab initialTab;

  @override
  State<_ThemePickerSheet> createState() => _ThemePickerSheetState();
}

class _ThemePickerSheetState extends State<_ThemePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;
  List<CustomThemeModel> _items = const [];
  bool _loading = true;
  Timer? _searchDebounce;
  int _requestId = 0;
  late DeepLinkThemeTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _load();
    _searchController.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), _load);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onQueryChanged)
      ..dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final query = _searchController.text.trim();
    final requestId = ++_requestId;
    setState(() => _loading = true);
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (_tab == DeepLinkThemeTab.own) {
        if (uid == null) {
          if (!mounted || requestId != _requestId) return;
          setState(() => _items = const []);
          return;
        }
        var ownQuery = _supabase.from('themes').select().eq('created_by', uid);
        if (query.isNotEmpty) {
          ownQuery = ownQuery.ilike('name', '%$query%');
        }
        final ownRows = await ownQuery
            .order('created_at', ascending: false)
            .limit(60);
        if (!mounted || requestId != _requestId) return;
        setState(
          () => _items = List<Map<String, dynamic>>.from(
            ownRows,
          ).map(CustomThemeModel.fromJson).toList(),
        );
      } else {
        var publicQuery = _supabase
            .from('themes')
            .select()
            .eq('is_public', true);
        if (query.isNotEmpty) {
          publicQuery = publicQuery.ilike('name', '%$query%');
        }
        final publicRows = await publicQuery
            .order('likes_count', ascending: false)
            .limit(60);
        if (!mounted || requestId != _requestId) return;
        setState(
          () => _items = List<Map<String, dynamic>>.from(
            publicRows,
          ).map(CustomThemeModel.fromJson).toList(),
        );
      }
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _supabase.auth.currentUser?.id;
    return _PickerScaffold(
      title: 'select theme',
      controller: _searchController,
      hint: 'search themes',
      prefix: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SegmentedButton<DeepLinkThemeTab>(
          segments: const [
            ButtonSegment(
              value: DeepLinkThemeTab.community,
              label: Text('Community'),
              icon: Icon(Icons.public_outlined),
            ),
            ButtonSegment(
              value: DeepLinkThemeTab.own,
              label: Text('Own'),
              icon: Icon(Icons.person_outline),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (selected) {
            final next = selected.first;
            if (next == _tab) return;
            setState(() => _tab = next);
            _load();
          },
        ),
      ),
      loading: _loading,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final theme = _items[index];
        final isOwn = uid != null && theme.createdBy == uid;
        return ListTile(
          leading: CircleAvatar(backgroundColor: theme.colors.primary),
          title: Text(theme.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            isOwn
                ? 'Own Theme'
                : (theme.isPublic ? 'Community Theme' : 'Private Theme'),
          ),
          onTap: () => Navigator.of(context).pop(theme),
        );
      },
    );
  }
}

class _PickerScaffold extends StatelessWidget {
  const _PickerScaffold({
    required this.title,
    required this.controller,
    required this.hint,
    this.prefix,
    required this.loading,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String title;
  final TextEditingController controller;
  final String hint;
  final Widget? prefix;
  final bool loading;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: hint,
                ),
              ),
            ),
            ?prefix,
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : itemCount == 0
                  ? const Center(child: Text('No results'))
                  : ListView.builder(
                      itemCount: itemCount,
                      itemBuilder: itemBuilder,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
