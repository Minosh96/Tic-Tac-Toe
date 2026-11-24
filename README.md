# 🎮 Melow Tic Tac Toe — Version 3.6.0

A polished, social, real-time multiplayer and offline single-player emoji Tic-Tac-Toe game for Android built with **Flutter**, **Firebase Authentication**, **Cloud Firestore (Enterprise Native Mode)**, and **Firebase Cloud Functions**.

Developed at **Melow Labs** • Repository: [Minosh96/Tic-Tac-Toe](https://github.com/Minosh96/Tic-Tac-Toe)

---

## What’s New in Version 3.6.0 (`v3.6.0+14`)
- **Single Player Mode (Player vs System)**: Play 100% offline against a dedicated local `BotEngine` across **Easy**, **Normal**, **Hard**, and **Impossible** difficulty levels (full Alpha-Beta Minimax on `3×3`, move-ordered heuristic search on `4×4–6×6`, executed in a background isolate).
- **Rich Solo Configuration**: Supports Classic, Tournament (`Best of 3`, `5`, `7`), and Blitz (`5s`) modes, `3×3–6×6` board sizes, First Player choice (`Player`, `System`, `Random`), universal emojis, and Practice Mode (`Hint` & `Undo`).
- **Separate Solo Statistics & 8 Solo Achievements**: Tracks Total Games, Wins, Losses, Draws, Solo Cups, Streak, Best Streak, Win %, per-difficulty records, and match history locally (with optional cloud backup) without affecting Global Top 100 online rankings.
- **Streamlined Profile Tab**: Displays Player Identity, Online Multiplayer Summary, Single Player vs System Summary, and Recent Match History, keeping all privacy and account controls cleanly inside Settings (`⚙️`).

---

## What’s Included in Version 2.0

### Preserved v1 Core Features
- Anonymous Firebase Authentication & real-time multiplayer synchronization
- 6-character collision-checked room codes with one-tap copy
- Classic untimed gameplay on **3×3, 4×4, 5×5, and 6×6** boards
- Default ❌/⭕ plus 12 custom emoji marks (with host/guest conflict prevention)
- Best-of-3 & Best-of-5 Melow Cup tournaments with alternating starting player
- Temporary participant-only 24-hour room chat
- Light & Dark themes + `"Developed at Melow Labs"` footer

### New v2.0 Features
- **Brand Identity, Custom Logo & Splash Screen**: Neon arcade Dark Theme (`#101125` / `#1B1C38` / `#8B5CF6` / `#22D3EE` / `#FBBF24`), cheerful Light Theme (`#F8FAFF` / `#FFFFFF`), adaptive Android launcher icon, Android 12 native splash + animated Flutter splash gate, and dedicated **About** screen.
- **Redesigned Gaming Dashboard & 5-Tab Navigation**: `Home | Friends | Trophies | Ranks | Profile` with live pending-challenge badges, player level & rank badge, PLAY NOW CTA, stats overview, achievement progress, and quick-challenge friends carousel.
- **Redesigned Game Screen**: Player avatars, active turn glow, board/mode pills, animated mark pop-in, glowing winning line, confetti celebrations, locally synthesized WAV sound effects & haptics, collapsible chat panel, and leave-game confirmation (`PopScope`).
- **Live Reactions & Quick Taunts**: Floating auto-dismiss (~2s) room-scoped reactions (`😂 😎 😲 👏 🔥 🥳 😭 👍 ❤️`) and playful quick taunts with cooldown spam protection and mute toggle.
- **Blitz Mode (5s)**: Synchronized 5-second move clock (`BlitzTimerBar` isolated from full-screen rebuilds) with atomic/idempotent timeout resolution.
- **Random Challenge Wheel**: Host proposes spinning a 6-option wheel (`Classic 3×3`, `Blitz 3×3`, `Emoji Shuffle`, `Mega 4×4/5×5/6×6`); both players must accept; single shared authoritative outcome locked before Round 1.
- **Player Profiles, Achievements & Trophy Cabinet**: Editable validated nickname, 12 built-in avatars, shareable 8-character friend code, verified stats, 10 deterministic Bronze/Silver/Gold achievements, and Melow Cup trophies.
- **Friends, Challenges, Rivalries & Leaderboards**: Friend code lookup, friend requests, direct match challenges, block/report controls, deterministic head-to-head rivalries (`uidA__uidB`), and paginated Global & Friends leaderboards with opt-out privacy.
- **Privacy-Safe Victory Sharing**: Local PNG victory card renderer (`RepaintBoundary` + `share_plus`) with opponent-name hide toggle and zero room codes/UIDs/chat leaked.
- **Hardened Security Rules & Trusted Cloud Functions**: `firestore.rules` locks `stats`, `achievements`, `trophies`, `matches`, `rivalries`, and `leaderboardEntries` against client tampering (`allow write: if false`). Full TypeScript Cloud Functions v2 backend provided in `functions/`.

---

## Replacing the Temporary Placeholder Logo

A temporary placeholder emblem is bundled at `assets/images/melow_logo.png`. To use your official Melow Labs logo:

1. Replace `assets/images/melow_logo.png` with your own square PNG (`1024×1024` recommended, with ~15% safe padding for Android adaptive icons).
2. Regenerate Android launcher icons & native splash assets:
   ```bash
   dart run flutter_launcher_icons
   dart run flutter_native_splash:create
   ```
3. Rebuild the APK.

---

## New Dependencies Added in v2.0

| Package | Purpose |
| --- | --- |
| `cloud_functions` | Invoke trusted server-side Blitz timeout, match finalization & challenge acceptance |
| `shared_preferences` | Local offline persistence for theme, SFX, haptics, reactions mute & reduced motion |
| `audioplayers` | Play bundled original WAV sound effects with overlap throttling |
| `confetti` | Round & tournament victory confetti celebration |
| `share_plus` | Native Android share sheet for Victory Cards |
| `path_provider` | Temporary file storage for locally rendered PNG victory cards |
| `flutter_launcher_icons` *(dev)* | Generate Android adaptive launcher icons |
| `flutter_native_splash` *(dev)* | Generate Android / Android 12 native splash screen |

---

## Commands to Run & Build Android

```bash
flutter pub get
dart format .
flutter analyze
flutter test

# Run on connected Android device/emulator
flutter run

# Build Android APKs
flutter build apk --debug
flutter build apk --release
```

Release APK output: `build/app/outputs/flutter-apk/app-release.apk`

---

## Firebase Deployment & Emulator Suite

```bash
# Deploy Auth providers, Firestore Security Rules & Composite Indexes
npx -y firebase-tools@latest deploy --only auth,firestore --project melow-tic-tac-toe-minosh96

# Build & test Cloud Functions locally
cd functions && npm install && npm run build && npm test

# Deploy Cloud Functions (requires Firebase Blaze billing plan)
npx -y firebase-tools@latest deploy --only functions --project melow-tic-tac-toe-minosh96

# Run Firestore Security Rules tests against local Emulator Suite
npx -y firebase-tools@latest emulators:exec --only firestore "node --test test_rules/firestore_rules.test.mjs"
```

---

## Schema Migration / Backfill Notes

- **v1 → v2 Compatibility**: Existing `rooms/{roomId}` and `rooms/{roomId}/messages/{messageId}` documents remain 100% readable and playable. Optional v2 room fields (`gameMode`, `hostAvatar`, `guestAvatar`, `turnDeadlineAt`, `wheelProposal`, `wheelResult`, `hostLeft`, `guestLeft`) default safely in `GameRoom.fromFirestore`.
- **Legacy Anonymous Accounts**: `ProfileRepository.ensureProfile()` automatically bootstraps `users/{uid}` and registers a unique `friendCodes/{code}` document on first v2 launch without replacing the existing Firebase UID.
- **Verified Stats**: Stats, achievements, trophies, rivalries, and leaderboard entries are populated exclusively by the trusted Cloud Functions (`functions/src/index.ts`) once deployed on a Blaze-enabled Firebase project.
