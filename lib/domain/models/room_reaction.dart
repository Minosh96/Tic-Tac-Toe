import 'package:cloud_firestore/cloud_firestore.dart';

/// Allowed live emoji reactions (expanded with funny & expressive emojis).
const List<String> allowedReactionEmojis = [
  '😂',
  '🤣',
  '😎',
  '😲',
  '👏',
  '🔥',
  '🥳',
  '😭',
  '👍',
  '❤️',
  '🤪',
  '🤡',
  '💀',
  '🤯',
  '🙈',
  '💩',
  '👻',
  '👑',
  '⚡',
  '👦',
  '👧',
];

/// Allowed playful, non-abusive quick taunts.
const List<String> allowedQuickTaunts = [
  'Your turn!',
  'Nice move!',
  'That was close!',
  'Good luck!',
  'Rematch?',
  'Well played!',
  "Let's go!",
  'Game on!',
];

/// Short-lived room reaction or quick taunt event.
class RoomReaction {
  const RoomReaction({
    required this.id,
    required this.senderUid,
    required this.kind,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String senderUid;
  final String kind; // 'emoji' | 'taunt'
  final String payload;
  final DateTime createdAt;

  bool get isEmoji => kind == 'emoji';
  bool get isTaunt => kind == 'taunt';

  factory RoomReaction.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final ts = data['createdAt'];
    return RoomReaction(
      id: doc.id,
      senderUid: data['senderUid'] as String? ?? '',
      kind: data['kind'] as String? ?? 'emoji',
      payload: data['payload'] as String? ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
