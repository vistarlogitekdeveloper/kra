class AppAssets {
  AppAssets._();

  static const String _imagesPath = 'assets/images';

  /// Legacy wordmark / brand glyph. Still bundled so older surfaces that
  /// reference [logo] directly keep rendering.
  static const String logo = '$_imagesPath/vistar_logo.png';

  /// Rainbow "Vistar" wordmark used by the Vistar Premium ambient
  /// watermark, the splash orbit loader, and card corner accents. Bundled
  /// as `assets/images/logo.png`.
  static const String sMark = '$_imagesPath/logo.png';

  /// Rainbow wordmark for splash + login art panel — same source asset
  /// as [sMark] today.
  static const String wordmark = sMark;
}
