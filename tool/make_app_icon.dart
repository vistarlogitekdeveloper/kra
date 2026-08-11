// Builds the SQUARE launcher-icon sources from the brand logo.
//
//   dart run tool/make_app_icon.dart
//   dart run flutter_launcher_icons
//
// Why this exists: the brand logo is a 1536x1024 (3:2) wordmark, and
// flutter_launcher_icons resizes its input straight to a square — which would
// stretch "ViStar" horizontally. So the logo is FITTED (aspect preserved) onto a
// square canvas here, and the generator only ever sees a square.
//
// Two outputs, because Android's adaptive icon needs a different safe area from
// the plain legacy/iOS/web icon:
//
//   app_icon.png            1024x1024, white background, logo at ~86% width.
//                           Used for iOS, web and the legacy Android icon.
//   app_icon_foreground.png 1024x1024, TRANSPARENT, logo at ~62% width.
//                           Android crops a circle/squircle out of the adaptive
//                           foreground — only the middle 66% is guaranteed
//                           visible — so the logo sits well inside that or the
//                           ends of the wordmark get clipped on some launchers.
//
// The source is a JPEG despite its .png name; decodeImage sniffs the content, so
// that resolves itself. JPEG carries no alpha, so the logo's own white
// background is baked in — which is why the square canvas is white too rather
// than transparent, otherwise the icon would show a white logo block floating on
// nothing.

import 'dart:io';

import 'package:image/image.dart';

/// Source of truth for the icon. Content-sniffed, so the .png/JPEG mismatch is
/// not a problem.
const _source = 'assets/images/vistar_logo.png';
const _outDir = 'assets/icons';

/// Square canvas edge. 1024 is what the generator wants for iOS.
const _canvas = 1024;

/// Fraction of the canvas width the logo occupies.
///   * 0.86 for the plain icon — a little breathing room from the edge.
///   * 0.62 for the adaptive foreground — inside Android's 66% safe area.
const _plainFit = 0.86;
const _adaptiveFit = 0.62;

void main() {
  final file = File(_source);
  if (!file.existsSync()) {
    stderr.writeln('✗ Source not found: $_source');
    exit(1);
  }

  final logo = decodeImage(file.readAsBytesSync());
  if (logo == null) {
    stderr.writeln('✗ Could not decode $_source');
    exit(1);
  }
  stdout.writeln('Source: ${logo.width}x${logo.height}');

  Directory(_outDir).createSync(recursive: true);

  _write(
    logo: logo,
    fit: _plainFit,
    // Opaque white: matches the logo's own baked-in background.
    background: ColorRgba8(255, 255, 255, 255),
    path: '$_outDir/app_icon.png',
  );
  _write(
    logo: logo,
    fit: _adaptiveFit,
    // Transparent: the adaptive BACKGROUND layer supplies the colour
    // (adaptive_icon_background in pubspec.yaml).
    background: ColorRgba8(0, 0, 0, 0),
    path: '$_outDir/app_icon_foreground.png',
  );

  // The MARK on its own, for anywhere the icon renders small — a browser
  // favicon is 16-32px, where the full wordmark is an illegible smudge.
  final mark = _cropMark(logo);
  _write(
    logo: mark,
    // Nearly fills the canvas: at favicon size every pixel of margin costs
    // legibility, and there is no launcher mask to worry about here.
    fit: 0.96,
    background: ColorRgba8(255, 255, 255, 255),
    path: '$_outDir/app_icon_mark.png',
  );
}

/// Crops the logo down to its swoosh, discarding the wordmark.
///
/// Found by colour rather than by hardcoded pixel coordinates, so it survives
/// the logo being re-exported at a different size: the lettering is purple only,
/// while the swoosh is the sole part of the mark carrying warm hues (red →
/// orange → yellow). So the bounding box of "warm" pixels IS the swoosh.
Image _cropMark(Image logo) {
  var minX = logo.width, minY = logo.height, maxX = -1, maxY = -1;
  for (var y = 0; y < logo.height; y++) {
    for (var x = 0; x < logo.width; x++) {
      final p = logo.getPixel(x, y);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      // Warm = red/orange/yellow: red leads, blue is clearly suppressed. Excludes
      // both the purple lettering (blue high) and the white ground (all high).
      final warm = r > 140 && r > b + 60 && g > b + 20;
      if (!warm) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) {
    stdout.writeln('! No warm pixels found — falling back to the full logo.');
    return logo;
  }

  // Vertically: grow OUTWARD, to take in the swoosh's purple outline and its
  // tips, which the warm test deliberately excluded.
  //
  // Horizontally: pull INWARD. The swoosh sweeps between "Vi" and "tar" and its
  // tails reach past both, so any axis-aligned box holding the whole swoosh also
  // catches slivers of the "i" and the "t" — which read as specks of noise once
  // scaled down. Trimming the outermost few percent of the tails is the cheaper
  // trade than keeping stray letter fragments in the icon.
  //
  // No squaring here: [_write] already fits any aspect ratio onto the square
  // canvas, and forcing a square would re-expand horizontally into the very
  // letters this inset removes.
  final warmW = maxX - minX, warmH = maxY - minY;
  final inset = (warmW * 0.08).round();
  final grow = (warmH * 0.06).round();
  final x0 = (minX + inset).clamp(0, logo.width - 1);
  final y0 = (minY - grow).clamp(0, logo.height - 1);
  final w = (maxX - inset - x0).clamp(1, logo.width - x0);
  final h = (maxY + grow - y0).clamp(1, logo.height - y0);

  stdout.writeln('Mark: warm box ($minX,$minY)-($maxX,$maxY) → crop ${w}x$h');
  return copyCrop(logo, x: x0, y: y0, width: w, height: h);
}

/// Fits [logo] onto a square canvas, centred, preserving aspect ratio.
void _write({
  required Image logo,
  required double fit,
  required Color background,
  required String path,
}) {
  final target = (_canvas * fit).round();

  // Scale to fit the target BOX, not the target width — so a logo that is taller
  // than it is wide would still fit. Ours is wide, so width binds in practice.
  final scale = target / (logo.width > logo.height ? logo.width : logo.height);
  final w = (logo.width * scale).round();
  final h = (logo.height * scale).round();
  final resized =
      copyResize(logo, width: w, height: h, interpolation: Interpolation.cubic);

  final canvas = Image(width: _canvas, height: _canvas, numChannels: 4);
  fill(canvas, color: background);
  compositeImage(
    canvas,
    resized,
    dstX: ((_canvas - w) / 2).round(),
    dstY: ((_canvas - h) / 2).round(),
  );

  File(path).writeAsBytesSync(encodePng(canvas));
  stdout.writeln('✓ $path  ${_canvas}x$_canvas  (logo ${w}x$h)');
}
