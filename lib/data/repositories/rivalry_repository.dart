import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/game_engine.dart';
import '../../domain/models/social_models.dart';

/// Streams server-verified head-to-head rivalry statistics & match history.
class RivalryRepository {
  RivalryRepository({FirebaseFirestore? firestore, String? databaseId})
      : _db = firestore ??
            (databaseId != null
                ? FirebaseFirestore.instanceFor(
                    app: Firebase.app(),
                    databaseId: databaseId,
                  )
                : FirebaseFirestore.instance);

  final FirebaseFirestore _db;

  Stream<RivalryStats?> watchRivalry(String uidA, String uidB) {
    final id = GameEngine.rivalryIdFor(uidA, uidB);
    return _db.collection('rivalries').doc(id).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return RivalryStats.fromFirestore(snap);
    });
  }

  Stream<List<MatchSummary>> watchHeadToHeadMatches(
    String uidA,
    String uidB, {
    int limit = 20,
  }) {
    return _db
        .collection('matches')
        .where('players', arrayContains: uidA)
        .limit(40)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(MatchSummary.fromFirestore)
          .where((m) => m.players.contains(uidB))
          .toList(growable: true);
      list.sort(
        (a, b) => (b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      return list.take(limit).toList(growable: false);
    });
  }
}
