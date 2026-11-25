import 'package:cloud_firestore/cloud_firestore.dart';

/// Individual member standing inside a Friend Group (2 to 5 members).
class GroupMemberStanding {
  const GroupMemberStanding({
    required this.uid,
    required this.nickname,
    required this.avatarId,
    this.played = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.cups = 0,
  });

  final String uid;
  final String nickname;
  final String avatarId;
  final int played;
  final int wins;
  final int losses;
  final int draws;
  final int cups;

  int get points => (wins * 3) + draws;
}

/// A single tournament fixture match inside a Friend Group (`User1 vs User2`).
/// The roomCode and Play button are shown ONLY to the two participants (`player1Uid` and `player2Uid`)!
class GroupFixture {
  const GroupFixture({
    required this.id,
    required this.matchNumber,
    required this.player1Uid,
    required this.player1Name,
    required this.player2Uid,
    required this.player2Name,
    this.roomId = '',
    this.status = 'pending', // 'pending' | 'playing' | 'finished'
    this.winnerUid = '',
    this.winnerName = '',
    this.resultText = '',
    this.isFinalMatch = false,
  });

  final String id;
  final int matchNumber;
  final String player1Uid;
  final String player1Name;
  final String player2Uid;
  final String player2Name;
  final String roomId;
  final String status; // 'pending' | 'playing' | 'finished'
  final String winnerUid;
  final String winnerName;
  final String resultText;
  final bool isFinalMatch;

  bool isParticipant(String uid) => uid == player1Uid || uid == player2Uid;

  String get statusLabel {
    if (status == 'finished') {
      if (resultText.isNotEmpty) return resultText;
      if (winnerName.isNotEmpty) return 'Winner: $winnerName 🏆';
      return 'Draw';
    }
    if (status == 'playing') return 'Playing';
    return 'Ready to Play';
  }

