import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/game_engine.dart';
import '../../domain/models/social_models.dart';
import '../../domain/models/user_profile.dart';

/// Manages player profile, private preferences, verified stats, achievements & trophies.
class ProfileRepository {
  ProfileRepository({
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

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _prefsRef(String uid) =>
      _userRef(uid).collection('private').doc('preferences');

  /// Ensures new or legacy anonymous accounts have a valid profile + friend code.
  Future<UserProfile> ensureProfile() async {
    final uid = currentUid;
    final ref = _userRef(uid);
    final existing = await ref.get();
    if (existing.exists && existing.data() != null) {
      final profile = UserProfile.fromFirestore(existing);
      if (profile.friendCode.isNotEmpty) return profile;
    }

    // Generate collision-checked friendCode.
    String friendCode = '';
    for (var i = 0; i < 6; i++) {
      final candidate = GameEngine.generateFriendCode();
      final codeRef = _db.collection('friendCodes').doc(candidate);
      try {
        await _db.runTransaction((tx) async {
          final snap = await tx.get(codeRef);
          if (snap.exists) throw StateError('collision');
          tx.set(codeRef, {
            'uid': uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
        });
        friendCode = candidate;
        break;
      } on StateError {
        continue;
      }
    }
    if (friendCode.isEmpty) {
      friendCode = GameEngine.generateFriendCode();
    }

    final defaultName = 'Player_${uid.substring(0, 4).toUpperCase()}';
    await ref.set({
      'nickname': existing.data()?['nickname'] ?? defaultName,
      'avatarId': existing.data()?['avatarId'] ?? 'astro',
      'preferredEmoji': existing.data()?['preferredEmoji'] ?? '❌',
      'friendCode': friendCode,
      'publicProfileEnabled': existing.data()?['publicProfileEnabled'] ?? true,
      'leaderboardOptIn': existing.data()?['leaderboardOptIn'] ?? true,
      'createdAt':
          existing.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final created = await ref.get();
    return UserProfile.fromFirestore(created);
  }

  Stream<UserProfile?> watchProfile(String uid) {
    return _userRef(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return UserProfile.fromFirestore(snap);
    });
  }

  Future<UserProfile?> getProfile(String uid) async {
    final snap = await _userRef(uid).get();
    if (!snap.exists || snap.data() == null) return null;
    return UserProfile.fromFirestore(snap);
  }

  Future<void> updateProfile({
    required String nickname,
    required String avatarId,
    required String preferredEmoji,
    required bool publicProfileEnabled,
    required bool leaderboardOptIn,
  }) async {
    final error = GameEngine.validateNickname(nickname);
    if (error != null) throw Exception(error);
    final uid = currentUid;
    await _userRef(uid).update({
      'nickname': nickname.trim(),
      'avatarId': avatarId,
      'preferredEmoji': preferredEmoji,
      'publicProfileEnabled': publicProfileEnabled,
      'leaderboardOptIn': leaderboardOptIn,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> fetchPrivatePreferences() async {
    final snap = await _prefsRef(currentUid).get();
    return snap.data();
  }

  Future<void> savePrivatePreferences(Map<String, dynamic> prefs) async {
    await _prefsRef(currentUid).set(
      {...prefs, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Stream<PlayerStats> watchStats(String uid) {
    return _db
        .collection('stats')
        .doc(uid)
        .snapshots()
        .map(PlayerStats.fromFirestore);
  }

  Stream<List<UserAchievement>> watchAchievements(String uid) {
    return _userRef(uid)
        .collection('achievements')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(UserAchievement.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<UserTrophy>> watchTrophies(String uid) {
    return _userRef(uid)
        .collection('trophies')
        .orderBy('awardedAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(UserTrophy.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<MatchSummary>> watchRecentMatches(String uid, {int limit = 15}) {
    return _db
        .collection('matches')
        .where('players', arrayContains: uid)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(MatchSummary.fromFirestore)
          .toList(growable: true);
      list.sort(
        (a, b) => (b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      return list;
    });
  }
}
