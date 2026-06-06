class AppAssets {
  AppAssets._();

  static const String _imagesPath = 'assets/images';

  /// Wordmark / logo bundled with the legacy theme — kept so existing
  /// callers don't break. New surfaces should prefer [sMark] (the rainbow
  /// swoosh) and [wordmark] (the new "Vistar" wordmark) when those files
  /// are dropped under `assets/images/`.
  static const String logo = '$_imagesPath/vistar_logo.png';

  /// Rainbow "S" swoosh used by the Vistar Premium signature treatments —
  /// ambient watermark, splash orbit, card corner accents. Falls back to
  /// [logo] via `Image.asset`'s `errorBuilder` until the dedicated asset
  /// is added to `assets/images/vistar_s_mark.png`.
  static const String sMark = '$_imagesPath/vistar_s_mark.png';

  /// Vistar wordmark used by the splash + login art panel. Falls back to
  /// [logo] until `assets/images/vistar_wordmark.png` is added.
  static const String wordmark = '$_imagesPath/vistar_wordmark.png';
}
