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

Future<T?> _showAttachmentSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: cs.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(context.uiRadiusLg),
      ),
      side: BorderSide(color: cs.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    builder: builder,
  );
}

Future<ChatAttachmentAction?> showChatAttachmentActionSheet(
  BuildContext context,
) {
  return _showAttachmentSheet<ChatAttachmentAction>(
    context,
    builder: (ctx) => _AttachmentSheetShell(
      icon: Icons.attachment_outlined,
      title: 'Add to chat',
      subtitle: 'Pick a clean inline attachment that fits the conversation.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentOptionCard(
            icon: Icons.upload_file_outlined,
            title: 'Add image from file',
            subtitle: 'Choose from your device storage.',
            onTap: () => Navigator.of(ctx).pop(ChatAttachmentAction.fileImage),
          ),
          const SizedBox(height: 10),
          _AttachmentOptionCard(
            icon: Icons.link_outlined,
            title: 'Add image via URL',
            subtitle: 'Paste a direct image or Cloudinary link.',
            onTap: () => Navigator.of(ctx).pop(ChatAttachmentAction.urlImage),
          ),
          const SizedBox(height: 10),
          _AttachmentOptionCard(
            icon: Icons.camera_alt_outlined,
            title: 'Add image from camera',
            subtitle: 'Capture something on the fly.',
            onTap: () =>
                Navigator.of(ctx).pop(ChatAttachmentAction.cameraImage),
          ),
          const SizedBox(height: 10),
          _AttachmentOptionCard(
            icon: Icons.route_outlined,
            title: 'Send Lumox Action',
            subtitle: 'Build a deep link for an in-app action.',
            onTap: () => Navigator.of(ctx).pop(ChatAttachmentAction.deepLink),
          ),
        ],
      ),
    ),
  );
}

