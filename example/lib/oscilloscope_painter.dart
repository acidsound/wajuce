import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class OscilloscopePainter extends CustomPainter {
  final Uint8List samples;

  OscilloscopePainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final sliceWidth = width / samples.length;
    final centerY = height / 2.0;
    var peak = 0;
    for (final sample in samples) {
      peak = math.max(peak, (sample - 128).abs());
    }
    final visualScale = peak <= 1
        ? 1.0
        : ((height * 0.35 * 128.0) / (peak * centerY)).clamp(1.0, 10.0);

    double x = 0;
    for (int i = 0; i < samples.length; i++) {
      // Map 0..255 to -1..1
      // data[i] is int (0-255)
      final val = samples[i];
      final normalized = ((val - 128) / 128.0) * visualScale;

      // Map to height
      final yPos = centerY - (normalized * centerY);

      if (i == 0) {
        path.moveTo(x, yPos);
      } else {
        path.lineTo(x, yPos);
      }
      x += sliceWidth;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(OscilloscopePainter old) => true;
}
