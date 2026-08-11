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