Future<String?> showChatFileImageUploadSheet(
  BuildContext context, {
  required ChatImageUpload uploadImage,
}) {
  return _showAttachmentSheet<String>(
    context,
    builder: (_) => _ImageUploadSheet(
      title: 'Upload from File',
      actionLabel: 'Choose File',
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
  return _showAttachmentSheet<String>(
    context,
    builder: (_) => _ImageUploadSheet(
      title: 'Camera Upload',
      actionLabel: kIsWeb ? 'Capture Photo' : 'Choose from Gallery',
      icon: Icons.camera_alt_outlined,
      uploadImage: uploadImage,
      pickMode: _ImagePickMode.camera,
    ),
  );
}

Future<String?> showChatUrlImageUploadSheet(BuildContext context) {
  return _showAttachmentSheet<String>(
    context,
    builder: (_) => const _UrlImageSheet(),
  );
}

Future<String?> showChatDeepLinkBuilderSheet(BuildContext context) {
  return _showAttachmentSheet<String>(
    context,
    builder: (_) => const _DeepLinkBuilderSheet(),
  );
}

class _AttachmentSheetShell extends StatelessWidget {
  const _AttachmentSheetShell({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.onBack,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(context.uiRadiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(context.uiRadiusLg),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(context.uiRadiusMd),
                            ),
                            child: Icon(icon, color: cs.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle!,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (onBack != null)
                            IconButton.filledTonal(
                              onPressed: onBack,
                              icon: const Icon(Icons.arrow_back_rounded),
                              tooltip: 'Back',
                            )
                          else
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Close',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                color: cs.surfaceContainerLow,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentOptionCard extends StatelessWidget {
  const _AttachmentOptionCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(context.uiRadiusMd),
                ),
                child: Icon(icon, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.arrow_forward_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _attachmentInputDecoration(
  BuildContext context, {
  required String hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final cs = Theme.of(context).colorScheme;
  final radius = BorderRadius.circular(context.uiRadiusMd);
  return InputDecoration(
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: cs.surfaceContainerHighest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: cs.primary, width: 1.5),
    ),
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
    return _AttachmentSheetShell(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.pickMode == _ImagePickMode.camera
          ? 'Capture or choose a photo, preview it, and send it.'
          : 'Choose an image, preview it, and send it into chat.',
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Preview',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(context.uiRadiusMd),
            ),
            child: _pickedBytes == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius:
                                BorderRadius.circular(context.uiRadiusLg),
                          ),
                          child: Icon(widget.icon, size: 34, color: cs.primary),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No image selected yet',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(context.uiRadiusMd),
                    child: Image.memory(_pickedBytes!, fit: BoxFit.cover),
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
            onPressed: (_pickedBytes == null || _uploading) ? null : _confirmUpload,
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_uploading ? 'Uploading Image...' : 'Send Image'),
          ),
        ],
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
    return _AttachmentSheetShell(
      icon: Icons.link_outlined,
      title: 'Append Image URL',
      subtitle: 'Paste a direct image link, check the preview, then send it.',
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            decoration: _attachmentInputDecoration(
              context,
              hintText: 'https://...',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: _isValidImageUrl
                  ? Icon(Icons.check_circle_rounded, color: cs.primary)
                  : Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _isValidImageUrl
                  ? 'Looks like a direct image link.'
                  : 'Use a URL that ends in .png, .jpg, .jpeg, .gif, .webp, .bmp, .svg, or a Cloudinary host.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Live preview',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(context.uiRadiusMd),
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
                      placeholder: (_, _) => Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Paste a direct image URL to see the preview here.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isValidImageUrl ? () => Navigator.of(context).pop(_url) : null,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send as Image URL'),
          ),
        ],
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
    final selected = await _showAttachmentSheet<Video>(
      context,
      builder: (_) => const _VideoPickerSheet(),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedVideo = selected);
  }

  Future<void> _pickProfile() async {
    final selected = await _showAttachmentSheet<UserProfile>(
      context,
      builder: (_) => const _ProfilePickerSheet(),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedProfile = selected);
  }

  Future<void> _pickTheme() async {
    final selected = await _showAttachmentSheet<CustomThemeModel>(
      context,
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
    final cs = Theme.of(context).colorScheme;
    return _AttachmentSheetShell(
      icon: Icons.route_outlined,
      title: 'Deep-Link Builder',
      subtitle: 'Shape a route, preview it live, and send it inline.',
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Link type',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<_DeepLinkType>(
            key: ValueKey(_type),
            initialValue: _type,
            decoration: _attachmentInputDecoration(
              context,
              hintText: 'Choose a link target',
              prefixIcon: const Icon(Icons.route_rounded),
            ),
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: _DeepLinkType.feed, child: Text('Video feed')),
              DropdownMenuItem(value: _DeepLinkType.profile, child: Text('Profile')),
              DropdownMenuItem(value: _DeepLinkType.chat, child: Text('Chat with user')),
              DropdownMenuItem(value: _DeepLinkType.themes, child: Text('Theme')),
              DropdownMenuItem(value: _DeepLinkType.search, child: Text('Search')),
              DropdownMenuItem(value: _DeepLinkType.quests, child: Text('Quests')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _type = value);
            },
          ),
          const SizedBox(height: 14),
          _buildTypeOptions(),
          const SizedBox(height: 16),
          Text(
            'Route preview',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(context.uiRadiusMd),
            ),
            child: SelectableText(
              _buildCurrentRoute(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                  ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _canSubmit() ? () => Navigator.of(context).pop(_buildCurrentRoute()) : null,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send Link to Action'),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeOptions() {
    final cs = Theme.of(context).colorScheme;
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
              decoration: _attachmentInputDecoration(
                context,
                hintText: 'Choose a profile tab',
                prefixIcon: const Icon(Icons.view_agenda_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: DeepLinkProfileTab.videos,
                  child: Text('Videos'),
                ),
                DropdownMenuItem(
                  value: DeepLinkProfileTab.followers,
                  child: Text('Followers'),
                ),
                DropdownMenuItem(
                  value: DeepLinkProfileTab.following,
                  child: Text('Following'),
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
              decoration: _attachmentInputDecoration(
                context,
                hintText: canChangeThemeTab ? 'Choose a theme tab' : 'Theme selected',
                prefixIcon: const Icon(Icons.category_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: DeepLinkThemeTab.community,
                  child: Text('Community'),
                ),
                DropdownMenuItem(
                  value: DeepLinkThemeTab.own,
                  child: Text('Own'),
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
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tab selection is disabled while a specific theme is selected.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
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
              decoration: _attachmentInputDecoration(
                context,
                hintText: 'Search text (optional)',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            if (hasQuery) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<DeepLinkSearchScope>(
                key: ValueKey(_searchScope),
                initialValue: _searchScope,
                decoration: _attachmentInputDecoration(
                  context,
                  hintText: 'Choose scope',
                  prefixIcon: const Icon(Icons.filter_alt_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: DeepLinkSearchScope.all,
                    child: Text('All'),
                  ),
                  DropdownMenuItem(
                    value: DeepLinkSearchScope.videos,
                    child: Text('Videos'),
                  ),
                  DropdownMenuItem(
                    value: DeepLinkSearchScope.profiles,
                    child: Text('Profiles'),
                  ),
                  DropdownMenuItem(
                    value: DeepLinkSearchScope.dictionary,
                    child: Text('Dictionary'),
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
                decoration: _attachmentInputDecoration(
                  context,
                  hintText: 'Choose mode',
                  prefixIcon: const Icon(Icons.tag_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: DeepLinkSearchMode.text,
                    child: Text('Text'),
                  ),
                  DropdownMenuItem(
                    value: DeepLinkSearchMode.tags,
                    child: Text('Tags'),
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
          decoration: _attachmentInputDecoration(
            context,
            hintText: 'Subject (optional, e.g. Math)',
            prefixIcon: const Icon(Icons.subject_outlined),
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
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(context.uiRadiusMd),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
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
      icon: Icons.play_circle_outline,
      title: 'select video',
      controller: _searchController,
      hint: 'search videos',
      loading: _loading,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final video = _items[index];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.uiRadiusMd),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: video.thumbnailUrl?.isNotEmpty == true
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: video.thumbnailUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox(width: 56, height: 56),
                      ),
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Icon(Icons.play_circle_outline, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
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
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: () => Navigator.of(context).pop(video),
            ),
          ),
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
      icon: Icons.person_outline,
      title: 'select profile',
      controller: _searchController,
      hint: 'search profiles',
      loading: _loading,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final profile = _items[index];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.uiRadiusMd),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(
                foregroundImage: profile.profileImageUrl.isNotEmpty
                    ? NetworkImage(profile.profileImageUrl)
                    : null,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
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
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: () => Navigator.of(context).pop(profile),
            ),
          ),
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
      icon: Icons.palette_outlined,
      title: 'select theme',
      controller: _searchController,
      hint: 'search themes',
      prefix: SegmentedButton<DeepLinkThemeTab>(
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
      loading: _loading,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final theme = _items[index];
        final isOwn = uid != null && theme.createdBy == uid;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.uiRadiusMd),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(
                backgroundColor: theme.colors.primary,
                child: Icon(Icons.palette_outlined, color: theme.colors.onPrimary),
              ),
              title: Text(theme.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                isOwn
                    ? 'Own Theme'
                    : (theme.isPublic ? 'Community Theme' : 'Private Theme'),
              ),
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: () => Navigator.of(context).pop(theme),
            ),
          ),
        );
      },
    );
  }
}

class _PickerScaffold extends StatelessWidget {
  const _PickerScaffold({
    required this.icon,
    required this.title,
    required this.controller,
    required this.hint,
    this.prefix,
    required this.loading,
    required this.itemCount,
    required this.itemBuilder,
  });

  final IconData icon;
  final String title;
  final TextEditingController controller;
  final String hint;
  final Widget? prefix;
  final bool loading;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return _AttachmentSheetShell(
      icon: icon,
      title: title,
      subtitle: 'Search, filter, and select without leaving the chat flow.',
      onBack: () => Navigator.of(context).pop(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              decoration: _attachmentInputDecoration(
                context,
                hintText: hint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            if (prefix != null) ...[
              const SizedBox(height: 12),
              prefix!,
            ],
            const SizedBox(height: 12),
            Expanded(
              child: loading
                  ? Center(
                      child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    )
                  : itemCount == 0
                      ? Center(
                          child: Text(
                            'No results',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 2),
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
