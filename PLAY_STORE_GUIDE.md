# Publishing Melow Tic Tac Toe to the Google Play Store

Complete step-by-step Play Store publishing guide for **`com.melowlabs.melow_tic_tac_toe`** (v3.4.0+10).
`android/app/build.gradle.kts`, `.github/workflows/android-release.yml`, and `docs/privacy.html` are **already configured** for release signing and `.aab` generation!

---

## Step 1: Create Your Google Play Console Account

1. Go to [Google Play Console](https://play.google.com/console) and register a developer account (one-time \$25 USD fee).
2. Complete your identity verification.
3. **Important for new personal accounts:** Google requires a **Closed Test** with at least **12 opted-in testers for 14 continuous days** before granting Production release access.

---

## Step 2: Generate Your Permanent Android Upload Keystore (Run Once!)

Open PowerShell on your PC and run this command (replace passwords with strong ones and **save them safely** — never lose this `.jks` file!):

```powershell
keytool -genkey -v -keystore "$env:USERPROFILE\melow-upload-keystore.jks" `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

> **CRITICAL:** Never commit `.jks` or `key.properties` to Git (both are already listed in `.gitignore`). Back up `C:\Users\Minosh\melow-upload-keystore.jks` to Google Drive / a secure password manager.

---

## Step 3: Create `android/key.properties`

Create a file at `android/key.properties` (already gitignored) with your exact passwords:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=C:\\Users\\Minosh\\melow-upload-keystore.jks
```

*(Optional — enable permanent signing on GitHub Actions too so all future GitHub APKs update in-place without uninstalling!)*
Encode your keystore to Base64:
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\melow-upload-keystore.jks")) | Set-Clipboard
```
Then in GitHub → **Settings → Secrets and variables → Actions**, add 4 repository secrets:
- `KEYSTORE_BASE64` (paste from clipboard)
- `KEYSTORE_PASSWORD`
- `KEY_ALIAS` (`upload`)
- `KEY_PASSWORD`

---

## Step 4: Build the Signed Google Play App Bundle (`.aab`)

Google Play requires an `.aab` (Android App Bundle), not `.apk`:

```powershell
flutter clean
flutter pub get
flutter build appbundle --release
```

Your Play Store upload file will be at:
```
build\app\outputs\bundle\release\app-release.aab
```

*(Before every future Play Store update, increment the build number in `pubspec.yaml`, e.g. `3.4.0+10` → `3.4.1+11`.)*

---

## Step 5: Publish Your Privacy Policy URL (2 Clicks via GitHub Pages)

`docs/privacy.html` is already in your repository! Publish it free on GitHub Pages:
1. Open your GitHub repo: `https://github.com/Minosh96/Tic-Tac-Toe/settings/pages`
2. Under **Build and deployment → Source**, choose **Deploy from a branch** → Branch: **`main`**, Folder: **`/docs`** → click **Save**.
3. Wait ~60 seconds. Your live URLs for Play Console will be:
   - **Privacy Policy URL:** `https://minosh96.github.io/Tic-Tac-Toe/privacy.html`
   - **Data Deletion URL:** `https://minosh96.github.io/Tic-Tac-Toe/privacy.html#delete-data`

---

## Step 6: Prepare Play Store Graphics & Listing Text

In **Play Console → Grow → Store presence → Main store listing**:
1. **App Name:** `Melow Tic Tac Toe`
2. **Short Description** (≤ 80 chars):
   > Real-time emoji Tic-Tac-Toe with Blitz mode, cups, friend chat & voice calls!
3. **Full Description:** Highlight 3×3–6×6 boards, 100+ emojis, Best-of-3/5 Melow Cups, Blitz 5s mode, Random Challenge Wheel, live Reactions/Taunts, 1-on-1 Friend Chat with photo sharing, and hands-free Voice Calls.
4. **App Icon:** `512 × 512 px` PNG (`assets/images/melow_logo.png`).
5. **Feature Graphic:** `1024 × 500 px` PNG/JPG banner.
6. **Phone Screenshots:** Upload 4–8 screenshots from your phone (Home Dashboard, Live Match Board, Trophies Cabinet, Friends & Chat, Voice Call).

---

## Step 7: Fill Out Play Console App Content Declarations (Avoid Rejections!)

In **Play Console → Policy and programmes → App content**, complete every checklist:

1. **Privacy Policy:** Paste `https://minosh96.github.io/Tic-Tac-Toe/privacy.html`.
2. **Data Safety:**
   - **Does your app collect or share user data?** → **Yes** (collected, not shared with third parties).
   - **Encrypted in transit?** → **Yes** (HTTPS/TLS & WebRTC DTLS-SRTP).
   - **Data deletion link:** `https://minosh96.github.io/Tic-Tac-Toe/privacy.html#delete-data`.
   - **Data types collected (App functionality only, optional/user-provided):**
     - *App info & performance / Device or other IDs:* Anonymous Firebase User ID
     - *Personal info:* Nickname
     - *Photos and videos:* Optional profile photo & user-shared chat photos
     - *Messages:* Temporary room chat & direct friend messages
     - *Audio:* Ephemeral voice call audio (processed in real time, not permanently stored)
3. **Foreground Service Permissions (`FOREGROUND_SERVICE_DATA_SYNC`):**
   - Declare **Data Sync**: Explain that Melow Tic Tac Toe maintains an active real-time connection for incoming friend voice calls and instant chat messages while the phone is locked. Attach a short 15-second screen recording showing the app receiving an incoming call/message notification while locked/minimized.
4. **Full-Screen Intent Permission (`USE_FULL_SCREEN_INTENT`):**
   - Declare **Calling functionality**: Used exclusively to wake the lock screen and alert the user to an incoming peer-to-peer friend voice call (equivalent to VoIP calling apps).
5. **Content Rating (IARC):**
   - Complete the questionnaire; answer **Yes** to *Users interact* (chat & voice calls) and note built-in **Block Player** and **Report Player** moderation tools.
6. **Target Audience & Content:**
   - Select **13–15, 16–17, 18 and over** (avoids Families/COPPA restrictions due to free-form chat & voice calling).
7. **App Access:**
   - Select **All functionality is available without special access** (Firebase Anonymous Auth signs in automatically with zero login wall).

---

## Step 8: Upload `.aab`, Run Closed Test & Publish!

1. In Play Console, go to **Test and release → Testing → Closed testing** (or **Internal testing** first to verify installation on your own phones!).
2. Click **Create new release** → opt in to **Play App Signing** (recommended).
3. Upload `build\app\outputs\bundle\release\app-release.aab`.
4. Add release notes (e.g., *"Melow Tic Tac Toe v3.4.0 — Real-time multiplayer Tic-Tac-Toe with Blitz mode, Melow Cups, Friend Chat, photo sharing & live voice calls!"*).
5. Click **Next → Save → Send changes for review**.
6. Once your 12 testers opt in for 14 continuous days (required for new personal Play Console accounts), click **Apply for Production** and publish worldwide!
