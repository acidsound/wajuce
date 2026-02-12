import 'package:flutter/material.dart';
import 'dart:typed_data';

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

    double x = 0;
    for (int i = 0; i < samples.length; i++) {
      // Map 0..255 to -1..1
      // data[i] is int (0-255)
      final val = samples[i];
      final normalized = (val - 128) / 128.0; 
      
      // Map to height
      final yPos = height / 2.0 - (normalized * height / 2.0);

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
