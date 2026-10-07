# Firebase setup (one time, free plan)

Without this the app works on a single phone. With it, family members share
the menu and the "done" ticks. The first phone to start a family is the
**admin**. Everyone else must ask to join and the admin approves or declines.

## 1. Create the project
1. Open https://console.firebase.google.com and sign in with your Google account.
2. **Add project**, name it `aaj-kya-banega`. Google Analytics can stay off.
3. Stay on the free **Spark** plan. Nothing here needs billing.

## 2. Register the Android app
1. Click the **Android** icon (Add app).
2. Android package name: `com.santosh.aaj_kya_banega`. Leave SHA-1 empty.
3. Download `google-services.json` and put it in `android/app/`.
   It is git-ignored, so it is not pushed to GitHub.

## 3. Turn on anonymous sign-in
The app signs each phone in quietly (no email or password) so the server can
tell who is the admin.
1. **Build -> Authentication -> Get started**.
2. **Sign-in method** tab -> **Anonymous** -> **Enable** -> **Save**.

## 4. Create the database
1. **Build -> Firestore Database -> Create database** (Standard edition).
2. Location near you (for example `asia-south1`), **Production mode**.
3. Open the **Rules** tab, replace everything with the rules below, **Publish**.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() { return request.auth != null; }
    function family(code) {
      return get(/databases/$(database)/documents/families/$(code)).data;
    }
    function isAdmin(code) {
      return signedIn() && family(code).adminUid == request.auth.uid;
    }
    function isMember(code) {
      return signedIn() && request.auth.uid in family(code).members;
    }

    match /families/{code} {
      allow get: if signedIn();
      allow create: if signedIn()
        && request.resource.data.adminUid == request.auth.uid
        && request.resource.data.members.keys().hasOnly([request.auth.uid]);
      allow update: if isAdmin(code);
      allow list, delete: if false;

      // People waiting for approval
      match /requests/{uid} {
        allow create: if signedIn() && request.auth.uid == uid;
        allow get: if signedIn() && (request.auth.uid == uid || isAdmin(code));
        allow list: if isAdmin(code);
        allow delete: if signedIn() && (request.auth.uid == uid || isAdmin(code));
        allow update: if false;
      }

      // The menu and done ticks: members only
      match /shared/{doc} {
        allow read, write: if isMember(code);
      }
    }
  }
}
```

## 5. Use it
1. First phone: pick the role, enter a name, tap **Start a new family**.
   You are the admin. Settings shows the family code.
2. Other phones: pick the role, enter a name and the code, tap
   **Ask to join this family**. The admin gets a notification and approves
   in **Settings -> Join requests**.
3. The admin can **Invite someone** (shares the code), see all members, and
   **remove** a member at any time.

## Notes
- Menu edits show up on other phones within about 15 minutes if the app is
  closed (Android decides the exact timing), and instantly if it is open.
- The admin is tied to the phone's app data. Clearing the app's data or
  uninstalling it loses admin rights; start a new family in that case.
- A non-admin who uses **Change** in Settings only leaves on their own phone;
  the admin can remove them from the list.
- Samsung/Xiaomi/Oppo/Vivo phones delay background work. Set the app to
  **Unrestricted** battery use on every phone.
