# Publishing Melow Tic Tac Toe to the Google Play Store

Complete step-by-step release checklist for **`com.melowlabs.melow_tic_tac_toe`**.

---

## 1. Create a Google Play Developer Account

1. Go to [Google Play Console](https://play.google.com/console) and register a developer account (one-time \$25 USD fee).
2. Complete identity verification and payment profile.
3. Note: New **personal** Play Console accounts (created after Nov 2023) require a **Closed Test** with at least **12 opted-in testers for 14 continuous days** before applying for Production access.

---

## 2. Generate Your Android Upload Keystore (Keep Secret!)

Run this once on your machine (NEVER commit the `.jks` file or passwords to Git — they are already in `android/.gitignore`):

```powershell
keytool -genkey -v -keystore "$env:USERPROFILE\melow-upload-keystore.jks" `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Save your keystore file and passwords in a secure password manager / cloud backup.

---

## 3. Configure Release Signing

Create `android/key.properties` (this file is gitignored):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=C:\\Users\\Minosh\\melow-upload-keystore.jks
```

Update `android/app/build.gradle.kts` to load `key.properties` and use `signingConfigs.getByName("release")` inside `buildTypes { release { ... } }`:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }
    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}
```

---

## 4. Build the Signed Android App Bundle (`.aab`)

Google Play requires `.aab` (Android App Bundle) rather than `.apk`:

```powershell
flutter clean
flutter pub get
flutter build appbundle --release
```

Your Play Store bundle will be created at:
`build/app/outputs/bundle/release/app-release.aab`

*(Remember to increment `version: 3.0.0+3` -> `3.0.1+4` in `pubspec.yaml` before every new upload.)*

---

## 5. Prepare Store Listing Assets

1. **App Icon**: `512 × 512 px` PNG (replace `assets/images/melow_logo.png` with your final Melow Labs artwork first and run `dart run flutter_launcher_icons`).
2. **Feature Graphic**: `1024 × 500 px` PNG/JPG banner.
3. **Phone Screenshots**: At least 2–8 screenshots (`16:9` or `9:16`, e.g., Home Dashboard, Blitz Gameplay, Challenge Wheel, Trophies Cabinet, Friend Chat/Voice Call).
4. **Short Description** (≤ 80 chars):
   > Real-time emoji Tic-Tac-Toe with Blitz mode, trophies, friend chat & voice call!
5. **Privacy Policy URL** (Required because the app uses Firebase Auth, Cloud Firestore, Gallery Photos & Microphone):
   - Host a simple public Privacy Policy page (e.g., on GitHub Pages at `https://minosh96.github.io/Tic-Tac-Toe/privacy.html`) explaining:
     - Anonymous Firebase Authentication UID & chosen nickname/avatar/photo
     - Real-time match state, room chat (24h expiry), direct friend chat & shared images
     - Microphone access used solely during user-initiated peer-to-peer WebRTC voice calls (not recorded)
     - Data deletion contact email

---

## 6. Complete Play Console Declarations

In **Play Console → App Content**:
1. **Privacy Policy**: Paste your hosted Privacy Policy URL.
2. **Data Safety**:
   - Declare **App info / identifiers** (Anonymous Firebase UID), **User content** (chat messages, shared photos, profile photo/nickname), and **Audio** (ephemeral voice call audio — not stored on servers).
   - Mark data as encrypted in transit (HTTPS/TLS + WebRTC DTLS-SRTP).
3. **Content Rating (IARC)**: Complete the questionnaire (note user-to-user chat & voice interaction + built-in Block/Report controls).
4. **Target Audience**: Select appropriate age group (e.g., 13+ due to free-form user chat & voice calls, avoiding COPPA/Families policy complications).
5. **App Access**: All features are accessible without a special login (Anonymous Auth auto-signs in).

---

## 7. Upload, Test & Publish

1. Go to **Testing → Internal testing** (quickest check) or **Closed testing** → **Create new release**.
2. Opt in to **Play App Signing** (recommended by Google).
3. Upload `build/app/outputs/bundle/release/app-release.aab`.
4. Add release notes, click **Next → Save → Start rollout**.
5. Once your 14-day Closed Test (for personal accounts) completes, apply for **Production** access and roll out to Google Play!
