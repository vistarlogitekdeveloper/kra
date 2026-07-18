import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation of [saveProofFile] — triggers a browser download.
///
/// Wraps the decoded bytes in a Blob, hands the browser an object URL on a
/// hidden `<a download>`, clicks it, then revokes the URL so the blob can be
/// garbage-collected. This is what lets a reporting manager actually open a
/// PDF/Excel/Word proof rather than just seeing its filename.
Future<bool> saveProofFile({
  required Uint8List bytes,
  required String fileName,
  required String mime,
}) async {
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = fileName;
    anchor.style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } finally {
    // Always release the object URL, even if the click path threw.
    web.URL.revokeObjectURL(url);
  }
}
