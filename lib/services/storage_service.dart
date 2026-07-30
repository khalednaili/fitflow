import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Thin wrapper around Firebase Storage for uploading/removing product
/// images. Kept separate from [ProductService] so it can be swapped/mocked
/// independently of Firestore in tests.
class StorageService {
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Uploads [bytes] under `products/{gymId}/...` and returns its public
  /// download URL. [filename] is only used to preserve the file extension.
  Future<String> uploadProductImage({
    required String gymId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final safeName = filename.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path =
        'products/$gymId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = _storage.ref().child(path);
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: _contentTypeFor(safeName)),
    );
    return task.ref.getDownloadURL();
  }

  /// Best-effort delete; failures are swallowed since a missing/already
  /// deleted image should never block a product edit.
  Future<void> deleteImage(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // Ignore — image may already be gone or URL may not be a Storage ref.
    }
  }

  String? _contentTypeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    return null;
  }
}
