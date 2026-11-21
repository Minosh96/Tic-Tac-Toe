import 'dart:convert';

import 'package:image_picker/image_picker.dart';

/// Picks and compresses images locally into Firestore-safe Base64 JPEG payloads
/// (works on Firebase Spark free tier without needing Firebase Storage).
class ImageHelper {
  static final ImagePicker _picker = ImagePicker();

  static const int maxAvatarBase64Chars = 130000;
  static const int maxChatImageBase64Chars = 300000;

  /// Picks a profile avatar photo from the device gallery and encodes it cleanly.
  static Future<String?> pickProfilePhotoBase64() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 70,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final encoded = base64Encode(bytes);
    if (encoded.length > maxAvatarBase64Chars) {
      throw Exception('Selected image is too large. Please pick a smaller photo.');
    }
    return encoded;
  }

  /// Picks an image from gallery or camera to share in chat.
  static Future<String?> pickChatImageBase64({
    ImageSource source = ImageSource.gallery,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 680,
      maxHeight: 680,
      imageQuality: 60,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final encoded = base64Encode(bytes);
    if (encoded.length > maxChatImageBase64Chars) {
      throw Exception('Image is too large for chat. Try a smaller photo.');
    }
    return encoded;
  }
}
