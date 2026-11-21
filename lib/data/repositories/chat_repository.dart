import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/game_engine.dart';
import '../../domain/models/social_models.dart';

/// Direct 1-on-1 friend chat supporting real-time text + image sharing + unread tracking.
class ChatRepository {
  ChatRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? databaseId,
  })  : _db = firestore ??
            (databaseId != null
                ? FirebaseFirestore.instanceFor(
                    app: Firebase.app(),
                    databaseId: databaseId,
                  )
                : FirebaseFirestore.instance),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  String chatIdFor(String uidA, String uidB) =>
      GameEngine.rivalryIdFor(uidA, uidB);

  DocumentReference<Map<String, dynamic>> _chatRef(String chatId) =>
      _db.collection('chats').doc(chatId);

  /// Streams all direct chat threads involving [uid].
  Stream<List<DirectChatSummary>> watchUserChats(String uid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(DirectChatSummary.fromFirestore)
          .toList(growable: true);
      list.sort(
        (a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
          a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      return list;
    });
  }

  /// Streams unread direct chat threads for [uid] (drives the notification bell).
  Stream<List<DirectChatSummary>> watchUnreadChats(String uid) {
    return watchUserChats(uid).map(
      (chats) => chats.where((c) => c.isUnreadFor(uid)).toList(growable: false),
    );
  }

  /// Ensures the parent chat thread doc exists before subscribing to messages.
  Future<String> ensureChatThread(String friendUid) async {
    final meUid = currentUid;
    final chatId = chatIdFor(meUid, friendUid);
    final ref = _chatRef(chatId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'participants': [meUid, friendUid]..sort(),
        'lastMessage': '',
        'lastSenderUid': '',
        'unreadBy': <String>[],
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return chatId;
  }

  Stream<List<DirectChatMessage>> watchMessages(String chatId) {
    return _chatRef(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(DirectChatMessage.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<void> markChatRead(String chatId) async {
    final uid = currentUid;
    try {
      await _chatRef(chatId).update({
        'unreadBy': FieldValue.arrayRemove([uid]),
      });
    } catch (_) {}
  }

  Future<void> sendMessage({
    required String friendUid,
    required String senderName,
    String text = '',
    String? imageBase64,
  }) async {
    final trimmed = text.trim();
    final hasImage = imageBase64 != null && imageBase64.isNotEmpty;
    if (trimmed.isEmpty && !hasImage) return;
    if (trimmed.length > 500) {
      throw Exception('Message is too long (max 500 characters).');
    }

    final meUid = currentUid;
    final chatId = await ensureChatThread(friendUid);
    final chatRef = _chatRef(chatId);

    final preview =
        trimmed.isNotEmpty ? trimmed : '📷 Shared an image';

    final batch = _db.batch();
    batch.set(chatRef.collection('messages').doc(), {
      'senderUid': meUid,
      'senderName': senderName,
      'text': trimmed,
      if (hasImage) 'imageBase64': imageBase64,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(chatRef, {
      'lastMessage': preview.length > 120 ? preview.substring(0, 120) : preview,
      'lastSenderUid': meUid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadBy': [friendUid],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
