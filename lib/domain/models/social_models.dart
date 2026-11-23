import 'package:cloud_firestore/cloud_firestore.dart';

class FriendEntry {
  const FriendEntry({
    required this.friendUid,
    required this.nickname,
    required this.avatarId,
    this.photoBase64,
    required this.status,
    this.since,
  });

  final String friendUid;
  final String nickname;
  final String avatarId;
  final String? photoBase64;
  final String status;
  final DateTime? since;

  factory FriendEntry.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return FriendEntry(
      friendUid: data['friendUid'] as String? ?? doc.id,
      nickname: data['nickname'] as String? ?? 'Friend',
      avatarId: data['avatarId'] as String? ?? 'fox',
      photoBase64: data['photoBase64'] as String?,
      status: data['status'] as String? ?? 'accepted',
      since: data['since'] is Timestamp
          ? (data['since'] as Timestamp).toDate()
          : null,
    );
  }
}

class BlockedUserEntry {
  const BlockedUserEntry({
    required this.blockedUid,
    required this.nickname,
    required this.avatarId,
    this.createdAt,
  });

  final String blockedUid;
  final String nickname;
  final String avatarId;
  final DateTime? createdAt;

  factory BlockedUserEntry.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawName = (data['nickname'] as String?)?.trim() ?? '';
    final rawAvatar = (data['avatarId'] as String?)?.trim() ?? '';
    return BlockedUserEntry(
      blockedUid:
          data['blockedUid'] as String? ?? data['uid'] as String? ?? doc.id,
      nickname: rawName.isNotEmpty ? rawName : 'Blocked Player',
      avatarId: rawAvatar.isNotEmpty ? rawAvatar : 'fox',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.senderAvatar,
    required this.receiverUid,
    required this.receiverName,
    required this.receiverAvatar,
    required this.status,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String senderUid;
  final String senderName;
  final String senderAvatar;
  final String receiverUid;
  final String receiverName;
  final String receiverAvatar;
  final String status;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isPending => status == 'pending';
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory FriendRequest.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return FriendRequest(
      id: doc.id,
      senderUid: data['senderUid'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Player',
      senderAvatar: data['senderAvatar'] as String? ?? 'astro',
      receiverUid: data['receiverUid'] as String? ?? '',
      receiverName: data['receiverName'] as String? ?? 'Player',
      receiverAvatar: data['receiverAvatar'] as String? ?? 'fox',
      status: data['status'] as String? ?? 'pending',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      expiresAt: data['expiresAt'] is Timestamp
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class FriendChallenge {
  const FriendChallenge({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.senderAvatar,
    required this.senderEmoji,
    required this.receiverUid,
    required this.receiverName,
    required this.mode,
    required this.boardSize,
    required this.bestOf,
    required this.roomId,
    required this.status,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String senderUid;
  final String senderName;
  final String senderAvatar;
  final String senderEmoji;
  final String receiverUid;
  final String receiverName;
  final String mode;
  final int boardSize;
  final int bestOf;
  final String roomId;
  final String status;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory FriendChallenge.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return FriendChallenge(
      id: doc.id,
      senderUid: data['senderUid'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Player',
      senderAvatar: data['senderAvatar'] as String? ?? 'astro',
      senderEmoji: data['senderEmoji'] as String? ?? '❌',
      receiverUid: data['receiverUid'] as String? ?? '',
      receiverName: data['receiverName'] as String? ?? 'Friend',
      mode: data['mode'] as String? ?? 'classic',
      boardSize: (data['boardSize'] as num?)?.toInt() ?? 3,
      bestOf: (data['bestOf'] as num?)?.toInt() ?? 3,
      roomId: data['roomId'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      expiresAt: data['expiresAt'] is Timestamp
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class DirectChatSummary {
  const DirectChatSummary({
    required this.chatId,
    required this.participants,
    required this.lastMessage,
    required this.lastSenderUid,
    this.lastSenderName = '',
    required this.unreadBy,
    this.unreadCounts = const <String, int>{},
    this.lastMessageAt,
  });

  final String chatId;
  final List<String> participants;
  final String lastMessage;
  final String lastSenderUid;
  final String lastSenderName;
  final List<String> unreadBy;
  final Map<String, int> unreadCounts;
  final DateTime? lastMessageAt;

  int unreadCountFor(String uid) {
    final c = unreadCounts[uid] ?? 0;
    if (c > 0) return c;
    return unreadBy.contains(uid) ? 1 : 0;
  }

  bool isUnreadFor(String uid) => unreadCountFor(uid) > 0;

  String otherParticipantUid(String myUid) =>
      participants.firstWhere((p) => p != myUid, orElse: () => '');

  factory DirectChatSummary.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawCounts = data['unreadCounts'];
    final counts = <String, int>{};
    if (rawCounts is Map) {
      for (final entry in rawCounts.entries) {
        counts[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    return DirectChatSummary(
      chatId: doc.id,
      participants: (data['participants'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastSenderUid: data['lastSenderUid'] as String? ?? '',
      lastSenderName: data['lastSenderName'] as String? ?? '',
      unreadBy: (data['unreadBy'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      unreadCounts: counts,
      lastMessageAt: data['lastMessageAt'] is Timestamp
          ? (data['lastMessageAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class DirectChatMessage {
  const DirectChatMessage({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.text,
    this.imageBase64,
    this.msgType = 'text',
    this.createdAt,
  });

  final String id;
  final String senderUid;
  final String senderName;
  final String text;
  final String? imageBase64;
  final String msgType; // 'text' | 'image' | 'call'
  final DateTime? createdAt;

  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;
  bool get isCallLog => msgType == 'call' || text.startsWith('📞');

  factory DirectChatMessage.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return DirectChatMessage(
      id: doc.id,
      senderUid: data['senderUid'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Player',
      text: data['text'] as String? ?? '',
      imageBase64: data['imageBase64'] as String?,
      msgType: data['msgType'] as String? ?? 'text',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class VoiceCallSession {
  const VoiceCallSession({
    required this.callId,
    required this.callerUid,
    required this.calleeUid,
    required this.callerName,
    required this.callerAvatar,
    required this.calleeName,
    required this.status,
    this.roomId,
    this.offer,
    this.answer,
    this.createdAt,
  });

  final String callId;
  final String callerUid;
  final String calleeUid;
  final String callerName;
  final String callerAvatar;
  final String calleeName;
  final String status; // ringing | active | ended | declined | missed
  final String? roomId;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final DateTime? createdAt;

  bool get isRinging => status == 'ringing';
  bool get isActive => status == 'active';

  factory VoiceCallSession.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return VoiceCallSession(
      callId: doc.id,
      callerUid: data['callerUid'] as String? ?? '',
      calleeUid: data['calleeUid'] as String? ?? '',
      callerName: data['callerName'] as String? ?? 'Player',
      callerAvatar: data['callerAvatar'] as String? ?? 'astro',
      calleeName: data['calleeName'] as String? ?? 'Friend',
      status: data['status'] as String? ?? 'ended',
      roomId: data['roomId'] as String?,
      offer: data['offer'] is Map<String, dynamic>
          ? data['offer'] as Map<String, dynamic>
          : null,
      answer: data['answer'] is Map<String, dynamic>
          ? data['answer'] as Map<String, dynamic>
          : null,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class RivalryStats {
  const RivalryStats({
    required this.rivalryId,
    required this.playerUids,
    required this.winsByPlayer,
    required this.draws,
    required this.totalMatches,
    required this.currentStreakOwner,
    required this.currentStreak,
    required this.bestStreak,
    this.lastMatchAt,
  });

  final String rivalryId;
  final List<String> playerUids;
  final Map<String, int> winsByPlayer;
  final int draws;
  final int totalMatches;
  final String currentStreakOwner;
  final int currentStreak;
  final int bestStreak;
  final DateTime? lastMatchAt;

  int winsFor(String uid) => winsByPlayer[uid] ?? 0;

  factory RivalryStats.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawWins = data['winsByPlayer'];
    final winsMap = <String, int>{};
    if (rawWins is Map) {
      for (final entry in rawWins.entries) {
        winsMap[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    return RivalryStats(
      rivalryId: doc.id,
      playerUids: (data['playerUids'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      winsByPlayer: winsMap,
      draws: (data['draws'] as num?)?.toInt() ?? 0,
      totalMatches: (data['totalMatches'] as num?)?.toInt() ?? 0,
      currentStreakOwner: data['currentStreakOwner'] as String? ?? '',
      currentStreak: (data['currentStreak'] as num?)?.toInt() ?? 0,
      bestStreak: (data['bestStreak'] as num?)?.toInt() ?? 0,
      lastMatchAt: data['lastMatchAt'] is Timestamp
          ? (data['lastMatchAt'] as Timestamp).toDate()
          : null,
    );
  }
}

enum LeaderboardMetric {
  wins('wins', 'Wins'),
  tournamentsWon('tournamentsWon', 'Trophies'),
  bestStreak('bestStreak', 'Streak'),
  blitzWins('blitzWins', 'Blitz');

  const LeaderboardMetric(this.field, this.label);
  final String field;
  final String label;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.publicNickname,
    required this.avatarId,
    this.photoBase64,
    required this.wins,
    required this.tournamentsWon,
    required this.bestStreak,
    required this.blitzWins,
    required this.optIn,
  });

  final String uid;
  final String publicNickname;
  final String avatarId;
  final String? photoBase64;
  final int wins;
  final int tournamentsWon;
  final int bestStreak;
  final int blitzWins;
  final bool optIn;

  int scoreFor(LeaderboardMetric metric) {
    switch (metric) {
      case LeaderboardMetric.wins:
        return wins;
      case LeaderboardMetric.tournamentsWon:
        return tournamentsWon;
      case LeaderboardMetric.bestStreak:
        return bestStreak;
      case LeaderboardMetric.blitzWins:
        return blitzWins;
    }
  }

  factory LeaderboardEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return LeaderboardEntry(
      uid: doc.id,
      publicNickname: data['publicNickname'] as String? ?? 'Player',
      avatarId: data['avatarId'] as String? ?? 'astro',
      photoBase64: data['photoBase64'] as String?,
      wins: (data['wins'] as num?)?.toInt() ?? 0,
      tournamentsWon: (data['tournamentsWon'] as num?)?.toInt() ?? 0,
      bestStreak: (data['bestStreak'] as num?)?.toInt() ?? 0,
      blitzWins: (data['blitzWins'] as num?)?.toInt() ?? 0,
      optIn: data['optIn'] == true,
    );
  }
}

class MatchSummary {
  const MatchSummary({
    required this.matchId,
    required this.roomId,
    required this.players,
    required this.playerNames,
    required this.gameMode,
    required this.boardSize,
    required this.hostWins,
    required this.guestWins,
    required this.draws,
    required this.finalWinnerUid,
    required this.finalStatus,
    this.completedAt,
  });

  final String matchId;
  final String roomId;
  final List<String> players;
  final Map<String, String> playerNames;
  final String gameMode;
  final int boardSize;
  final int hostWins;
  final int guestWins;
  final int draws;
  final String finalWinnerUid;
  final String finalStatus;
  final DateTime? completedAt;

  factory MatchSummary.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawNames = data['playerNames'];
    final names = <String, String>{};
    if (rawNames is Map) {
      for (final e in rawNames.entries) {
        names[e.key.toString()] = e.value.toString();
      }
    }
    return MatchSummary(
      matchId: doc.id,
      roomId: data['roomId'] as String? ?? '',
      players: (data['players'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      playerNames: names,
      gameMode: data['gameMode'] as String? ?? 'classic',
      boardSize: (data['boardSize'] as num?)?.toInt() ?? 3,
      hostWins: (data['hostWins'] as num?)?.toInt() ?? 0,
      guestWins: (data['guestWins'] as num?)?.toInt() ?? 0,
      draws: (data['draws'] as num?)?.toInt() ?? 0,
      finalWinnerUid: data['finalWinnerUid'] as String? ?? '',
      finalStatus: data['finalStatus'] as String? ?? 'won',
      completedAt: data['completedAt'] is Timestamp
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
    );
  }
}
