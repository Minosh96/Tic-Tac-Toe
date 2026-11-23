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
});
