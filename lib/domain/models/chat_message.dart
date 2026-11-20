import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable domain model representing a single room chat message.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.uid,
    required this.text,
    required this.createdAt,
    required this.expireAt,
  });

  final String id;
  final String uid;
  final String text;
  final DateTime? createdAt;
  final DateTime? expireAt;

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
