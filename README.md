# Aaj Kya Banega? (What's cooking today?)

An Android app that answers the question every household asks. A family keeps
one shared weekly menu, and each person gets reminders that suit their role:
the cook is told what to prepare, everyone else is told when to eat.

Built with Flutter. Data and sign-in run on Firebase's free plan.

## Features

**Menu**
- Weekly menu with morning routine, breakfast, lunch, snacks, dinner and a
  bedtime slot (Mon to Sun). Tap any item to edit it.
- Today screen with a greeting, filter pills (icon + count) and a "NEXT" badge.
- Week screen with the same pills and a sort menu (Monday to Sunday, or
  starting today).
- Nothing is pre-filled. A new install is empty; the family adds its own menu,
  guidelines and reminder times.

**Families and accounts**
- Sign up with email and password, with email verification and password reset.
- Each person picks a name and a unique username.
- Create a family and become its **admin**, or accept an invitation.
- The admin invites people by **email or username**, assigns a role, changes
  roles later, removes members and cancels pending invitations. Members can see
  the member list and leave. Accounts survive a reinstall or a new phone.

**Roles and reminders** (each person sets their own times)
- **Cook:** wake-up reminder with breakfast and lunch, a follow-up if not
  marked prepared, dinner reminder, and a "soak dry fruits" reminder with a
  follow-up the night before an almond morning. Pressing **Prepared** or
  **Soaked**, on the notification or in the app, cancels the follow-up and tells
  the family.
- **Family member:** reminders for the morning routine, breakfast, lunch,
  snacks, dinner and bedtime milk, showing that day's dish.
- Reminders for the next 7 days are scheduled as one-off notifications and
  rebuilt after every change, so "done" ticks and menu edits take effect.

**Sharing**
- Shared with the family: the menu, the daily guidelines, and the Prepared /
  Soaked ticks. Edits appear live while the app is open, and within about 15
  minutes otherwise, with a "Menu updated by ..." notification.
- Private to each person: medicine timings (saved on their own account only),
  reminder times, the notification switch and the theme.

**App**
- Light and dark theme from the hamburger menu (remembered).
- Menu also has Reminders & times, Send test notification, Check for menu
  changes and Sign out.
- Works on a single phone without Firebase (no sharing, no sign-in).
- **Update notice:** once a day the app asks GitHub for the newest release. If
  it is newer than the installed version, a banner offers **Download** (opens
  the release page) or **Later**. The menu also has **Check for updates**.

## Roles in the code

There are two roles, saved as `cook` and `familyMember` on the phone and in
Firestore (`Role` in `lib/tasks.dart`). They are displayed as **Cook** and
**Family member**. The security rules accept only those two values.

## Getting started

### Requirements
- Flutter 3.47 or newer (stable) and the Android SDK
- A Firebase project (free Spark plan)
- A phone or emulator running Android 7+ (Android 13+ asks for notification
  permission)

### 1. Get the code
```bash
git clone https://github.com/santoshkumawat/food-menu.git
cd food-menu
flutter pub get
```

### 2. Connect Firebase
Follow [FIREBASE_SETUP.md](FIREBASE_SETUP.md): create the project, register the
Android app `com.santosh.aaj_kya_banega`, put `google-services.json` in
`android/app/`, enable **Email/Password** sign-in, and publish
[firestore.rules](firestore.rules). Without `google-services.json` the app
still builds and runs in single-phone mode.

### 3. Run
```bash
flutter run
```

### 4. Build a signed release APK
1. Create a keystore once (keep it and its password safe, outside the repo):
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `android/key.properties` (git-ignored):
   ```
   storePassword=<your password>
   keyPassword=<your password>
   keyAlias=upload
   storeFile=D:/path/to/upload-keystore.jks
   ```
   Use forward slashes in `storeFile`.
3. Build and install:
   ```bash
   flutter build apk --release
   ```
   The APK is at `build/app/outputs/flutter-apk/app-release.apk`. Without
   `key.properties`, release builds fall back to the debug key.

Keep a backup of the keystore. Without it you cannot publish updates that
install over the existing app.

### 5. Publish a release (the invite link points here)
The invite message the admin shares links to
`https://github.com/santoshkumawat/food-menu/releases/latest`, which always
opens the newest release.
1. Raise `version` in `pubspec.yaml`, for example `1.0.1+2`. The number after
   `+` must go up each time, or Android will not install it over the old app.
2. Build the signed APK (step 4) and commit.
3. On GitHub: **Releases -> Draft a new release**, create a tag such as
   `v1.0.1`, attach `build/app/outputs/flutter-apk/app-release.apk`, write a
   short note and **Publish release**.

Name the tag after the version, such as `v1.0.2` for `version: 1.0.2+3`. The
app's update notice compares the tag with the installed version number, so a
tag that does not match the `pubspec.yaml` version would show a wrong banner.
Mark the release as a normal one: drafts and pre-releases are ignored.

People open the link on their phone, download the APK and allow installs from
that source. Phones that already have the app see the update banner within a
day, or straight away via the menu's **Check for updates**. The repository must stay public for the link to work without a
GitHub login.

### Tests
```bash
flutter analyze
flutter test
```

## Project structure

```
lib/
  main.dart            App start-up, theme (light/dark palette), wiring
  store.dart           Menu, guidelines, medicines, times, role; saved on the phone
  tasks.dart           Roles and the reminder tasks for each
  notifications.dart   Schedules reminders; handles the Prepared / Soaked buttons
  sync.dart            Firestore: families, invites, shared menu, background check
  account.dart         Sign-in state: verified, profile, family
  auth_screens.dart    Sign in, verify, profile, create family / invitations
  screens.dart         Today, Week, Family, Health, Reminders, menus
  widgets.dart         Filter pills and the hamburger dropdown
  updates.dart         Checks GitHub for a newer release; powers the update banner
  links.dart           Download link and the invite message
android/               Android project (icons, manifest, signing, Firebase plugin)
firestore.rules        Security rules to publish in the Firebase console
tool/icon_gen_test.dart  Draws the launcher icon (flutter test tool/icon_gen_test.dart)
test/widget_test.dart  Unit and widget tests
```

## Data layout (Firestore)

```
users/{uid}                      username, name, email, familyCode, medicines (private)
usernames/{username}             uid (keeps usernames unique)
families/{code}                  name, adminUid, members{uid: name, username, role, admin}
families/{code}/invites/{key}    invitations the admin has sent
families/{code}/shared/state     menu, guidelines, rev, done flags (members only)
inboxes/{key}/invites/{code}     an invitation as the invited person sees it
```

## Good to know
- Firebase's free plan cannot send the invitation email itself. After
  inviting, use **Tell them** to share a message, for example on WhatsApp. The
  message includes the download link for the latest release.
- Background checks and reminders depend on Android. On Samsung, Xiaomi, Oppo
  and Vivo phones set the app's battery use to **Unrestricted**.
- Reminder times use the phone's time zone.
- The Firestore rules were written without the emulator; check them in the
  console's Rules Playground if something shows "Not allowed".
- The Kotlin incremental cache is turned off (`android/gradle.properties`)
  because it breaks builds when the project and the Pub cache are on different
  drives.

## History
[PLAN.md](PLAN.md) is the original plan from before accounts and sharing.
It is kept for reference and is out of date.
