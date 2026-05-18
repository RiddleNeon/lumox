import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class InfiniteDotsBackground extends StatefulWidget {
  final TransformationController controller;

  const InfiniteDotsBackground({super.key, required this.controller});

  @override
  State<InfiniteDotsBackground> createState() => _InfiniteDotsBackgroundState();
}

class _InfiniteDotsBackgroundState extends State<InfiniteDotsBackground> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<ui.Image> _loadUiImageFromNetwork(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw Exception('Failed to load image');
    final bytes = response.bodyBytes;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  late ui.Image img;

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/dotted_background.frag');
      if (!mounted) return;
      final shader = program.fragmentShader();
      img = await _loadUiImageFromNetwork('https://res.cloudinary.com/dvw3vksqx/image/upload/v1773681710/smurf_ri5kfd.jpg');
      setState(() => _shader = shader);
    } catch (e) {
      debugPrint('dotted_background.frag failed to load – falling back to CPU painter: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final m = widget.controller.value;
        final offsetX = m.entry(0, 3);
        final offsetY = m.entry(1, 3);
        final scale = m.entry(0, 0);

        return CustomPaint(
          painter: _shader != null
              ? _ShaderDotsPainter(shader: _shader!, offsetX: offsetX, offsetY: offsetY, scale: scale, img: img, cs: Theme.of(context).colorScheme)
              : _CpuDotsPainter(offsetX: offsetX, offsetY: offsetY, scale: scale, cs: Theme.of(context).colorScheme),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _ShaderDotsPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image img;
  final double offsetX;
  final double offsetY;
  final double scale;
  final ColorScheme cs;

  const _ShaderDotsPainter({required this.shader, required this.offsetX, required this.offsetY, required this.scale, required this.img, required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    const double spacing = 25.0;
    const double accentSpacing = spacing * 4.0;
    final double period = accentSpacing * scale;
    
    final Color backgroundColor = cs.surface;
    final Color baseColor = cs.onSurface;
    final Color accentColor = cs.onSurfaceVariant;
    
    
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, offsetX % period)
      ..setFloat(3, offsetY % period)
      ..setFloat(4, scale)
      ..setFloat(5, baseColor.r)
      ..setFloat(6, baseColor.g)
      ..setFloat(7, baseColor.b)
      ..setFloat(8, accentColor.r)
      ..setFloat(9, accentColor.g)
      ..setFloat(10, accentColor.b)
      ..setFloat(11, backgroundColor.r)
      ..setFloat(12, backgroundColor.g)
      ..setFloat(13, backgroundColor.b);
    shader.setImageSampler(0, img);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderDotsPainter old) => old.offsetX != offsetX || old.offsetY != offsetY || old.scale != scale;
}

class _CpuDotsPainter extends CustomPainter {
  final double offsetX;
  final double offsetY;
  final double scale;
  final ColorScheme cs;
  const _CpuDotsPainter({required this.offsetX, required this.offsetY, required this.scale, required this.cs});

  static const double _baseSpacing = 50.0;

  @override
  void paint(Canvas canvas, Size size) {
    final double spacing = _baseSpacing * scale;
    final double radius = (2.0 * scale).clamp(0.6, 4.0);
    final double ox = offsetX % spacing;
    final double oy = offsetY % spacing;

    final pts = <Offset>[];
    for (double x = ox - spacing; x < size.width + spacing; x += spacing) {
      for (double y = oy - spacing; y < size.height + spacing; y += spacing) {
        pts.add(Offset(x, y));
      }
    }
    
    canvas.drawRect(Offset.zero & size, Paint()..color = cs.surface);

    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..color = cs.onSurface.withValues(alpha: 0.3)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = radius * 2,
    );
  }

  @override
  bool shouldRepaint(_CpuDotsPainter old) => old.offsetX != offsetX || old.offsetY != offsetY || old.scale != scale;
}
