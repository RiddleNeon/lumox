import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumox/ui/misc/avatar.dart';
import 'package:lumox/ui/misc/basic_player.dart';
import 'package:lumox/ui/router/router.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';
import 'package:lumox/ui/widgets/camera/web_camera.dart';

class CallingApp extends StatelessWidget {
  final String name;
  final String? profileImageUrl;

  const CallingApp({super.key, required this.name, this.profileImageUrl});

  @override
  Widget build(BuildContext context) {
    return CallingScreen(joinFuture: Future.delayed(const Duration(milliseconds: 2500)), name: name, profileImageUrl: profileImageUrl);
  }
}

class CallingScreen extends StatefulWidget {
  final Future<void> joinFuture;
  final String name;
  final String? profileImageUrl;

  const CallingScreen({super.key, required this.joinFuture, required this.name, this.profileImageUrl});

  @override
  State<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends State<CallingScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulse;
  late AnimationController _videoAppearController;
  bool _joined = false;
  bool _cameraConnected = false;
  static const GlobalObjectKey<WebCameraState> _cameraKey = GlobalObjectKey("CallCamera");

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 12.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _videoAppearController = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _videoAppearController.dispose();
    super.dispose();
  }

  Widget buildActionButton({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required Color labelColor,
    required VoidCallback onTap,
    double size = 68,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  return Container(
                    width: size + _pulse.value,
                    height: size + _pulse.value,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: bg.withValues(alpha: 0.12)),
                  );
                },
              ),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [bg.withValues(alpha: 0.95), bg.withValues(alpha: 0.78)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(icon, color: fg, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: labelColor, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primary = cs.primary;
    final secondary = cs.secondary;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.scaffoldBackgroundColor.withValues(alpha: 0.95), theme.scaffoldBackgroundColor.withValues(alpha: 0.80)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              top: 24,
              left: 20,
              right: 20,
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: widget.profileImageUrl == null
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [primary, secondary]),
                          )
                        : null,
                    child: widget.profileImageUrl == null
                        ? Center(
                            child: Text(
                              widget.name.substring(0, 2),
                              style: TextStyle(fontWeight: FontWeight.bold, color: cs.onPrimary),
                            ),
                          )
                        : Avatar(imageUrl: widget.profileImageUrl, name: widget.name, colorScheme: theme.colorScheme),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [Icon(Icons.more_vert, color: cs.onSurfaceVariant)],
                  ),
                ],
              ),
            ),
            Positioned(
              top: media.size.height * 0.14,
              left: 16,
              right: 16,
              height: media.size.height * 0.56,
              child: AnimatedBuilder(
                animation: _videoAppearController,
                builder: (context, child) {
                  if (!_joined || !_cameraConnected) {
                    return Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(context.uiRadiusLg),
                        color: cs.surfaceContainerHigh.withValues(alpha: 0.55),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.6, valueColor: AlwaysStoppedAnimation(primary))),
                            const SizedBox(height: 12),
                            Text('Establishing Connection...', style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  }

                  final t = Curves.easeOut.transform(_videoAppearController.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                  );
                },
                child: Hero(
                  tag: 'video_placeholder',
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(context.uiRadiusLg),
                      gradient: LinearGradient(
                        colors: [cs.surfaceBright.withValues(alpha: 0.08), cs.surfaceDim.withValues(alpha: 0.04)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
                    ),
                    child: Transform.scale(
                      scale: 2,
                      child: FittedBox(
                        fit: BoxFit.fitHeight,
                        child: SizedBox(width: 1024, height: 1024, child: BasicMemePlayer(vid: MemeVid.hamster)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 28,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      buildActionButton(
                        icon: Icons.mic_off,
                        label: 'Mute',
                        bg: cs.primary,
                        fg: cs.onPrimary,
                        labelColor: cs.onSurfaceVariant,
                        onTap: () {},
                        size: 60,
                      ),
                      GestureDetector(
                        onTap: () {
                          routerConfig.pop();
                        },
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                AnimatedBuilder(
                                  animation: _pulse,
                                  builder: (context, child) {
                                    return Container(
                                      width: 84 + _pulse.value,
                                      height: 84 + _pulse.value,
                                       decoration: BoxDecoration(shape: BoxShape.circle, color: cs.error.withValues(alpha: 0.16)),
                                    );
                                  },
                                ),
                                Container(
                                  width: 84,
                                  height: 84,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(colors: [cs.error, cs.error.withValues(alpha: 0.88)]),
                                  ),
                                  child: Icon(Icons.call_end, color: cs.onError, size: 32),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('Hang Up', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      buildActionButton(
                        icon: Icons.cameraswitch,
                        label: 'Flip Camera',
                        bg: cs.tertiary,
                        fg: cs.onTertiary,
                        labelColor: cs.onSurfaceVariant,
                        onTap: () {
                          _cameraKey.currentState?.switchCamera();
                        },
                        size: 60,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              right: 28,
              top: media.size.height * 0.14 + 12,
              child: Container(
                width: 96,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(context.uiRadiusMd),
                  color: cs.inverseSurface.withValues(alpha: 0.58),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadiusGeometry.all(Radius.circular(context.uiRadiusLg)),
                  child: WebCamera(
                    preferFrontCamera: true,
                    key: _cameraKey,
                    onCameraConnected: () {
                      setState(() {
                        _cameraConnected = true;
                        _videoAppearController.animateTo(0.1);
                        widget.joinFuture
                            .then((_) {
                              if (mounted) {
                                setState(() => _joined = true);
                                _videoAppearController.forward();
                              }
                            })
                            .catchError((_) {});
                      });
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
