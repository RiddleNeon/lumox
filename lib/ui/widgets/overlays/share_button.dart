import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme_ui_values.dart';

/// Lightweight share target used by [ShareButton].
class ShareContact {
  final String id;
  final String name;
  final String? avatarUrl;
  final int recentShareCount;
  final DateTime? lastSharedAt;
  final bool alreadySharedWithThisVideo;
  final DateTime? lastSharedThisVideoAt;

  const ShareContact({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.recentShareCount = 0,
    this.lastSharedAt,
    this.alreadySharedWithThisVideo = false,
    this.lastSharedThisVideoAt,
  });
}

/// A button that expands inline and lets users copy a link or share to a contact.
class ShareButton extends StatefulWidget {
  final String shareUrl;

  final Future<Set<ShareContact>> Function() loadContacts;

  final Future<void> Function(String link)? onCopyLink;
  final Future<void> Function(ShareContact contact, String link)? onShareToContact;
  final VoidCallback? onShared;
  final ValueChanged<bool>? onExpandedChanged;
  final String emptyStateLabel;

  const ShareButton({
    super.key,
    required this.shareUrl,
    required this.loadContacts,
    this.onCopyLink,
    this.onShareToContact,
    this.onShared,
    this.onExpandedChanged,
    this.emptyStateLabel = 'No recent chats',
  });

  @override
  State<ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<ShareButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _menuSize;
  late final Animation<double> _menuFade;
  late final Animation<Offset> _menuSlide;
  late final Animation<double> _iconTurn;

  bool _expanded = false;
  bool _copying = false;
  bool _loadingContacts = false;

  String? _sendingContactId;

