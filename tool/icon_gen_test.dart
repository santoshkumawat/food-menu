// Draws the launcher icon and writes it to android/ and web/.
// Run with:  flutter test tool/icon_gen_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bgTop = Color(0xFFFF7043);
const _bgBottom = Color(0xFFD84315);

/// Bowl with steam, drawn on a 108-unit grid (the adaptive-icon canvas).
/// Everything sits inside the 66-unit safe zone (21..87).
void _glyph(Canvas c, double size, {double scale = 1}) {
  final u = size / 108;
  c.save();
  c.translate(size / 2, size / 2);
  c.scale(scale);
  c.translate(-size / 2, -size / 2);

  final white = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  // Bowl body
  final bowl = Path()
    ..moveTo(31 * u, 58 * u)
    ..cubicTo(31 * u, 76 * u, 42 * u, 84 * u, 54 * u, 84 * u)
    ..cubicTo(66 * u, 84 * u, 77 * u, 76 * u, 77 * u, 58 * u)
    ..close();
  c.drawPath(bowl, white);
  // Rim
  c.drawRRect(
    RRect.fromRectAndRadius(
        Rect.fromLTRB(28 * u, 55 * u, 80 * u, 60.5 * u), Radius.circular(2.75 * u)),
    white,
  );

  // Steam
  final steam = Paint()
    ..color = Colors.white.withValues(alpha: 0.92)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.6 * u
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  for (final x in [43.0, 54.0, 65.0]) {
    final p = Path()
      ..moveTo(x * u, 50 * u)
      ..cubicTo((x - 5) * u, 45 * u, (x + 5) * u, 40 * u, x * u, 33 * u);
    c.drawPath(p, steam);
  }
  c.restore();
}

Future<void> _write(String path, int px, void Function(Canvas, double) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()));
  paint(canvas, px.toDouble());
  final image = await recorder.endRecording().toImage(px, px);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
}

/// Full icon: gradient rounded square with the glyph (older Android, web).
void _full(Canvas c, double s, {bool round = true}) {
  final rect = Rect.fromLTWH(0, 0, s, s);
  final paint = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_bgTop, _bgBottom],
    ).createShader(rect);
  c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(round ? s * 0.22 : 0)), paint);
  _glyph(c, s, scale: 1.15);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate launcher icons', () async {
    const res = 'android/app/src/main/res';
    const legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    const adaptive = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};

    for (final e in legacy.entries) {
      await _write('$res/mipmap-${e.key}/ic_launcher.png', e.value, _full);
    }
    for (final e in adaptive.entries) {
      // Transparent foreground; the colour behind it comes from colors.xml.
      await _write('$res/mipmap-${e.key}/ic_launcher_foreground.png', e.value,
          (c, s) => _glyph(c, s, scale: 0.78));
    }
    await _write('web/favicon.png', 32, _full);
    await _write('web/icons/Icon-192.png', 192, _full);
    await _write('web/icons/Icon-512.png', 512, _full);
    await _write('web/icons/Icon-maskable-192.png', 192, (c, s) => _full(c, s, round: false));
    await _write('web/icons/Icon-maskable-512.png', 512, (c, s) => _full(c, s, round: false));
    await _write('tool/icon_preview.png', 512, _full);
    expect(File('$res/mipmap-xxxhdpi/ic_launcher.png').existsSync(), isTrue);
  });
}
