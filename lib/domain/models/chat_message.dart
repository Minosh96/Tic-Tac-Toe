import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable domain model representing a single room chat message (text and/or image).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.uid,
    required this.text,
    this.imageBase64,
    required this.createdAt,
    required this.expireAt,
  });

  final String id;
  final String uid;
  final String text;
  final String? imageBase64;
  final DateTime? createdAt;
  final DateTime? expireAt;

  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;

  factory ChatMessage.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final created = data['createdAt'];
    final expiry = data['expireAt'];
    return ChatMessage(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      text: data['text'] as String? ?? '',
      imageBase64: data['imageBase64'] as String?,
      createdAt: created is Timestamp ? created.toDate() : null,
      expireAt: expiry is Timestamp ? expiry.toDate() : null,
    );
  }

  bool isExpired([DateTime? now]) {
    final expiry = expireAt;
    if (expiry == null) return true;
    return !expiry.isAfter(now ?? DateTime.now());
  }
}
