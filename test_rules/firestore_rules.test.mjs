/**
 * Firebase Emulator Suite Security Rules Tests for Melow Tic Tac Toe v2.0.
 * Run with:
 *   npx -y firebase-tools@latest emulators:exec --only firestore "node --test test_rules/firestore_rules.test.mjs"
 */
import test from 'node:test';
import fs from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp } from 'firebase/firestore';

const PROJECT_ID = 'melow-tic-tac-toe-test';

test('Firestore Security Rules — Melow v2.0 invariants', async (t) => {
  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync('firestore.rules', 'utf8'),
    },
  });

  t.after(async () => {
    await testEnv.cleanup();
  });

  const hostCtx = testEnv.authenticatedContext('host_uid');
  const guestCtx = testEnv.authenticatedContext('guest_uid');
  const strangerCtx = testEnv.authenticatedContext('stranger_uid');

  const hostDb = hostCtx.firestore();
  const guestDb = guestCtx.firestore();
  const strangerDb = strangerCtx.firestore();

  await t.test('allows host to create a valid lobby room and guest to join', async () => {
    const roomRef = doc(hostDb, 'rooms', 'ABC234');
    await assertSucceeds(
      setDoc(roomRef, {
        hostId: 'host_uid',
        guestId: '',
        hostName: 'Host',
        guestName: '',
        hostEmoji: '❌',
        guestEmoji: '',
        size: 3,
        bestOf: 3,
        gameMode: 'blitz',
        status: 'lobby',
        board: Array(9).fill(''),
        turn: 'h',
        round: 1,
        roundDone: false,
        hostWins: 0,
        guestWins: 0,
        draws: 0,
        lastResult: '',
        champion: '',
        createdAt: serverTimestamp(),
      })
    );

    await assertSucceeds(
      updateDoc(doc(guestDb, 'rooms', 'ABC234'), {
        guestId: 'guest_uid',
        guestName: 'Guest',
        guestEmoji: '⭕',
        status: 'playing',
      })
    );
  });

  await t.test('blocks non-participant from reading or posting room messages/reactions', async () => {
    await assertFails(getDoc(doc(strangerDb, 'rooms', 'ABC234', 'messages', 'm1')));
    await assertFails(
      setDoc(doc(strangerDb, 'rooms', 'ABC234', 'reactions', 'r1'), {
        senderUid: 'stranger_uid',
        kind: 'emoji',
        payload: '🔥',
        createdAt: serverTimestamp(),
        expireAt: Timestamp.fromMillis(Date.now() + 60_000),
      })
    );
  });

  await t.test('allows room member to send valid reaction and blocks sender impersonation', async () => {
    await assertSucceeds(
      setDoc(doc(hostDb, 'rooms', 'ABC234', 'reactions', 'r_ok'), {
        senderUid: 'host_uid',
        kind: 'emoji',
        payload: '🔥',
        createdAt: serverTimestamp(),
        expireAt: Timestamp.fromMillis(Date.now() + 60_000),
      })
    );
    await assertFails(
      setDoc(doc(guestDb, 'rooms', 'ABC234', 'reactions', 'r_spoof'), {
        senderUid: 'host_uid',
        kind: 'emoji',
        payload: '🔥',
        createdAt: serverTimestamp(),
        expireAt: Timestamp.fromMillis(Date.now() + 60_000),
      })
    );
  });

  await t.test('strictly blocks client writes to stats, trophies, achievements, rivalries & leaderboards', async () => {
    await assertFails(setDoc(doc(hostDb, 'stats', 'host_uid'), { wins: 999 }));
    await assertFails(
      setDoc(doc(hostDb, 'users', 'host_uid', 'trophies', 'fake'), { title: 'Fake Cup' })
    );
    await assertFails(
      setDoc(doc(hostDb, 'users', 'host_uid', 'achievements', 'first_victory'), { verified: true })
    );
    await assertFails(
      setDoc(doc(hostDb, 'leaderboardEntries', 'host_uid'), { wins: 999, optIn: true })
    );
    await assertFails(
      setDoc(doc(hostDb, 'rivalries', 'guest_uid__host_uid'), { totalMatches: 99 })
    );
  });

  await t.test('blocks friend requests from a blocked user', async () => {
    await assertSucceeds(
      setDoc(doc(guestDb, 'users', 'guest_uid', 'blocked', 'stranger_uid'), {
        blockedUid: 'stranger_uid',
        createdAt: serverTimestamp(),
      })
    );
    await assertFails(
      setDoc(doc(strangerDb, 'friendRequests', 'stranger_uid__guest_uid'), {
        senderUid: 'stranger_uid',
        senderName: 'Stranger',
        receiverUid: 'guest_uid',
        status: 'pending',
        createdAt: serverTimestamp(),
      })
    );
  });

  await t.test('allows room members and direct chat participants to delete messages (clear chat) while blocking non-participants and updates', async () => {
    const roomMsgHostRef = doc(hostDb, 'rooms', 'ABC234', 'messages', 'm_clear');
    await assertSucceeds(
      setDoc(roomMsgHostRef, {
        uid: 'host_uid',
        text: 'Hello room',
        createdAt: serverTimestamp(),
        expireAt: Timestamp.fromMillis(Date.now() + 60_000),
      })
    );
    await assertFails(updateDoc(roomMsgHostRef, { text: 'Edited' }));
    await assertFails(deleteDoc(doc(strangerDb, 'rooms', 'ABC234', 'messages', 'm_clear')));
    await assertSucceeds(deleteDoc(doc(guestDb, 'rooms', 'ABC234', 'messages', 'm_clear')));

    const chatId = 'guest_uid__host_uid';
    await assertSucceeds(
      setDoc(doc(hostDb, 'chats', chatId), {
        participants: ['guest_uid', 'host_uid'],
        lastMessage: 'Hi',
        lastSenderUid: 'host_uid',
        updatedAt: serverTimestamp(),
      })
    );
    const dmHostRef = doc(hostDb, 'chats', chatId, 'messages', 'dm_clear');
    await assertSucceeds(
      setDoc(dmHostRef, {
        senderUid: 'host_uid',
        text: 'Hi friend',
        createdAt: serverTimestamp(),
      })
    );
    await assertFails(updateDoc(dmHostRef, { text: 'Edited' }));
    await assertFails(deleteDoc(doc(strangerDb, 'chats', chatId, 'messages', 'dm_clear')));
    await assertSucceeds(deleteDoc(doc(guestDb, 'chats', chatId, 'messages', 'dm_clear')));
  });

  await t.test('enforces profileVisibility, hidePhotoGlobally, hideNameGlobally, +0..5 stats deltas, and stats-bounded leaderboard updates', async () => {
    const hostUserRef = doc(hostDb, 'users', 'host_uid');
    await assertSucceeds(
      setDoc(hostUserRef, {
        nickname: 'HostPlayer',
        avatarId: 'cat',
        preferredEmoji: '❌',
        publicProfileEnabled: true,
        leaderboardOptIn: true,
        profileVisibility: 'private',
        hidePhotoGlobally: true,
        hideNameGlobally: false,
        createdAt: serverTimestamp(),
      })
    );
    // Owner can read private profile, non-owners cannot
    await assertSucceeds(getDoc(hostUserRef));
    await assertFails(getDoc(doc(guestDb, 'users', 'host_uid')));

    // Switch to 'friends' visibility: guest can read only if in host's friends subcollection
    await assertSucceeds(updateDoc(hostUserRef, { profileVisibility: 'friends' }));
    await assertFails(getDoc(doc(guestDb, 'users', 'host_uid')));
    await assertSucceeds(
      setDoc(doc(hostDb, 'users', 'host_uid', 'friends', 'guest_uid'), {
        friendUid: 'guest_uid',
        nickname: 'Guest',
        avatarId: 'dog',
        since: serverTimestamp(),
        status: 'accepted',
      })
    );
    await assertSucceeds(getDoc(doc(guestDb, 'users', 'host_uid')));
    await assertFails(getDoc(doc(strangerDb, 'users', 'host_uid')));

    // Stats create (<=1) and update (+0..5 per match, tournamentsWon/trophyCount <= +1)
    const hostStatsRef = doc(hostDb, 'stats', 'host_uid');
    await assertSucceeds(
      setDoc(hostStatsRef, {
        gamesPlayed: 1,
        wins: 1,
        losses: 0,
        draws: 0,
        tournamentsWon: 0,
        currentStreak: 1,
        bestStreak: 1,
        blitzWins: 1,
        megaWins: 0,
        trophyCount: 0,
        updatedAt: serverTimestamp(),
      })
    );
    await assertSucceeds(
      updateDoc(hostStatsRef, {
        gamesPlayed: 6,
        wins: 4,
        losses: 1,
        draws: 1,
        tournamentsWon: 1,
        currentStreak: 4,
        bestStreak: 4,
        blitzWins: 4,
        megaWins: 3,
        trophyCount: 1,
        updatedAt: serverTimestamp(),
      })
    );
    // Reject > +5 jump on wins or > +1 jump on tournamentsWon
    await assertFails(updateDoc(hostStatsRef, { wins: 15 }));
    await assertFails(updateDoc(hostStatsRef, { tournamentsWon: 3 }));

    // Leaderboard create & update bounded by stats/{uid}
    const lbRef = doc(hostDb, 'leaderboardEntries', 'host_uid');
    await assertSucceeds(
      setDoc(lbRef, {
        publicNickname: 'HostPlayer',
        avatarId: 'cat',
        wins: 1,
        tournamentsWon: 0,
        bestStreak: 1,
        blitzWins: 1,
        optIn: true,
        updatedAt: serverTimestamp(),
      })
    );
    // Resync with stats (wins: 4 -> 5, bounded by stats.wins + 1)
    await assertSucceeds(
      updateDoc(lbRef, {
        publicNickname: 'Player #HOST',
        wins: 4,
        tournamentsWon: 1,
        bestStreak: 4,
        blitzWins: 4,
        updatedAt: serverTimestamp(),
      })
    );
    // Reject jump exceeding stats + 1
    await assertFails(updateDoc(lbRef, { wins: 99 }));
  });
});
