import 'dart:typed_data';

/// Non-web fallback for [saveProofFile].
///
/// The app ships as a web build, so the browser download path is the one that
/// matters. Saving to disk on native would need a file-system/permissions
/// dependency this project doesn't carry, so report "unsupported" and let the
/// caller surface a message — rather than silently doing nothing.
Future<bool> saveProofFile({
  required Uint8List bytes,
  required String fileName,
  required String mime,
}) async =>
    false;
