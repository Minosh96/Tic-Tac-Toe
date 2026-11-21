import 'package:cloud_firestore/cloud_firestore.dart';

/// Player public profile stored at `users/{uid}`.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.nickname,
    required this.avatarId,
    this.photoBase64,
    required this.preferredEmoji,
    required this.friendCode,
    required this.publicProfileEnabled,
    required this.leaderboardOptIn,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String nickname;
  final String avatarId;
  final String? photoBase64;
  final String preferredEmoji;
  final String friendCode;
  final bool publicProfileEnabled;
  final bool leaderboardOptIn;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasCustomPhoto => photoBase64 != null && photoBase64!.isNotEmpty;

  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return UserProfile(
      uid: doc.id,
      nickname: data['nickname'] as String? ?? 'Player',
      avatarId: data['avatarId'] as String? ?? 'astro',
      photoBase64: data['photoBase64'] as String?,
      preferredEmoji: data['preferredEmoji'] as String? ?? '❌',
      friendCode: data['friendCode'] as String? ?? '',
      publicProfileEnabled: data['publicProfileEnabled'] != false,
      leaderboardOptIn: data['leaderboardOptIn'] != false,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

/// Verified player stats stored at `stats/{uid}`.
class PlayerStats {
  const PlayerStats({
    this.gamesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.tournamentsWon = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.blitzWins = 0,
    this.megaWins = 0,
    this.trophyCount = 0,
  });

  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int tournamentsWon;
  final int currentStreak;
  final int bestStreak;
  final int blitzWins;
  final int megaWins;
  final int trophyCount;

  double get winRate => gamesPlayed == 0 ? 0.0 : (wins / gamesPlayed) * 100.0;

  int get level => 1 + (wins ~/ 3) + (tournamentsWon * 2);

  String get rankBadge {
    if (tournamentsWon >= 10 || wins >= 50) return '👑 Melow Legend';
    if (tournamentsWon >= 3 || wins >= 25) return '💎 Grand Master';
    if (wins >= 10) return '🔥 Strategist';
    if (wins >= 3) return '⭐ Rising Challenger';
    return '🎮 Rookie';
  }

  factory PlayerStats.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return const PlayerStats();
    return PlayerStats(
      gamesPlayed: (data['gamesPlayed'] as num?)?.toInt() ?? 0,
      wins: (data['wins'] as num?)?.toInt() ?? 0,
      losses: (data['losses'] as num?)?.toInt() ?? 0,
      draws: (data['draws'] as num?)?.toInt() ?? 0,
      tournamentsWon: (data['tournamentsWon'] as num?)?.toInt() ?? 0,
      currentStreak: (data['currentStreak'] as num?)?.toInt() ?? 0,
      bestStreak: (data['bestStreak'] as num?)?.toInt() ?? 0,
      blitzWins: (data['blitzWins'] as num?)?.toInt() ?? 0,
      megaWins: (data['megaWins'] as num?)?.toInt() ?? 0,
      trophyCount: (data['trophyCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class UserAchievement {
  const UserAchievement({
    required this.achievementId,
    required this.progress,
    required this.verified,
    this.unlockedAt,
  });

  final String achievementId;
  final int progress;
  final bool verified;
  final DateTime? unlockedAt;

  bool get isUnlocked => unlockedAt != null && verified;

  factory UserAchievement.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return UserAchievement(
      achievementId: data['achievementId'] as String? ?? doc.id,
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      verified: data['verified'] == true,
      unlockedAt: data['unlockedAt'] is Timestamp
          ? (data['unlockedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class UserTrophy {
  const UserTrophy({
    required this.trophyId,
    required this.matchId,
    required this.title,
    this.awardedAt,
  });

  final String trophyId;
  final String matchId;
  final String title;
  final DateTime? awardedAt;

  factory UserTrophy.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return UserTrophy(
      trophyId: data['trophyId'] as String? ?? doc.id,
      matchId: data['matchId'] as String? ?? '',
      title: data['title'] as String? ?? 'Melow Cup',
      awardedAt: data['awardedAt'] is Timestamp
          ? (data['awardedAt'] as Timestamp).toDate()
          : null,
    );
  }
}
