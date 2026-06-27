// Cross-platform JSON download helper.
//
// On web  → triggers a browser "Save As" dialog.
// On other platforms → no-op (caller should fall back to clipboard).
export 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';
