/// Saves a fetched proof attachment to the viewer's device.
///
/// A reporting manager / management needs to actually OPEN the evidence an
/// employee filed — not just see that a file exists. Images can be previewed
/// inline, but a PDF / Excel / Word / PowerPoint can only be reviewed by
/// downloading it, so this is what makes the attachment genuinely accessible.
///
/// Implementation is platform-split: the web build triggers a browser download
/// (the app ships as a web app), and native builds fall back to "unsupported"
/// rather than breaking the build.
library;

export 'proof_file_saver_io.dart'
    if (dart.library.js_interop) 'proof_file_saver_web.dart';
