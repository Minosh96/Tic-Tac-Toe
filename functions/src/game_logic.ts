export interface WinEvaluation {
  winner: 'h' | 'g';
  line: number[];
}

export function evaluateWinner(board: string[], size: number): WinEvaluation | null {
  if (size < 3 || board.length !== size * size) return null;

  for (let row = 0; row < size; row++) {
    const start = row * size;
    const first = board[start];
    if (first !== 'h' && first !== 'g') continue;
    const line = Array.from({ length: size }, (_, c) => start + c);
    if (line.every((i) => board[i] === first)) return { winner: first, line };
  }

  for (let col = 0; col < size; col++) {
    const first = board[col];
    if (first !== 'h' && first !== 'g') continue;
    const line = Array.from({ length: size }, (_, r) => r * size + col);
    if (line.every((i) => board[i] === first)) return { winner: first, line };
  }

  const d1 = board[0];
  if (d1 === 'h' || d1 === 'g') {
    const line = Array.from({ length: size }, (_, i) => i * size + i);
    if (line.every((i) => board[i] === d1)) return { winner: d1, line };
  }

  const d2 = board[size - 1];
  if (d2 === 'h' || d2 === 'g') {
    const line = Array.from({ length: size }, (_, i) => i * size + (size - i - 1));
    if (line.every((i) => board[i] === d2)) return { winner: d2, line };
  }

  return null;
}

export function winsNeeded(bestOf: number): number {
  return Math.floor(bestOf / 2) + 1;
}

export function computeChampion(hostWins: number, guestWins: number, bestOf: number): '' | 'h' | 'g' {
  const target = winsNeeded(bestOf);
  if (hostWins >= target) return 'h';
  if (guestWins >= target) return 'g';
  return '';
}

export function rivalryIdFor(uidA: string, uidB: string): string {
  return [uidA, uidB].sort().join('__');
}

export interface AchievementInput {
  totalWins: number;
  tournamentsWon: number;
  blitzWins: number;
  megaWins: number;
  maxRivalryMatches: number;
  wonWithoutDroppingRound: boolean;
  wonAfterTrailing: boolean;
}

export interface AchievementProgress {
  id: string;
  progress: number;
  target: number;
  unlocked: boolean;
}

export function evaluateAchievements(input: AchievementInput): AchievementProgress[] {
  const specs: Array<{ id: string; progress: number; target: number }> = [
    { id: 'first_victory', progress: Math.min(input.totalWins, 1), target: 1 },
    { id: 'rising_star', progress: Math.min(input.totalWins, 5), target: 5 },
    { id: 'tic_tac_master', progress: Math.min(input.totalWins, 25), target: 25 },
    { id: 'champion', progress: Math.min(input.tournamentsWon, 1), target: 1 },
    { id: 'triple_champion', progress: Math.min(input.tournamentsWon, 3), target: 3 },
    { id: 'perfect_match', progress: input.wonWithoutDroppingRound ? 1 : 0, target: 1 },
    { id: 'blitz_hero', progress: Math.min(input.blitzWins, 5), target: 5 },
    { id: 'mega_strategist', progress: Math.min(input.megaWins, 5), target: 5 },
    { id: 'friendly_rival', progress: Math.min(input.maxRivalryMatches, 10), target: 10 },
    { id: 'comeback_king', progress: input.wonAfterTrailing ? 1 : 0, target: 1 },
  ];
  return specs.map((s) => ({ ...s, unlocked: s.progress >= s.target }));
}
