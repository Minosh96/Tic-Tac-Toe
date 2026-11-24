import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/game_engine.dart';
import '../../domain/models/social_models.dart';

/// Direct 1-on-1 friend chat supporting real-time text, images, call logs & exact unread counts.
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
  final Map<String, DateTime> _clearedAtByChatId = <String, DateTime>{};
  final Set<String> _deletedForMeMessageIds = <String>{};

  void resetLocalCaches() {
    _clearedAtByChatId.clear();
    _deletedForMeMessageIds.clear();
  }

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

  /// Streams unread direct chat threads for [uid] (drives the notification bell & badges).
  Stream<List<DirectChatSummary>> watchUnreadChats(String uid) {
    return watchUserChats(uid).map(
      (chats) => chats.where((c) => c.isUnreadFor(uid)).toList(growable: false),
    );
  }

  /// Streams a map of friendUid -> DirectChatSummary for per-friend unread counts & previews.
  Stream<Map<String, DirectChatSummary>> watchChatsByFriend(String uid) {
    return watchUserChats(uid).map((chats) {
      final map = <String, DirectChatSummary>{};
      for (final c in chats) {
        final other = c.otherParticipantUid(uid);
        if (other.isNotEmpty) map[other] = c;
      }
      return map;
    });
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
        'lastSenderName': '',
        'unreadBy': <String>[],
        'unreadCounts': {meUid: 0, friendUid: 0},
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final rawCleared = snap.data()?['clearedAtBy'];
      if (rawCleared is Map && rawCleared[meUid] is Timestamp) {
        final remoteTs = (rawCleared[meUid] as Timestamp).toDate();
        final localTs = _clearedAtByChatId[chatId];
        if (localTs == null || remoteTs.isAfter(localTs)) {
          _clearedAtByChatId[chatId] = remoteTs;
        }
      }
    }
    return chatId;
  }

  Stream<List<DirectChatMessage>> watchMessages(String chatId) {
    return _chatRef(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .map((snap) {
      final uid = _auth.currentUser?.uid ?? '';
      final clearedAt = _clearedAtByChatId[chatId];
      return snap.docs
          .map(DirectChatMessage.fromFirestore)
          .where((m) {
            if (_deletedForMeMessageIds.contains(m.id)) return false;
            if (uid.isNotEmpty && m.isDeletedFor(uid)) return false;
            if (clearedAt == null) return true;
            final created = m.createdAt;
            return created != null && created.isAfter(clearedAt);
          })
          .toList(growable: false);
    });
  }

  /// Clears chat history ONLY for the current user ("Clear for Me").
  /// The other person's chat history on their device remains intact.
  Future<void> clearChatForMe(String chatId) async {
    final uid = currentUid;
    _clearedAtByChatId[chatId] = DateTime.now();
    try {
      await _chatRef(chatId).update({
        'clearedAtBy.$uid': FieldValue.serverTimestamp(),
        'unreadBy': FieldValue.arrayRemove([uid]),
        'unreadCounts.$uid': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Clears all messages in a 1-on-1 direct chat thread for BOTH players ("Clear for Everyone").
  Future<void> clearChatForEveryone(String chatId) async {
    final uid = currentUid;
    _clearedAtByChatId[chatId] = DateTime.now();
    final chatRef = _chatRef(chatId);

    try {
      final messagesSnap = await chatRef.collection('messages').get();
      final docs = messagesSnap.docs;
      const chunkSize = 400;
      for (var i = 0; i < docs.length; i += chunkSize) {
        final batch = _db.batch();
        final end = (i + chunkSize < docs.length) ? i + chunkSize : docs.length;
        for (var j = i; j < end; j++) {
          batch.delete(docs[j].reference);
        }
        await batch.commit();
      }
    } catch (_) {}

    try {
      await chatRef.update({
        'lastMessage': '',
        'lastSenderUid': '',
        'lastSenderName': '',
        'unreadBy': <String>[],
        'unreadCounts.$uid': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Clears a chat (defaults to [forEveryone] = true when unspecified).
  Future<void> clearChat(String chatId, {bool forEveryone = true}) async {
    if (forEveryone) {
      await clearChatForEveryone(chatId);
    } else {
      await clearChatForMe(chatId);
    }
  }

  /// Hides/deletes a single message for the current user only ("Delete for Me").
  Future<void> deleteMessageForMe({
    required String chatId,
    required String messageId,
  }) async {
    final uid = currentUid;
    _deletedForMeMessageIds.add(messageId);
    try {
      await _chatRef(chatId).collection('messages').doc(messageId).update({
        'deletedFor': FieldValue.arrayUnion([uid]),
      });
    } catch (_) {}
  }

  /// Unsends / permanently deletes a single message for everyone in the chat ("Unsend / Delete for Everyone").
  Future<void> deleteMessageForEveryone({
    required String chatId,
    required String messageId,
  }) async {
    _deletedForMeMessageIds.add(messageId);
    final chatRef = _chatRef(chatId);
    try {
      await chatRef.collection('messages').doc(messageId).delete();
    } catch (_) {}

    // Sync parent chat thread's lastMessage preview with the newest remaining message.
    try {
      final latestSnap = await chatRef
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (latestSnap.docs.isEmpty) {
        await chatRef.update({
          'lastMessage': '',
          'lastSenderUid': '',
          'lastSenderName': '',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final m = DirectChatMessage.fromFirestore(latestSnap.docs.first);
        final preview = m.text.isNotEmpty
            ? (m.text.length > 120 ? m.text.substring(0, 120) : m.text)
            : (m.hasImage ? '📷 Shared an image' : '');
        await chatRef.update({
          'lastMessage': preview,
          'lastSenderUid': m.senderUid,
          'lastSenderName': m.senderName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  Future<void> markChatRead(String chatId) async {
    final uid = currentUid;
    try {
      await _chatRef(chatId).update({
        'unreadBy': FieldValue.arrayRemove([uid]),
        'unreadCounts.$uid': 0,
      });
    } catch (_) {}
  }

  /// Marks all given chat threads read for the current user immediately.
  Future<void> markAllChatsRead(List<String> chatIds) async {
    if (chatIds.isEmpty) return;
    final uid = currentUid;
    final batch = _db.batch();
    for (final chatId in chatIds) {
      batch.update(_chatRef(chatId), {
        'unreadBy': FieldValue.arrayRemove([uid]),
        'unreadCounts.$uid': 0,
      });
    }
    try {
      await batch.commit();
    } catch (_) {
      for (final chatId in chatIds) {
        await markChatRead(chatId);
      }
    }
  }

  Future<void> sendMessage({
    required String friendUid,
    required String senderName,
    String text = '',
    String? imageBase64,
    String? msgType,
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

    final effectiveType = msgType ?? (hasImage ? 'image' : 'text');
    final preview = trimmed.isNotEmpty ? trimmed : '📷 Shared an image';

    final batch = _db.batch();
    batch.set(chatRef.collection('messages').doc(), {
      'senderUid': meUid,
      'senderName': senderName,
      'text': trimmed,
      if (hasImage) 'imageBase64': imageBase64,
      'msgType': effectiveType,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(chatRef, {
      'lastMessage': preview.length > 120 ? preview.substring(0, 120) : preview,
      'lastSenderUid': meUid,
      'lastSenderName': senderName,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadBy': FieldValue.arrayUnion([friendUid]),
      'unreadCounts.$friendUid': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Writes a structured voice call log entry directly into the 1-on-1 friend chat.
  Future<void> logCallInChat({
    required String friendUid,
    required String senderName,
    required String summary,
  }) async {
    try {
      await sendMessage(
        friendUid: friendUid,
        senderName: senderName,
        text: summary,
        msgType: 'call',
      );
    } catch (_) {}
  }
}
