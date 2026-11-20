import test from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateWinner,
  computeChampion,
  rivalryIdFor,
  evaluateAchievements,
} from '../lib/game_logic.js';

test('evaluateWinner detects 3x3 through 6x6 wins', () => {
  const b3 = ['h', 'h', 'h', '', 'g', '', '', '', ''];
  assert.deepEqual(evaluateWinner(b3, 3), { winner: 'h', line: [0, 1, 2] });

  const b6 = Array(36).fill('');
  for (let i = 0; i < 6; i++) b6[i * 6 + i] = 'g';
  assert.deepEqual(evaluateWinner(b6, 6), {
    winner: 'g',
    line: [0, 7, 14, 21, 28, 35],
  });
});

test('computeChampion handles Best-of-3 and Best-of-5 accurately', () => {
  assert.equal(computeChampion(1, 1, 3), '');
  assert.equal(computeChampion(2, 1, 3), 'h');
  assert.equal(computeChampion(2, 3, 5), 'g');
});

test('rivalryIdFor is deterministic regardless of player order', () => {
  assert.equal(rivalryIdFor('uidB', 'uidA'), 'uidA__uidB');
  assert.equal(rivalryIdFor('uidA', 'uidB'), 'uidA__uidB');
});

test('evaluateAchievements unlocks expected verified milestones', () => {
  const list = evaluateAchievements({
    totalWins: 6,
    tournamentsWon: 3,
    blitzWins: 5,
    megaWins: 5,
    maxRivalryMatches: 10,
    wonWithoutDroppingRound: true,
    wonAfterTrailing: true,
  });
  const byId = Object.fromEntries(list.map((a) => [a.id, a]));
  assert.equal(byId.first_victory.unlocked, true);
  assert.equal(byId.rising_star.unlocked, true);
  assert.equal(byId.tic_tac_master.unlocked, false);
  assert.equal(byId.triple_champion.unlocked, true);
  assert.equal(byId.perfect_match.unlocked, true);
  assert.equal(byId.blitz_hero.unlocked, true);
  assert.equal(byId.mega_strategist.unlocked, true);
  assert.equal(byId.friendly_rival.unlocked, true);
  assert.equal(byId.comeback_king.unlocked, true);
});
