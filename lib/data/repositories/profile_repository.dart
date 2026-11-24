import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../core/services/preferences_controller.dart';
import '../../core/services/push_notification_service.dart';
import '../../domain/game_engine.dart';
import '../../domain/models/social_models.dart';
import '../../domain/models/user_profile.dart';
import 'chat_repository.dart';

/// Manages player profile (including gallery photo), preferences, stats, achievements & trophies.
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

  Future<UserProfile> ensureProfile() async {
    final uid = currentUid;
    final ref = _userRef(uid);
    final existing = await ref.get();
    if (existing.exists && existing.data() != null) {
      final profile = UserProfile.fromFirestore(existing);
      if (profile.friendCode.isNotEmpty) return profile;
    }

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

    final defaultName = UserProfile.defaultSystemNicknameFor(uid);
    final rawVis = existing.data()?['profileVisibility'] as String?;
    final pubEnabled = existing.data()?['publicProfileEnabled'] != false;
    final vis = ProfileVisibility.fromId(rawVis, fallbackPublic: pubEnabled);
    await ref.set({
      'nickname': existing.data()?['nickname'] ?? defaultName,
      'avatarId': existing.data()?['avatarId'] ?? 'astro',
      'preferredEmoji': existing.data()?['preferredEmoji'] ?? '❌',
      'friendCode': friendCode,
      'publicProfileEnabled': vis == ProfileVisibility.public,
      'profileVisibility': vis.id,
      'hidePhotoGlobally': existing.data()?['hidePhotoGlobally'] == true,
      'hideNameGlobally': existing.data()?['hideNameGlobally'] == true,
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
    String? photoBase64,
    bool updatePhoto = false,
    required String preferredEmoji,
    required bool publicProfileEnabled,
    required bool leaderboardOptIn,
    ProfileVisibility? profileVisibility,
    bool? hidePhotoGlobally,
    bool? hideNameGlobally,
  }) async {
    final error = GameEngine.validateNickname(nickname);
    if (error != null) throw Exception(error);
    final uid = currentUid;
    final existingSnap = await _userRef(uid).get();
    final existingProfile = existingSnap.exists
        ? UserProfile.fromFirestore(existingSnap)
        : null;

    final effectiveVisibility = profileVisibility ??
        (publicProfileEnabled
            ? ProfileVisibility.public
            : (existingProfile?.profileVisibility == ProfileVisibility.private
                ? ProfileVisibility.private
                : ProfileVisibility.friends));
    final effectivePublicEnabled =
        effectiveVisibility == ProfileVisibility.public;
    final effectiveHidePhoto =
        hidePhotoGlobally ?? existingProfile?.hidePhotoGlobally ?? false;
    final effectiveHideName =
        hideNameGlobally ?? existingProfile?.hideNameGlobally ?? false;
    final effectivePhoto =
        updatePhoto ? photoBase64 : existingProfile?.photoBase64;

    final patch = <String, dynamic>{
      'nickname': nickname.trim(),
      'avatarId': avatarId,
      'preferredEmoji': preferredEmoji,
      'publicProfileEnabled': effectivePublicEnabled,
      'profileVisibility': effectiveVisibility.id,
      'hidePhotoGlobally': effectiveHidePhoto,
      'hideNameGlobally': effectiveHideName,
      'leaderboardOptIn': leaderboardOptIn,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (updatePhoto) {
      patch['photoBase64'] = photoBase64;
    }

    await _userRef(uid).update(patch);

    await _propagateVisibilityToFriendsAndLeaderboard(
      uid: uid,
      nickname: nickname.trim(),
      avatarId: avatarId,
      photoBase64: effectivePhoto,
      visibility: effectiveVisibility,
      hidePhotoGlobally: effectiveHidePhoto,
      hideNameGlobally: effectiveHideName,
      leaderboardOptIn: leaderboardOptIn,
    );
  }

  /// Deletes/resets the user's custom name, profile picture, or whole profile
  /// back to a default system profile (`Player_XXXX`) and removes custom data globally.
  Future<void> deleteOrResetProfile({
    required bool deleteName,
    required bool deletePhoto,
    ProfileVisibility? newVisibility,
  }) async {
    if (!deleteName && !deletePhoto && newVisibility == null) return;
    final uid = currentUid;
    final snap = await _userRef(uid).get();
    final current = snap.exists ? UserProfile.fromFirestore(snap) : null;

    final defaultName = UserProfile.defaultSystemNicknameFor(uid);
    final nextName = deleteName ? defaultName : (current?.nickname ?? defaultName);
    final nextAvatar = deletePhoto ? 'astro' : (current?.avatarId ?? 'astro');
    final String? nextPhoto = deletePhoto ? null : current?.photoBase64;
    final nextEmoji =
        (deleteName && deletePhoto) ? '❌' : (current?.preferredEmoji ?? '❌');
    final nextVisibility =
        newVisibility ?? current?.profileVisibility ?? ProfileVisibility.public;
    final nextPublic = nextVisibility == ProfileVisibility.public;
    final nextLbOptIn = current?.leaderboardOptIn ?? true;
    final nextHidePhoto = current?.hidePhotoGlobally ?? false;
    final nextHideName = current?.hideNameGlobally ?? false;

    await _userRef(uid).update({
      'nickname': nextName,
      'avatarId': nextAvatar,
      'photoBase64': nextPhoto,
      'preferredEmoji': nextEmoji,
      'publicProfileEnabled': nextPublic,
      'profileVisibility': nextVisibility.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _propagateVisibilityToFriendsAndLeaderboard(
      uid: uid,
      nickname: nextName,
      avatarId: nextAvatar,
      photoBase64: nextPhoto,
      visibility: nextVisibility,
      hidePhotoGlobally: nextHidePhoto,
      hideNameGlobally: nextHideName,
      leaderboardOptIn: nextLbOptIn,
    );
  }

  Future<void> _propagateVisibilityToFriendsAndLeaderboard({
    required String uid,
    required String nickname,
    required String avatarId,
    required String? photoBase64,
    required ProfileVisibility visibility,
    required bool hidePhotoGlobally,
    required bool hideNameGlobally,
    required bool leaderboardOptIn,
  }) async {
    final defaultName = UserProfile.defaultSystemNicknameFor(uid);
    final isPrivate = visibility == ProfileVisibility.private;
    final isPublic = visibility == ProfileVisibility.public;

    // Friends see custom name & photo when Public or Friends Only; default system identity when Private.
    final friendSideName = isPrivate ? defaultName : nickname;
    final friendSideAvatar = isPrivate ? 'astro' : avatarId;
    final String? friendSidePhoto = isPrivate ? null : photoBase64;

    try {
      final friendsSnap = await _userRef(uid).collection('friends').get();
      if (friendsSnap.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in friendsSnap.docs) {
          final friendUid = doc.id;
          final friendSideRef =
              _userRef(friendUid).collection('friends').doc(uid);
          batch.update(friendSideRef, {
            'nickname': friendSideName,
            'avatarId': friendSideAvatar,
            'photoBase64': friendSidePhoto,
          });
        }
        await batch.commit();
      }
    } catch (_) {
      try {
        final friendsSnap = await _userRef(uid).collection('friends').get();
        for (final doc in friendsSnap.docs) {
          try {
            await _userRef(doc.id).collection('friends').doc(uid).update({
              'nickname': friendSideName,
              'avatarId': friendSideAvatar,
              'photoBase64': friendSidePhoto,
            });
          } catch (_) {}
        }
      } catch (_) {}
    }

    // Global Leaderboard: never expose custom name or photo if hidden or not Public.
    final globalName =
        (!isPublic || hideNameGlobally) ? defaultName : nickname;
    final globalAvatar =
        (!isPublic || hidePhotoGlobally) ? 'astro' : avatarId;
    final String? globalPhoto =
        (!isPublic || hidePhotoGlobally) ? null : photoBase64;
    final globalOptIn = isPublic && leaderboardOptIn;

    try {
      final lbRef = _db.collection('leaderboardEntries').doc(uid);
      final lbSnap = await lbRef.get();
      if (lbSnap.exists) {
        await lbRef.update({
          'publicNickname': globalName,
          'avatarId': globalAvatar,
          'photoBase64': globalPhoto,
          'optIn': globalOptIn,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  /// Permanently deletes the current user's account, friends, chats, notifications,
  /// trophies, stats, and settings, then signs in as a brand-new anonymous player
  /// profile (`Player_XXXX`) without affecting other existing user profiles.
  Future<UserProfile> permanentlyDeleteAccountAndCreateNew({
    required PreferencesController preferences,
    required ChatRepository chatRepository,
  }) async {
    final uid = currentUid;
    final userRef = _userRef(uid);
    String friendCode = '';
    try {
      final snap = await userRef.get();
      friendCode = snap.data()?['friendCode'] as String? ?? '';
    } catch (_) {}

    // 1. Delete friendships on both sides (leaves friends' own user profiles completely untouched)
    try {
      final friendsSnap = await userRef.collection('friends').get();
      for (final doc in friendsSnap.docs) {
        final friendUid = doc.id;
        try {
          await _userRef(friendUid).collection('friends').doc(uid).delete();
        } catch (_) {}
        try {
          await doc.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}

    // 2. Delete blocked entries
    try {
      final blockedSnap = await userRef.collection('blocked').get();
      for (final doc in blockedSnap.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}

    // 3. Delete incoming & outgoing friend requests and game challenges (notifications)
    for (final field in const ['senderUid', 'receiverUid']) {
      try {
        final reqSnap = await _db
            .collection('friendRequests')
            .where(field, isEqualTo: uid)
            .get();
        for (final doc in reqSnap.docs) {
          try {
            await doc.reference.delete();
          } catch (_) {}
        }
      } catch (_) {}

      try {
        final chalSnap = await _db
            .collection('friendChallenges')
            .where(field, isEqualTo: uid)
            .get();
        for (final doc in chalSnap.docs) {
          try {
            await doc.reference.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }

    // 4. Delete all 1-on-1 chats, messages & cancel message notifications
    try {
      final chatsSnap = await _db
          .collection('chats')
          .where('participants', arrayContains: uid)
          .get();
      for (final chatDoc in chatsSnap.docs) {
        await PushNotificationService.cancelMessageNotification(chatDoc.id);
        try {
          final msgSnap = await chatDoc.reference.collection('messages').get();
          for (final m in msgSnap.docs) {
            try {
              await m.reference.delete();
            } catch (_) {}
          }
        } catch (_) {}
        try {
          await chatDoc.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}

    // 5. Delete call records & cancel call notifications
    for (final field in const ['callerUid', 'calleeUid']) {
      try {
        final callsSnap =
            await _db.collection('calls').where(field, isEqualTo: uid).get();
        for (final callDoc in callsSnap.docs) {
          await PushNotificationService.cancelCallNotification(callDoc.id);
          try {
            await callDoc.reference.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }

    // 6. Delete user subcollections (trophies, achievements, processedMatches, private)
    for (final sub in const [
      'trophies',
      'achievements',
      'processedMatches',
      'private',
    ]) {
      try {
        final snap = await userRef.collection(sub).get();
        for (final doc in snap.docs) {
          try {
            await doc.reference.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }

    // 7. Delete friendCode, leaderboardEntries, stats, and users/{uid}
    if (friendCode.isNotEmpty) {
      try {
        await _db.collection('friendCodes').doc(friendCode).delete();
      } catch (_) {}
    }
    try {
      await _db.collection('leaderboardEntries').doc(uid).delete();
    } catch (_) {}
    try {
      await _db.collection('stats').doc(uid).delete();
    } catch (_) {}
    try {
      await userRef.delete();
    } catch (_) {}

    // 8. Reset all local settings & caches
    chatRepository.resetLocalCaches();
    await preferences.resetAllSettingsToDefault();

    // 9. Delete Firebase Auth user (or sign out) and sign in with a brand-new anonymous UID
    try {
      await _auth.currentUser?.delete();
    } catch (_) {
      try {
        await _auth.signOut();
      } catch (_) {}
    }
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }

    // 10. Provision brand-new default system profile
    return ensureProfile();
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
        .asyncMap((statsSnap) async {
      final raw = PlayerStats.fromFirestore(statsSnap);
      try {
        final results = await Future.wait([
          _db
              .collection('matches')
              .where('players', arrayContains: uid)
              .limit(100)
              .get(),
          _userRef(uid).collection('trophies').limit(100).get(),
        ]);
        final matchSnap = results[0];
        final trophySnap = results[1];

        int histWins = 0;
        int histLosses = 0;
        int histDraws = 0;
        int histCups = 0;

        for (final doc in matchSnap.docs) {
          final d = doc.data();
          final players = (d['players'] as List? ?? const [])
              .map((e) => e.toString())
              .toList(growable: false);
          final hWins = (d['hostWins'] as num?)?.toInt() ?? 0;
          final gWins = (d['guestWins'] as num?)?.toInt() ?? 0;
          final mDraws = (d['draws'] as num?)?.toInt() ?? 0;
          final winnerUid = d['finalWinnerUid'] as String? ?? '';

          if (players.isNotEmpty && players.first == uid) {
            histWins += hWins;
            histLosses += gWins;
          } else {
            histWins += gWins;
            histLosses += hWins;
          }
          histDraws += mDraws;
          if (winnerUid == uid) histCups++;
        }

        final trophyCups = trophySnap.docs.length;
        final effectiveWins = raw.wins >= histWins ? raw.wins : histWins;
        final effectiveLosses =
            raw.losses >= histLosses ? raw.losses : histLosses;
        final effectiveDraws = raw.draws >= histDraws ? raw.draws : histDraws;
        final maxCups = histCups >= trophyCups ? histCups : trophyCups;
        final effectiveCups =
            raw.tournamentsWon >= maxCups ? raw.tournamentsWon : maxCups;
        final minPlayed = effectiveWins + effectiveLosses + effectiveDraws;
        final effectivePlayed =
            raw.gamesPlayed >= minPlayed ? raw.gamesPlayed : minPlayed;

        return PlayerStats(
          gamesPlayed: effectivePlayed,
          wins: effectiveWins,
          losses: effectiveLosses,
          draws: effectiveDraws,
          tournamentsWon: effectiveCups,
          currentStreak: raw.currentStreak,
          bestStreak: raw.bestStreak,
          blitzWins: raw.blitzWins,
          megaWins: raw.megaWins,
          trophyCount:
              raw.trophyCount >= effectiveCups ? raw.trophyCount : effectiveCups,
        );
      } catch (_) {
        return raw;
      }
    });
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
