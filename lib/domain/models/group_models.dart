import 'package:cloud_firestore/cloud_firestore.dart';

/// Individual member standing inside a Friend Group (up to 5 members).
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

/// Active or completed 1v1 match inside a Friend Group (qualifying match or Final Match).
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
  final String status; // 'pending' | 'playing' | 'finished'
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

/// Friend Group (up to 5 members added via Friend Codes) supporting
/// 2-player matches, Final Championship Match for the Melow Challenge Champion Cup,
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
    this.cupName = 'Melow Challenge Champion Cup',
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
  final String cupName;
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

  /// Returns sorted Group Individual Rankings for all members in the group.
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
      cupName: d['cupName'] as String? ?? 'Melow Challenge Champion Cup',
      activeMatch: active,
      winsByUid: parseIntMap(d['winsByUid']),
      lossesByUid: parseIntMap(d['lossesByUid']),
      drawsByUid: parseIntMap(d['drawsByUid']),
      cupsByUid: parseIntMap(d['cupsByUid']),
      lastMessage: d['lastMessage'] as String? ?? '',
      lastSenderUid: d['lastSenderUid'] as String? ?? '',
      lastSenderName: d['lastSenderName'] as String? ?? '',
      lastMessageAt: d['lastMessageAt'] is Timestamp
          ? (d['lastMessageAt'] as Timestamp).toDate()
          : null,
      clearedAtBy: clearedMap,
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}
