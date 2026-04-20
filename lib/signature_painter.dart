import 'package:flutter/material.dart' hide Ink;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';

class SignaturePainter extends CustomPainter {
  final Ink ink;
  final double gridSpacing;
  final Map<int, String> linePreviews;
  final double horizontalOffset;
  final double inkOpacity;

  SignaturePainter({
    required this.ink,
    required this.gridSpacing,
    required this.linePreviews,
    required this.horizontalOffset,
    this.inkOpacity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..strokeWidth = 1.0;

    for (double y = gridSpacing; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      int lineIndex = (y / gridSpacing).floor() - 1;
      if (linePreviews.containsKey(lineIndex)) {
        // Redrawn text remains synced with the grid during scrolls [cite: 182]
        _drawTextAt(canvas, linePreviews[lineIndex]!, y - gridSpacing);
      }
    }

    final Paint strokePaint = Paint()
      ..color = Colors.black87.withOpacity(inkOpacity)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.5;

    for (final stroke in ink.strokes) {
      if (stroke.points.isEmpty) continue;
      for (int i = 0; i < stroke.points.length - 1; i++) {
        canvas.drawLine(
          Offset(stroke.points[i].x, stroke.points[i].y),
          Offset(stroke.points[i + 1].x, stroke.points[i + 1].y),
          strokePaint,
        );
      }
    }
  }

  void _drawTextAt(Canvas canvas, String text, double yOffset) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.blue.shade900.withOpacity(0.8),
          fontSize: 22,
          fontWeight: FontWeight.w400,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    // Text is drawn 10px down from the top of the grid row
    textPainter.paint(canvas, Offset(horizontalOffset + 24, yOffset + 10));
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}