  Set<ShareContact>? _contacts;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), reverseDuration: const Duration(milliseconds: 170));

    _menuSize = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

    _menuFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 1, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );

    _menuSlide = Tween<Offset>(
      begin: const Offset(0, 0.07),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic));

    _iconTurn = Tween<double>(begin: 0, end: 0.125).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ensureContactsLoaded() async {
    if (_contacts != null || _loadingContacts) return;

    setState(() => _loadingContacts = true);

    try {
      final contacts = await widget.loadContacts();

      if (!mounted) return;

      setState(() {
        _contacts = contacts;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingContacts = false);
      }
    }
  }

  Future<void> reloadContacts() async {
    setState(() {
      _contacts = null;
    });

    await _ensureContactsLoaded();
  }

  List<ShareContact> get _sortedContacts {
    final sorted = List<ShareContact>.of(_contacts ?? []);

    sorted.sort((a, b) {
      final byCount = b.recentShareCount.compareTo(a.recentShareCount);
      if (byCount != 0) return byCount;

      final aTime = a.lastSharedAt;
      final bTime = b.lastSharedAt;

      if (aTime == null && bTime == null) {
        return a.name.compareTo(b.name);
      }

      if (aTime == null) return 1;
      if (bTime == null) return -1;

      final byTime = bTime.compareTo(aTime);
      if (byTime != 0) return byTime;
      return a.name.compareTo(b.name);
    });

    return sorted;
  }

  Future<void> _toggleExpanded() async {
    if (_copying || _sendingContactId != null) return;
    final next = !_expanded;
    if (next) {
      await _ensureContactsLoaded();
    }
    setState(() => _expanded = next);
    widget.onExpandedChanged?.call(next);
    if (next) {
      await _controller.forward();
    } else {
      await _controller.reverse();
    }
  }

  Future<void> _collapseIfExpanded() async {
    if (!_expanded) return;
    await _toggleExpanded();
  }

  Future<void> _copyLink() async {
    if (_copying || _sendingContactId != null) return;
    setState(() => _copying = true);
    try {
      final link = Uri.base.origin + widget.shareUrl;

      if (widget.onCopyLink != null) {
        await widget.onCopyLink!(link);
      } else {
        await Clipboard.setData(ClipboardData(text: link));
      }
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
      widget.onShared?.call();
      if (_expanded) {
        await _toggleExpanded();
      }
    } finally {
      if (mounted) {
        setState(() => _copying = false);
      }
    }
  }

  Future<void> _shareToContact(ShareContact contact) async {
    if (_copying || _sendingContactId != null) return;
    setState(() => _sendingContactId = contact.id);
    try {
      if (widget.onShareToContact != null) {
        await widget.onShareToContact!(contact, widget.shareUrl);
      } else {
        await Clipboard.setData(ClipboardData(text: widget.shareUrl));
      }
      if (!mounted) return;
      widget.onShared?.call();
      if (_expanded) {
        await _toggleExpanded();
      }
    } finally {
      if (mounted) {
        setState(() {
          reloadContacts();
          _sendingContactId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TapRegion(
      onTapOutside: (_) {
        _collapseIfExpanded();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizeTransition(
            axisAlignment: -1,
            sizeFactor: _menuSize,
            child: FadeTransition(
              opacity: _menuFade,
              child: SlideTransition(
                position: _menuSlide,
                child: Padding(padding: const EdgeInsets.only(bottom: 8), child: _buildInlineMenu(context, cs)),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(context.uiRadiusLg),
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: AnimatedBuilder(
                  animation: _iconTurn,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _iconTurn.value,
                      child: Icon(CupertinoIcons.paperplane_fill, size: 28, color: _expanded ? cs.primary : cs.onSurface.withValues(alpha: 0.9)),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineMenu(BuildContext context, ColorScheme cs) {
    final contacts = _sortedContacts;

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 270),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(context.uiRadiusLg),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
            boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 8))],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActionTile(icon: CupertinoIcons.link, label: _copying ? 'Copying...' : 'Copy video link', busy: _copying, onTap: _copyLink),

                const SizedBox(height: 9),

                if (_loadingContacts)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(widget.emptyStateLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (int i = 0; i < contacts.length; i++) _buildAnimatedContactChip(i: i, contact: contacts[i], colorScheme: cs)],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedContactChip({required int i, required ShareContact contact, required ColorScheme colorScheme}) {
    final start = (0.2 + (i * 0.07)).clamp(0, 0.8).toDouble();

    final end = (start + 0.35).clamp(start + 0.05, 1).toDouble();

    final chipCurve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: chipCurve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero).animate(chipCurve),
        child: _ContactChip(
          contact: contact,
          isSending: _sendingContactId == contact.id,
          alreadySharedWithThisVideo: contact.alreadySharedWithThisVideo,
          onTap: () => _shareToContact(contact),
          colorScheme: colorScheme,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _ActionTile({required this.icon, required this.label, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.primaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(context.uiRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 18, color: cs.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
                ),
              ),
              if (busy) SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimaryContainer)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactChip extends StatelessWidget {
  final ShareContact contact;
  final bool isSending;
  final bool alreadySharedWithThisVideo;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _ContactChip({
    required this.contact,
    required this.isSending,
    required this.alreadySharedWithThisVideo,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSending ? colorScheme.tertiaryContainer : (alreadySharedWithThisVideo ? colorScheme.secondaryContainer : colorScheme.surfaceContainer),
      borderRadius: BorderRadius.circular(context.uiRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        onTap: isSending ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: colorScheme.primaryContainer,
                foregroundImage: (contact.avatarUrl?.isNotEmpty ?? false) ? NetworkImage(contact.avatarUrl!) : null,
                child: Text(
                  contact.name.trim().isEmpty ? '?' : contact.name.trim()[0].toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 115),
                child: Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isSending
                        ? colorScheme.onTertiaryContainer
                        : (alreadySharedWithThisVideo ? colorScheme.onSecondaryContainer : colorScheme.onSurface),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!isSending && alreadySharedWithThisVideo)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(CupertinoIcons.checkmark_circle_fill, size: 14, color: colorScheme.onSecondaryContainer),
                ),
              if (isSending)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8, color: colorScheme.onTertiaryContainer)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
