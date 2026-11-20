import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/models/social_models.dart';

class LeaderboardPageResult {
  const LeaderboardPageResult({
    required this.entries,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<LeaderboardEntry> entries;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

/// Queries verified global & friends leaderboards with pagination & tie handling.
class LeaderboardRepository {
  LeaderboardRepository({FirebaseFirestore? firestore, String? databaseId})
      : _db = firestore ??
            (databaseId != null
                ? FirebaseFirestore.instanceFor(
                    app: Firebase.app(),
                    databaseId: databaseId,
                  )
                : FirebaseFirestore.instance);

  final FirebaseFirestore _db;

  static const int pageSize = 20;

  /// Sorts entries deterministically with tie-breaking (metric -> wins -> tournaments -> nickname).
  static List<LeaderboardEntry> sortDeterministically(
    List<LeaderboardEntry> entries,
    LeaderboardMetric metric,
  ) {
    final copy = List<LeaderboardEntry>.from(entries);
    copy.sort((a, b) {
      final primary = b.scoreFor(metric).compareTo(a.scoreFor(metric));
      if (primary != 0) return primary;
      final winsTie = b.wins.compareTo(a.wins);
      if (winsTie != 0) return winsTie;
      final cupTie = b.tournamentsWon.compareTo(a.tournamentsWon);
      if (cupTie != 0) return cupTie;
      return a.publicNickname
          .toLowerCase()
          .compareTo(b.publicNickname.toLowerCase());
    });
    return copy;
  }

  /// Fetches a page of opted-in Global Leaderboard entries using indexed query.
  Future<LeaderboardPageResult> fetchGlobalPage({
    required LeaderboardMetric metric,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('leaderboardEntries')
        .where('optIn', isEqualTo: true)
        .orderBy(metric.field, descending: true)
        .limit(pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    final entries = sortDeterministically(
      snap.docs.map(LeaderboardEntry.fromFirestore).toList(growable: false),
      metric,
    );

    return LeaderboardPageResult(
      entries: entries,
      lastDocument: snap.docs.isNotEmpty ? snap.docs.last : null,
      hasMore: snap.docs.length == pageSize,
    );
  }

  /// Fetches verified leaderboard entries for the current player + their friends.
  Future<List<LeaderboardEntry>> fetchFriendsLeaderboard({
    required String currentUid,
    required List<String> friendUids,
    required LeaderboardMetric metric,
  }) async {
    final ids = <String>{currentUid, ...friendUids}.toList(growable: false);
    final results = <LeaderboardEntry>[];

    // Batch fetch in chunks of 10 (Firestore `whereIn` limit / point gets).
    for (final uid in ids) {
      try {
        final doc = await _db.collection('leaderboardEntries').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          final entry = LeaderboardEntry.fromFirestore(doc);
          if (entry.optIn || entry.uid == currentUid) {
            results.add(entry);
          }
        }
      } catch (_) {}
    }

    return sortDeterministically(results, metric);
  }
}
