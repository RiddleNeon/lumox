import 'package:flutter/material.dart';
import 'package:lumox/logic/users/user_model.dart';
import 'package:lumox/ui/misc/avatar.dart';
import 'package:lumox/ui/screens/profile_screen.dart';
import 'package:lumox/ui/widgets/overlays/buttons/follow_button.dart';

import '../../../../base_logic.dart';
import '../../../../logic/local_storage/local_seen_service.dart';
import '../../theme/theme_ui_values.dart';

class UserCard extends StatefulWidget {
  const UserCard({super.key, required this.initialUser, required this.cs, this.onFollowChange});

  final void Function(bool)? onFollowChange;
  final UserProfile initialUser;
  final ColorScheme cs;

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard> {
  late UserProfile user = widget.initialUser;
  late final GlobalKey<FollowButtonState> _followButtonState = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: widget.cs.surfaceContainer,
        borderRadius: BorderRadius.circular(context.uiRadiusMd),
        border: Border.all(color: widget.cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) {
                return ProfileScreen(
                  initialProfile: user,
                  ownProfile: user.id == currentUser.id,
                  hasBackButton: true,
                  initialFollowed: localSeenService.isFollowing(user.id),
                  onFollowChange: (bool followed) {
                    if (mounted) {
                      setState(() {
                        user = user.copyWith(followersCount: user.followersCount + (followed ? 1 : -1));
                        _followButtonState.currentState?.setFollowed(followed);
                        widget.onFollowChange?.call(followed);
                      });
                    }
                  },
                );
              },
            ),
          );
        },
        child: Row(
          children: [
            Avatar(name: user.displayName, imageUrl: user.profileImageUrl, colorScheme: widget.cs),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: TextStyle(color: widget.cs.onSurface, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text('@${user.username}', style: TextStyle(color: widget.cs.onSurfaceVariant, fontSize: 13)),
                  /*Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      StatChip(icon: Icons.video_collection, label: _formatCount(user.totalVideosCount), cs: widget.cs),
                      StatChip(icon: Icons.favorite_border_rounded, label: _formatCount(user.totalLikesCount), cs: widget.cs),
                      StatChip(icon: FontAwesomeIcons.users, label: _formatCount(user.followersCount), cs: widget.cs),
                    ],
                  ),*/
                  //fixme
                ],
              ),
            ),
            if (user.id != currentUser.id)
              FollowButton(
                key: _followButtonState,
                onChanged: (followed) async {
                  if (mounted) {
                    setState(() {
                      user = user.copyWith(followersCount: user.followersCount + (followed ? 1 : -1));
                      widget.onFollowChange?.call(followed);
                    });
                  }
                },
                initialSubscribed: localSeenService.isFollowing(user.id),
                user: user,
              ),
          ],
        ),
      ),
    );
  }
}