  GroupFixture copyWith({
    String? roomId,
    String? status,
    String? winnerUid,
    String? winnerName,
    String? resultText,
  }) {
    return GroupFixture(
      id: id,
      matchNumber: matchNumber,
      player1Uid: player1Uid,
      player1Name: player1Name,
      player2Uid: player2Uid,
      player2Name: player2Name,
      roomId: roomId ?? this.roomId,
      status: status ?? this.status,
      winnerUid: winnerUid ?? this.winnerUid,
      winnerName: winnerName ?? this.winnerName,
      resultText: resultText ?? this.resultText,
      isFinalMatch: isFinalMatch,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'matchNumber': matchNumber,
        'player1Uid': player1Uid,
        'player1Name': player1Name,
        'player2Uid': player2Uid,
        'player2Name': player2Name,
        'roomId': roomId,
        'status': status,
        'winnerUid': winnerUid,
        'winnerName': winnerName,
        'resultText': resultText,
        'isFinalMatch': isFinalMatch,
      };

  factory GroupFixture.fromMap(Map<String, dynamic> map) {
    return GroupFixture(
      id: map['id'] as String? ?? 'M1',
      matchNumber: (map['matchNumber'] as num?)?.toInt() ?? 1,
      player1Uid: map['player1Uid'] as String? ?? '',
      player1Name: map['player1Name'] as String? ?? 'Player 1',
      player2Uid: map['player2Uid'] as String? ?? '',
      player2Name: map['player2Name'] as String? ?? 'Player 2',
      roomId: map['roomId'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      winnerUid: map['winnerUid'] as String? ?? '',
      winnerName: map['winnerName'] as String? ?? '',
      resultText: map['resultText'] as String? ?? '',
      isFinalMatch: map['isFinalMatch'] == true,
    );
  }
}

/// Active or completed 1v1 match inside a Friend Group (kept for legacy compatibility).
class GroupActiveMatch {
  const GroupActiveMatch({
    required this.roomId,
    required this.hostUid,
    required this.hostName,
    required this.guestUid,
    required this.guestName,
    required this.mode,
    required this.boardSize,
    required this.bestOf,
    required this.isFinalMatch,
    required this.status,
    this.winnerUid = '',
    this.winnerName = '',
  });

  final String roomId;
  final String hostUid;
  final String hostName;
  final String guestUid;
  final String guestName;
  final String mode;
  final int boardSize;
  final int bestOf;
  final bool isFinalMatch;
  final String status;
  final String winnerUid;
  final String winnerName;

  Map<String, dynamic> toMap() => {
        'roomId': roomId,
        'hostUid': hostUid,
        'hostName': hostName,
        'guestUid': guestUid,
        'guestName': guestName,
        'mode': mode,
        'boardSize': boardSize,
        'bestOf': bestOf,
        'isFinalMatch': isFinalMatch,
        'status': status,
        'winnerUid': winnerUid,
        'winnerName': winnerName,
      };

  factory GroupActiveMatch.fromMap(Map<String, dynamic> map) {
    return GroupActiveMatch(
      roomId: map['roomId'] as String? ?? '',
      hostUid: map['hostUid'] as String? ?? '',
      hostName: map['hostName'] as String? ?? 'Player 1',
      guestUid: map['guestUid'] as String? ?? '',
      guestName: map['guestName'] as String? ?? 'Player 2',
      mode: map['mode'] as String? ?? 'classic',
      boardSize: (map['boardSize'] as num?)?.toInt() ?? 3,
      bestOf: (map['bestOf'] as num?)?.toInt() ?? 3,
      isFinalMatch: map['isFinalMatch'] == true,
      status: map['status'] as String? ?? 'pending',
      winnerUid: map['winnerUid'] as String? ?? '',
      winnerName: map['winnerName'] as String? ?? '',
    );
  }
}

/// Friend Group (2 to 5 members joining via host's Friend Code) with
/// auto-generated tournament fixtures, participant-only room code visibility,
/// Final Match for the Melow Challenge Champion Cup, Champion & Runner-Up summary,
/// Group Individual Rankings, Group Chat, and Group Voice Calls.
class FriendGroup {
  const FriendGroup({
    required this.id,
    required this.name,
    required this.creatorUid,
    this.hostFriendCode = '',
    this.maxMembers = 5,
    required this.memberUids,
    required this.memberNames,
    required this.memberAvatars,
    required this.tournamentStatus,
    this.championUid = '',
    this.championName = '',
    this.runnerUpUid = '',
    this.runnerUpName = '',
    this.cupName = 'Melow Challenge Champion Cup',
    this.fixtures = const <GroupFixture>[],
    this.activeMatch,
    this.winsByUid = const <String, int>{},
    this.lossesByUid = const <String, int>{},
    this.drawsByUid = const <String, int>{},
    this.cupsByUid = const <String, int>{},
    this.lastMessage = '',
    this.lastSenderUid = '',
    this.lastSenderName = '',
    this.lastMessageAt,
    this.clearedAtBy = const <String, DateTime>{},
    this.createdAt,
  });

  static const int maxAllowedMembers = 5;

  final String id;
  final String name;
  final String creatorUid;
  final String hostFriendCode;
  final int maxMembers;
  final List<String> memberUids;
  final Map<String, String> memberNames;
  final Map<String, String> memberAvatars;
  final String tournamentStatus; // 'active' | 'final_ready' | 'completed'
  final String championUid;
  final String championName;
  final String runnerUpUid;
  final String runnerUpName;
  final String cupName;
  final List<GroupFixture> fixtures;
  final GroupActiveMatch? activeMatch;
  final Map<String, int> winsByUid;
  final Map<String, int> lossesByUid;
  final Map<String, int> drawsByUid;
  final Map<String, int> cupsByUid;
  final String lastMessage;
  final String lastSenderUid;
  final String lastSenderName;
  final DateTime? lastMessageAt;
  final Map<String, DateTime> clearedAtBy;
  final DateTime? createdAt;

  /// Returns Group Members / Individual Rankings:
  /// - When no matches have been played yet (all members at 0 played and 0 cups),
  ///   preserves the exact join order `1, 2, 3, 4, 5` (`memberUids` order).
  /// - Once matches are played or the tournament completes, sorts by Cups, Points, Wins, and Nickname.
  List<GroupMemberStanding> get rankings {
    final list = <GroupMemberStanding>[];
    for (final uid in memberUids) {
      final w = winsByUid[uid] ?? 0;
      final l = lossesByUid[uid] ?? 0;
      final d = drawsByUid[uid] ?? 0;
      final c = cupsByUid[uid] ?? 0;
      list.add(
        GroupMemberStanding(
          uid: uid,
          nickname: memberNames[uid] ?? 'Player',
          avatarId: memberAvatars[uid] ?? 'astro',
          played: w + l + d,
          wins: w,
          losses: l,
          draws: d,
          cups: c,
        ),
      );
    }
    final anyPlayedOrCups =
        list.any((m) => m.played > 0 || m.cups > 0) ||
        tournamentStatus == 'completed';
    if (!anyPlayedOrCups) {
      return list;
    }
    list.sort((a, b) {
      final cupCmp = b.cups.compareTo(a.cups);
      if (cupCmp != 0) return cupCmp;
      final ptCmp = b.points.compareTo(a.points);
      if (ptCmp != 0) return ptCmp;
      final winCmp = b.wins.compareTo(a.wins);
      if (winCmp != 0) return winCmp;
      return a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase());
    });
    return list;
  }

  /// Resolved Runner-Up name from either explicit `runnerUpName` or 2nd place in rankings.
  String get effectiveRunnerUpName {
    if (runnerUpName.trim().isNotEmpty) return runnerUpName;
    final r = rankings;
    for (final s in r) {
      if (s.uid != championUid) return s.nickname;
    }
    return r.length >= 2 ? r[1].nickname : '';
  }

  factory FriendGroup.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final members = (d['memberUids'] as List? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);

    Map<String, String> parseStringMap(dynamic raw) {
      if (raw is! Map) return const <String, String>{};
      return {
        for (final entry in raw.entries)
          entry.key.toString(): entry.value?.toString() ?? '',
      };
    }

    Map<String, int> parseIntMap(dynamic raw) {
      if (raw is! Map) return const <String, int>{};
      return {
        for (final entry in raw.entries)
          entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
      };
    }

    final rawCleared = d['clearedAtBy'];
    final clearedMap = <String, DateTime>{};
    if (rawCleared is Map) {
      for (final entry in rawCleared.entries) {
        if (entry.value is Timestamp) {
          clearedMap[entry.key.toString()] =
              (entry.value as Timestamp).toDate();
        }
      }
    }

    final rawFixtures = d['fixtures'];
    final fixtureList = <GroupFixture>[];
    if (rawFixtures is List) {
      for (final item in rawFixtures) {
        if (item is Map) {
          fixtureList.add(
            GroupFixture.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final rawMatch = d['activeMatch'];
    final active = rawMatch is Map
        ? GroupActiveMatch.fromMap(Map<String, dynamic>.from(rawMatch))
        : null;

    return FriendGroup(
      id: doc.id,
      name: d['name'] as String? ?? 'Melow Squad',
      creatorUid: d['creatorUid'] as String? ?? '',
      hostFriendCode: d['hostFriendCode'] as String? ?? doc.id,
      maxMembers: ((d['maxMembers'] as num?)?.toInt() ?? 5).clamp(2, 5),
      memberUids: members,
      memberNames: parseStringMap(d['memberNames']),
      memberAvatars: parseStringMap(d['memberAvatars']),
      tournamentStatus: d['tournamentStatus'] as String? ?? 'active',
      championUid: d['championUid'] as String? ?? '',
      championName: d['championName'] as String? ?? '',
      runnerUpUid: d['runnerUpUid'] as String? ?? '',
      runnerUpName: d['runnerUpName'] as String? ?? '',
      cupName: d['cupName'] as String? ?? 'Melow Challenge Champion Cup',
      fixtures: fixtureList,
      activeMatch: active,
      winsByUid: parseIntMap(d['winsByUid']),
      lossesByUid: parseIntMap(d['lossesByUid']),
      drawsByUid: parseIntMap(d['drawsByUid']),
      cupsByUid: parseIntMap(d['cupsByUid']),
      lastMessage: d['lastMessage'] as String? ?? '',
      lastSenderUid: d['lastSenderUid'] as String? ?? '',
      lastSenderName: d['lastSenderName'] as String? ?? '',
      lastMessageAt: dataTimestamp(d['lastMessageAt']),
      clearedAtBy: clearedMap,
      createdAt: dataTimestamp(d['createdAt']),
    );
  }

  static DateTime? dataTimestamp(dynamic raw) =>
      raw is Timestamp ? raw.toDate() : null;
}
