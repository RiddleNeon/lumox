import 'package:flutter/material.dart';
import 'package:lumox/base_logic.dart';
import 'package:lumox/logic/feed_recommendation/user_preference_manager.dart';
import 'package:lumox/ui/misc/dynamic_item_list.dart';
import 'package:lumox/ui/theme/theme_creation_screen.dart';

import '../../../logic/local_storage/local_seen_service.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key, this.initialCategory = SettingsCategory.account});

  final SettingsCategory initialCategory;

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  late SettingsCategory _selectedCategory = widget.initialCategory;

  late final TextEditingController _displayNameController = TextEditingController(text: currentUser.displayName);
  late final TextEditingController _usernameController = TextEditingController(text: currentUser.username);
  late final TextEditingController _bioController = TextEditingController(text: currentUser.bio);
  final TextEditingController _tagController = TextEditingController();

  bool _savingAccount = false;
  bool _workingDataAction = false;
  late bool _useYoutubeOnly;
  late List<String> _blockedTags;

  bool isProUser = false;

  @override
  void initState() {
    super.initState();
    _useYoutubeOnly = useYoutubeVideosOnlyNotifier.value;
    _blockedTags = localSeenService.getBlacklistedTags()..sort();

    userRepository.isProUser(currentUser.id).then((isPro) {
      if (mounted) setState(() => isProUser = isPro);
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _saveAccount() async {
    final displayName = _displayNameController.text.trim();
    final username = _usernameController.text.trim();
    final bio = _bioController.text.trim();

    if (displayName.isEmpty || username.isEmpty) {
      _snack('Display name and username are required.');
      return;
    }

    setState(() => _savingAccount = true);
    try {
      final changedUsername = username.toLowerCase() != currentUser.username.toLowerCase();
      if (changedUsername) {
        final available = await userRepository.isUsernameAvailable(username, excludingUserId: currentUser.id);
        if (!available) {
          _snack('That username is already taken.');
          return;
        }
      }

      final updated = currentUser.copyWith(displayName: displayName, username: username, bio: bio);
      await userRepository.upsertCurrentUserProfile(updated);
      currentUser = updated;
      _snack('Account settings saved.');
    } catch (e) {
      _snack('Failed to save account settings: $e');
    } finally {
      if (mounted) setState(() => _savingAccount = false);
    }
  }

  Future<void> _syncNow() async {
    await _runDataAction(() async {
      await localSeenService.syncWithSupabase();
      _snack('Synced local data with server.');
    });
  }

  Future<void> _resetFeedCursors() async {
    await _runDataAction(() async {
      await localSeenService.resetCursors();
      _snack('Feed cursors were reset.');
    });
  }

  Future<void> _resetRecommendationLearning() async {
    await _runDataAction(() async {
      UserPreferenceManager.reset();
      UserPreferenceManager();
      _snack('Recommendation learning cache reset.');
    });
  }

  Future<void> _runDataAction(Future<void> Function() callback) async {
    setState(() => _workingDataAction = true);
    try {
      await callback();
    } catch (e) {
      _snack('Action failed: $e');
    } finally {
      if (mounted) setState(() => _workingDataAction = false);
    }
  }

  void _toggleYoutubeOnly(bool value) async {
    final isPro = await userRepository.isProUser(currentUser.id);
    if (value && !isPro) {
      _snack('This feature is available for Pro users only.');
      return;
    }

    await userRepository.setSetting(currentUser.id, 'show_youtube', value ? 'true' : 'false');
    setState(() => _useYoutubeOnly = value);
    useYoutubeVideosOnlyNotifier.value = value;
    videoProvider.clearCache();
    _snack(value ? 'Feed switched to YouTube videos only.' : 'Feed switched to normal videos.');
  }

  Widget _buildRequestProWidget(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Pro feature', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer)),
            const SizedBox(height: 8),
            Text(
              'Showing only YouTube videos in the feed is a Pro feature. Please verify yourself to gain access to this and other Pro features.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    content: SingleChildScrollView(
                      child: _buildProVerificationWidget(context),
                    ),
                  ),
                );
              },
              child: const Text('Upgrade to Pro'),
            ),
          ],
        ),
      ),
    );
  }

  /// a screen that asks the user what the names of the group members are (as a safety question) to verify they know the owner. there is an input field list where they can put any amount of names, and if all of them are correct, they get access to the feature. if any of them are wrong, they get a message saying "verification failed, please try again" and the input fields are cleared.
  Widget _buildProVerificationWidget(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Pro verification', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer)),
            const SizedBox(height: 8),
            Text(
              'To access this feature, please verify your Pro status by answering the following question:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text(
              'What are the group members of this project?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            DynamicItemList(
              itemBuilder: (index, enteredName, [removeItem]) => Text(enteredName),
              onSubmitted: (answers) async {
                final returnValue = await userRepository.requestProPrivileges((answers..sort()).map((e) => e.toLowerCase()).join('-'));
                if (returnValue == true) {
                  _snack('Verification successful! You can now watch youtube videos.');
                  if(mounted){
                    setState(() {
                      isProUser = true;
                    });
                  }
                  if(context.mounted) Navigator.of(context).pop();
                } else {
                  _snack('Verification failed, please try again.');
                  if(context.mounted) Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addBlockedTag() async {
    final tag = _tagController.text.trim().toLowerCase();
    if (tag.isEmpty) return;
    if (_blockedTags.contains(tag)) {
      _snack('Tag already blocked.');
      return;
    }

    await localSeenService.saveBlacklistedTag(tag, DateTime.now());
    setState(() {
      _blockedTags = [..._blockedTags, tag]..sort();
      _tagController.clear();
    });
  }

  Future<void> _removeBlockedTag(String tag) async {
    await localSeenService.removeBlacklistedTag(tag);
    setState(() {
      _blockedTags = _blockedTags.where((element) => element != tag).toList();
    });
  }

  Future<void> _clearBlockedTags() async {
    await localSeenService.clearBlacklistedTags();
    setState(() => _blockedTags = []);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 940;

          return Row(
            children: [
              _SettingsSidebar(
                isWide: isWide,
                selectedCategory: _selectedCategory,
                onCategorySelected: (category) => setState(() => _selectedCategory = category),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(
                  index: _selectedCategory.index,
                  children: [
                    _buildScrollablePane(_buildAccountPane()),
                    _buildScrollablePane(_buildContentPane()),
                    const ThemeManagerScreen(embedded: true),
                    _buildScrollablePane(_buildAboutPane()),
                    _buildScrollablePane(_buildAdvancedPane()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScrollablePane(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: child),
      ),
    );
  }

  Widget _buildAccountPane() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Update profile values tied to your account.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Bio', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _savingAccount ? null : _saveAccount,
                  icon: _savingAccount
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save changes'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    _displayNameController.text = currentUser.displayName;
                    _usernameController.text = currentUser.username;
                    _bioController.text = currentUser.bio;
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('Reset fields'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentPane() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Content', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Block tags to reduce similar recommendations in your local feed session.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(labelText: 'Blocked tag', hintText: 'example: spoilers', border: OutlineInputBorder()),
                    onSubmitted: (_) => _addBlockedTag(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(onPressed: _addBlockedTag, icon: const Icon(Icons.add), label: const Text('Add')),
              ],
            ),
            const SizedBox(height: 16),
            if (_blockedTags.isEmpty)
              const Text('No blocked tags yet.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _blockedTags.map((tag) => InputChip(label: Text('#$tag'), onDeleted: () => _removeBlockedTag(tag))).toList(),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _blockedTags.isEmpty ? null : _clearBlockedTags,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear blocked tags'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedPane() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Advanced', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Feed source and maintenance actions.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (isProUser)
              SwitchListTile.adaptive(
                value: _useYoutubeOnly,
                contentPadding: EdgeInsets.zero,
                title: const Text('Show YouTube videos only'),
                subtitle: const Text('When off, the feed uses the normal video source.'),
                onChanged: _toggleYoutubeOnly,
              ),
            if (!isProUser) _buildRequestProWidget(context),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync),
              title: const Text('Sync local data now'),
              subtitle: const Text('Pull likes, dislikes, follows, and chat updates from Supabase.'),
              trailing: FilledButton(onPressed: _workingDataAction ? null : _syncNow, child: const Text('Run')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.explore_off_outlined),
              title: const Text('Reset feed cursors'),
              subtitle: const Text('Forces the feed to recalculate local pagination and recency windows.'),
              trailing: FilledButton(onPressed: _workingDataAction ? null : _resetFeedCursors, child: const Text('Reset')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.psychology_alt_outlined),
              title: const Text('Reset recommendation learning'),
              subtitle: const Text('Clears locally cached interaction learning and restarts from neutral scores.'),
              trailing: FilledButton(onPressed: _workingDataAction ? null : _resetRecommendationLearning, child: const Text('Reset')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutPane() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _kv('User ID', currentUser.id),
            _kv('Username', currentUser.username),
            _kv('Created at', currentUser.createdAt.toLocal().toString()),
            _kv('Followers', '${currentUser.followersCount}'),
            _kv('Following', '${currentUser.followingCount ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(key, style: Theme.of(context).textTheme.labelLarge)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

enum SettingsCategory {
  account(Icons.person_outline, Icons.person, 'Account'),
  content(Icons.block_outlined, Icons.block, 'Content'),
  themes(Icons.palette_outlined, Icons.palette, 'Themes'),
  about(Icons.info_outline, Icons.info, 'About'),
  advanced(Icons.tune_outlined, Icons.tune, 'Advanced');

  const SettingsCategory(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({required this.isWide, required this.selectedCategory, required this.onCategorySelected});

  final bool isWide;
  final SettingsCategory selectedCategory;
  final ValueChanged<SettingsCategory> onCategorySelected;

  static const List<SettingsCategory> _mainCategories = [SettingsCategory.account, SettingsCategory.content, SettingsCategory.themes, SettingsCategory.about];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = isWide ? 220.0 : 72.0;

    return SizedBox(
      width: width,
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final category in _mainCategories)
            _SidebarItem(isWide: isWide, category: category, selected: selectedCategory == category, onTap: () => onCategorySelected(category)),
          const Spacer(),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          _SidebarItem(
            isWide: isWide,
            category: SettingsCategory.advanced,
            selected: selectedCategory == SettingsCategory.advanced,
            onTap: () => onCategorySelected(SettingsCategory.advanced),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.isWide, required this.category, required this.selected, required this.onTap});

  final bool isWide;
  final SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: isWide ? 12 : 0, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? cs.secondaryContainer.withValues(alpha: 0.7) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: selected ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)) : null,
          ),
          child: Row(
            mainAxisAlignment: isWide ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(selected ? category.selectedIcon : category.icon, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
              if (isWide) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(category.label, style: textStyle?.copyWith(color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
