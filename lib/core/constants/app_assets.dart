class AppAssets {
  AppAssets._();

  static const String _imagesPath = 'assets/images';

  /// Wordmark / logo bundled with the legacy theme. The Vistar Premium spec
  /// distinguishes between a rainbow "S" swoosh and a "Vistar" wordmark,
  /// but until those dedicated files are dropped into `assets/images/`,
  /// every slot points at this one file so the app loads cleanly without
  /// 404s from missing assets.
  static const String logo = '$_imagesPath/vistar_logo.png';

  /// Rainbow "S" swoosh used by the Vistar Premium signature treatments —
  /// ambient watermark, splash orbit, card corner accents. When you drop
  /// the dedicated file in, change this single constant to point at
  /// `$_imagesPath/vistar_s_mark.png`.
  static const String sMark = logo;

  /// Vistar wordmark used by the splash + login art panel. When you drop
  /// the dedicated file in, change this constant to point at
  /// `$_imagesPath/vistar_wordmark.png`.
  static const String wordmark = logo;
}
