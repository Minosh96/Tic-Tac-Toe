import 'package:cloud_firestore/cloud_firestore.dart';

class FriendEntry {
  const FriendEntry({
    required this.friendUid,
    required this.nickname,
    required this.avatarId,
    required this.status,
    this.since,
  });

  final String friendUid;
  final String nickname;
  final String avatarId;
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
      status: data['status'] as String? ?? 'accepted',
      since: data['since'] is Timestamp
          ? (data['since'] as Timestamp).toDate()
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
  final String status; // pending | accepted | declined | cancelled
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
  final String status; // pending | accepted | declined | cancelled
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
  bestStreak('bestStreak', 'Best Streak'),
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
    required this.wins,
    required this.tournamentsWon,
    required this.bestStreak,
    required this.blitzWins,
    required this.optIn,
  });

  final String uid;
  final String publicNickname;
  final String avatarId;
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
  final String finalStatus; // 'won' | 'draw'
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
