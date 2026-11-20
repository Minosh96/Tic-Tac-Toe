import * as admin from 'firebase-admin';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { computeChampion, evaluateAchievements, rivalryIdFor } from './game_logic';

admin.initializeApp();

const DATABASE_ID = 'melow-game';
const db = getFirestore(admin.app(), DATABASE_ID);
const BLITZ_SECONDS = 5;

function requireAuth(auth: { uid: string } | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
  return auth.uid;
}

/**
 * Authoritative, idempotent Blitz 5-second timeout resolver.
 * Ensures a timeout is recorded at most once per round and respects server time.
 */
export const claimBlitzTimeout = onCall({ region: 'asia-south1' }, async (req) => {
  const uid = requireAuth(req.auth);
  const roomId = String(req.data?.roomId ?? '').trim().toUpperCase();
  const expectedRound = Number(req.data?.round ?? 0);
  if (roomId.length !== 6 || !Number.isInteger(expectedRound) || expectedRound < 1) {
    throw new HttpsError('invalid-argument', 'Valid roomId and round are required.');
  }

  const roomRef = db.collection('rooms').doc(roomId);
  let matchFinished = false;

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(roomRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Room not found.');
    const d = snap.data()!;
    if (d.hostId !== uid && d.guestId !== uid) {
      throw new HttpsError('permission-denied', 'Not a room participant.');
    }
    if (d.gameMode !== 'blitz' || d.status !== 'playing' || d.roundDone === true) {
      return { applied: false };
    }
    if (d.round !== expectedRound) {
      return { applied: false };
    }
    const deadline: Timestamp | null = d.turnDeadlineAt ?? null;
    if (!deadline || Timestamp.now().toMillis() < deadline.toMillis()) {
      return { applied: false };
    }

    const timedOutSide: 'h' | 'g' = d.turn === 'g' ? 'g' : 'h';
    const winnerSide: 'h' | 'g' = timedOutSide === 'h' ? 'g' : 'h';
    const hostWins = Number(d.hostWins ?? 0) + (winnerSide === 'h' ? 1 : 0);
    const guestWins = Number(d.guestWins ?? 0) + (winnerSide === 'g' ? 1 : 0);
    const bestOf = Number(d.bestOf ?? 3);
    const champion = computeChampion(hostWins, guestWins, bestOf);
    matchFinished = champion !== '';

    tx.update(roomRef, {
      roundDone: true,
      lastResult: winnerSide,
      timeoutWinner: winnerSide,
      hostWins,
      guestWins,
      champion,
      status: matchFinished ? 'finished' : 'playing',
      turnDeadlineAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { applied: true, winnerSide, champion };
  });

  if (matchFinished) {
    await processFinalizedMatch(roomId);
  }
  return outcome;
});

/**
 * Idempotent match finalizer: writes immutable `matches/{matchId}`,
 * updates verified `stats`, `achievements`, `trophies`, `rivalries`, and `leaderboardEntries`.
 */
async function processFinalizedMatch(roomId: string): Promise<{ processed: boolean; matchId?: string }> {
  const roomRef = db.collection('rooms').doc(roomId);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) return { processed: false };
  const room = roomSnap.data()!;
  if (room.status !== 'finished' || !room.champion || !room.hostId || !room.guestId) {
    return { processed: false };
  }

  // Unique deterministic match ID per tournament completion (prevents double-counting on retries).
  const matchEpoch = room.round ?? 1;
  const matchId = `${roomId}__${room.hostWins}_${room.guestWins}_${room.draws}_${matchEpoch}`;
  const matchRef = db.collection('matches').doc(matchId);

  const hostUid: string = room.hostId;
  const guestUid: string = room.guestId;
  const winnerUid: string = room.champion === 'h' ? hostUid : guestUid;
  const loserUid: string = winnerUid === hostUid ? guestUid : hostUid;
  const isBlitz = room.gameMode === 'blitz';
  const boardSize = Number(room.size ?? 3);
  const isMega = boardSize >= 5;
  const winnerLostZeroRounds =
    (winnerUid === hostUid && Number(room.guestWins ?? 0) === 0) ||
    (winnerUid === guestUid && Number(room.hostWins ?? 0) === 0);

  const rivalryId = rivalryIdFor(hostUid, guestUid);
  const rivalryRef = db.collection('rivalries').doc(rivalryId);
  const winnerStatsRef = db.collection('stats').doc(winnerUid);
  const loserStatsRef = db.collection('stats').doc(loserUid);
  const winnerUserRef = db.collection('users').doc(winnerUid);
  const loserUserRef = db.collection('users').doc(loserUid);

  const processed = await db.runTransaction(async (tx) => {
    const existingMatch = await tx.get(matchRef);
    if (existingMatch.exists) return false;

    const [wStatsSnap, lStatsSnap, wUserSnap, lUserSnap, rivalSnap] = await Promise.all([
      tx.get(winnerStatsRef),
      tx.get(loserStatsRef),
      tx.get(winnerUserRef),
      tx.get(loserUserRef),
      tx.get(rivalryRef),
    ]);

    const wPrev = wStatsSnap.data() ?? {};
    const lPrev = lStatsSnap.data() ?? {};
    const wUser = wUserSnap.data() ?? {};
    const lUser = lUserSnap.data() ?? {};
    const rPrev = rivalSnap.data() ?? {};

    const wWins = Number(wPrev.wins ?? 0) + 1;
    const wTournaments = Number(wPrev.tournamentsWon ?? 0) + 1;
    const wCurrentStreak = Number(wPrev.currentStreak ?? 0) + 1;
    const wBestStreak = Math.max(Number(wPrev.bestStreak ?? 0), wCurrentStreak);
    const wBlitzWins = Number(wPrev.blitzWins ?? 0) + (isBlitz ? 1 : 0);
    const wMegaWins = Number(wPrev.megaWins ?? 0) + (isMega ? 1 : 0);
    const wTrophies = Number(wPrev.trophyCount ?? 0) + 1;

    const lLosses = Number(lPrev.losses ?? 0) + 1;

    const prevWinsByPlayer = (rPrev.winsByPlayer ?? {}) as Record<string, number>;
    const nextWinsByPlayer: Record<string, number> = {
      [hostUid]: Number(prevWinsByPlayer[hostUid] ?? 0) + (winnerUid === hostUid ? 1 : 0),
      [guestUid]: Number(prevWinsByPlayer[guestUid] ?? 0) + (winnerUid === guestUid ? 1 : 0),
    };
    const nextTotalRivalMatches = Number(rPrev.totalMatches ?? 0) + 1;
    const nextRivalStreak = rPrev.currentStreakOwner === winnerUid ? Number(rPrev.currentStreak ?? 0) + 1 : 1;
    const nextRivalBest = Math.max(Number(rPrev.bestStreak ?? 0), nextRivalStreak);

    // 1. Immutable finalized match record
    tx.set(matchRef, {
      roomId,
      players: [hostUid, guestUid],
      playerNames: {
        [hostUid]: room.hostName ?? 'Host',
        [guestUid]: room.guestName ?? 'Guest',
      },
      gameMode: room.gameMode ?? 'classic',
      boardSize,
      hostWins: Number(room.hostWins ?? 0),
      guestWins: Number(room.guestWins ?? 0),
      draws: Number(room.draws ?? 0),
      finalWinnerUid: winnerUid,
      finalStatus: 'won',
      completedAt: FieldValue.serverTimestamp(),
      processedAt: FieldValue.serverTimestamp(),
    });

    // 2. Verified winner & loser stats
    tx.set(
      winnerStatsRef,
      {
        gamesPlayed: Number(wPrev.gamesPlayed ?? 0) + 1,
        wins: wWins,
        losses: Number(wPrev.losses ?? 0),
        draws: Number(wPrev.draws ?? 0),
        tournamentsWon: wTournaments,
        currentStreak: wCurrentStreak,
        bestStreak: wBestStreak,
        blitzWins: wBlitzWins,
        megaWins: wMegaWins,
        trophyCount: wTrophies,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(
      loserStatsRef,
      {
        gamesPlayed: Number(lPrev.gamesPlayed ?? 0) + 1,
        wins: Number(lPrev.wins ?? 0),
        losses: lLosses,
        draws: Number(lPrev.draws ?? 0),
        tournamentsWon: Number(lPrev.tournamentsWon ?? 0),
        currentStreak: 0,
        bestStreak: Number(lPrev.bestStreak ?? 0),
        blitzWins: Number(lPrev.blitzWins ?? 0),
        megaWins: Number(lPrev.megaWins ?? 0),
        trophyCount: Number(lPrev.trophyCount ?? 0),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // 3. Verified rivalry aggregate
    tx.set(
      rivalryRef,
      {
        playerUids: [hostUid, guestUid].sort(),
        winsByPlayer: nextWinsByPlayer,
        draws: Number(rPrev.draws ?? 0),
        totalMatches: nextTotalRivalMatches,
        currentStreakOwner: winnerUid,
        currentStreak: nextRivalStreak,
        bestStreak: nextRivalBest,
        lastMatchAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // 4. Verified tournament trophy (deterministic ID prevents duplicates)
    tx.set(db.collection('users').doc(winnerUid).collection('trophies').doc(`cup_${matchId}`), {
      trophyId: `cup_${matchId}`,
      matchId,
      title: `Melow Cup (${boardSize}×${boardSize} ${isBlitz ? 'Blitz' : 'Classic'})`,
      awardedAt: FieldValue.serverTimestamp(),
    });

    // 5. Verified achievements for winner
    const achList = evaluateAchievements({
      totalWins: wWins,
      tournamentsWon: wTournaments,
      blitzWins: wBlitzWins,
      megaWins: wMegaWins,
      maxRivalryMatches: nextTotalRivalMatches,
      wonWithoutDroppingRound: winnerLostZeroRounds,
      wonAfterTrailing: false,
    });
    for (const ach of achList) {
      const achRef = db.collection('users').doc(winnerUid).collection('achievements').doc(ach.id);
      tx.set(
        achRef,
        {
          achievementId: ach.id,
          progress: ach.progress,
          verified: true,
          ...(ach.unlocked ? { unlockedAt: FieldValue.serverTimestamp() } : {}),
        },
        { merge: true }
      );
    }

    // 6. Verified leaderboard entries
    tx.set(
      db.collection('leaderboardEntries').doc(winnerUid),
      {
        publicNickname: wUser.nickname ?? room.hostName ?? 'Player',
        avatarId: wUser.avatarId ?? 'astro',
        wins: wWins,
        tournamentsWon: wTournaments,
        bestStreak: wBestStreak,
        blitzWins: wBlitzWins,
        optIn: wUser.leaderboardOptIn !== false,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(
      db.collection('leaderboardEntries').doc(loserUid),
      {
        publicNickname: lUser.nickname ?? room.guestName ?? 'Player',
        avatarId: lUser.avatarId ?? 'fox',
        wins: Number(lPrev.wins ?? 0),
        tournamentsWon: Number(lPrev.tournamentsWon ?? 0),
        bestStreak: Number(lPrev.bestStreak ?? 0),
        blitzWins: Number(lPrev.blitzWins ?? 0),
        optIn: lUser.leaderboardOptIn !== false,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return true;
  });

  return { processed, matchId };
}

export const finalizeMatch = onCall({ region: 'asia-south1' }, async (req) => {
  requireAuth(req.auth);
  const roomId = String(req.data?.roomId ?? '').trim().toUpperCase();
  if (roomId.length !== 6) {
    throw new HttpsError('invalid-argument', 'Valid 6-char roomId required.');
  }
  return processFinalizedMatch(roomId);
});

/**
 * Atomic, idempotent friend challenge acceptance creating a single shared room.
 */
export const acceptFriendChallenge = onCall({ region: 'asia-south1' }, async (req) => {
  const uid = requireAuth(req.auth);
  const challengeId = String(req.data?.challengeId ?? '').trim();
  const guestName = String(req.data?.guestName ?? 'Player').trim().slice(0, 20);
  const guestEmoji = String(req.data?.guestEmoji ?? '⭕').trim().slice(0, 16);
  const guestAvatar = String(req.data?.guestAvatar ?? 'fox').trim().slice(0, 32);
  if (!challengeId) throw new HttpsError('invalid-argument', 'challengeId required.');

  const chalRef = db.collection('friendChallenges').doc(challengeId);
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const genCode = () =>
    Array.from({ length: 6 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join('');

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(chalRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Challenge not found.');
    const c = snap.data()!;
    if (c.receiverUid !== uid) {
      throw new HttpsError('permission-denied', 'Only the challenged player can accept.');
    }
    if (c.status === 'accepted' && c.roomId) {
      return { roomId: c.roomId };
    }
    if (c.status !== 'pending') {
      throw new HttpsError('failed-precondition', 'Challenge is no longer pending.');
    }

    const roomId = genCode();
    const size = Number(c.boardSize ?? 3);
    const bestOf = Number(c.bestOf ?? 3);
    const isBlitz = c.mode === 'blitz';
    const nowMs = Date.now();

    tx.set(db.collection('rooms').doc(roomId), {
      hostId: c.senderUid,
      guestId: uid,
      hostName: c.senderName ?? 'Host',
      guestName,
      hostEmoji: c.senderEmoji ?? '❌',
      guestEmoji: guestEmoji === c.senderEmoji ? '⭕' : guestEmoji,
      hostAvatar: c.senderAvatar ?? 'astro',
      guestAvatar,
      size,
      bestOf,
      gameMode: isBlitz ? 'blitz' : 'classic',
      status: 'playing',
      board: Array(size * size).fill(''),
      turn: 'h',
      round: 1,
      roundDone: false,
      hostWins: 0,
      guestWins: 0,
      draws: 0,
      lastResult: '',
      champion: '',
      timeoutWinner: '',
      hostLeft: false,
      guestLeft: false,
      ...(isBlitz
        ? {
            turnStartedAt: FieldValue.serverTimestamp(),
            turnDeadlineAt: Timestamp.fromMillis(nowMs + BLITZ_SECONDS * 1000),
          }
        : {}),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(nowMs + 24 * 60 * 60 * 1000),
    });

    tx.update(chalRef, { status: 'accepted', roomId });
    return { roomId };
  });
});

/**
 * Keeps `leaderboardEntries/{uid}` nickname, avatar & optIn synced when user edits profile.
 */
export const syncLeaderboardOptIn = onDocumentUpdated(
  { document: 'users/{uid}', database: DATABASE_ID, region: 'asia-south1' },
  async (event) => {
    const after = event.data?.after.data();
    if (!after) return;
    const uid = event.params.uid;
    const lbRef = db.collection('leaderboardEntries').doc(uid);
    const lbSnap = await lbRef.get();
    if (!lbSnap.exists) return;
    await lbRef.update({
      publicNickname: after.nickname ?? 'Player',
      avatarId: after.avatarId ?? 'astro',
      optIn: after.leaderboardOptIn !== false,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
);

/**
 * Scheduled server-side sweeper for expired Blitz turns (even when both clients disconnect)
 * and expired temporary rooms/messages/reactions.
 */
export const cleanupExpiredData = onSchedule(
  { schedule: 'every 15 minutes', region: 'asia-south1' },
  async () => {
    const now = Timestamp.now();
    const expiredRooms = await db
      .collection('rooms')
      .where('expiresAt', '<', now)
      .limit(25)
      .get();

    for (const roomDoc of expiredRooms.docs) {
      await db.recursiveDelete(roomDoc.ref);
    }
  }
);
