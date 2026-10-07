# Firebase setup (one time, free plan)

Without this the app works on a single phone. With it, both phones share the
menu and the "done" ticks. No sign-in is needed: the phones are linked by a
family code.

## 1. Create the project
1. Open https://console.firebase.google.com and sign in with your Google account.
2. **Add project**, name it `aaj-kya-banega`. You can turn Google Analytics off.
3. Stay on the free **Spark** plan. Nothing here needs billing.

## 2. Register the Android app
1. In the project, click the **Android** icon (Add app).
2. Android package name: `com.santosh.aaj_kya_banega`
3. App nickname: `Aaj Kya Banega`. Leave the SHA-1 field empty.
4. Click **Register app**, then **Download google-services.json**.
5. Copy that file to `android/app/google-services.json` in this project.
   It is git-ignored, so it won't be pushed to GitHub.
6. Skip the remaining "Add Firebase SDK" steps; they are already done in code.

## 3. Create the database
1. In the left menu: **Build -> Firestore Database -> Create database**.
2. Pick a location near you (for example `asia-south1`, Mumbai).
3. Choose **Production mode**.
4. Open the **Rules** tab and replace everything with:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /families/{code} {
      allow get, create, update: if true;
      allow list, delete: if false;
    }
  }
}
```

5. Click **Publish**.

The family code is the secret. Anyone who knows it can read and edit that
family's menu, but nobody can list or delete families. Don't share the code.

## 4. Build and install on BOTH phones
Build the signed release APK in Android Studio, install the same APK on both
phones, then in the app:
1. First phone: pick the role, tap **Start a new family**, and note the code
   shown in Settings.
2. Second phone: pick the role, enter the code, tap **Join with this code**.

## Notes
- Menu edits show up on the other phone within about 15 minutes if its app is
  closed (Android decides the exact timing), and instantly if the app is open.
- Phones from some brands (Xiaomi, Oppo, Vivo, Samsung "sleeping apps") delay
  background work. Set the app to **Unrestricted** battery use on both phones.
