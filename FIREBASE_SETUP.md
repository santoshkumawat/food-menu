# Firebase setup (one time, free plan)

Without this the app works on a single phone. With it, people sign in with
email and password, create a family or accept an invitation, and share the
menu and the "done" ticks.

## 1. Create the project
1. Open https://console.firebase.google.com and sign in with your Google account.
2. **Add project**, name it `aaj-kya-banega`. Google Analytics can stay off.
3. Stay on the free **Spark** plan. Nothing here needs billing.

## 2. Register the Android app
1. Click the **Android** icon (Add app).
2. Android package name: `com.santosh.aaj_kya_banega`. Leave SHA-1 empty.
3. Download `google-services.json` and put it in `android/app/`.
   It is git-ignored, so it is not pushed to GitHub.

## 3. Turn on email + password sign-in
1. **Build -> Authentication -> Get started**.
2. **Sign-in method** tab -> **Email/Password** -> turn on the first switch
   (leave "Email link" off) -> **Save**.
3. Optional: **Templates** tab -> edit the "Email address verification" and
   "Password reset" emails (sender name, wording).

## 4. Create the database and paste the rules
1. **Build -> Firestore Database -> Create database** (Standard edition).
2. Location near you (for example `asia-south1`), **Production mode**.
3. Open the **Rules** tab, replace everything with the contents of
   `firestore.rules` (in this folder), then **Publish**.
4. Optional check: in the Rules tab use **Rules Playground** to confirm a
   signed-out request to `/families/ABC` is denied.

## How the app works
- **Sign up** with email + password. A verification email is sent; the app
  waits until you tap its link (this keeps invitations to an email address
  safe). Then you choose your name and a unique **username**.
- **Create a family** (you become the **admin** and pick your own role), or
  accept an **invitation** waiting for your email or username.
- **Admin** (Settings): invite by email or username and assign a role (Cook or
  Me), change anyone's role, remove members, cancel pending invitations.
- **Members** can see who is in the family and can leave it. The admin cannot
  leave.
- Firebase's free plan cannot send the invitation email itself. After
  inviting, tap **Tell them** to share a message (WhatsApp etc.). The invited
  person sees the invitation after signing up or logging in with that email
  or username.

## Notes
- Menu edits show up on other phones within about 15 minutes if the app is
  closed (Android decides the exact timing), and instantly if it is open.
- Accounts survive reinstalling the app or changing phones: sign in again and
  you are back in your family, as admin if you were.
- Samsung/Xiaomi/Oppo/Vivo phones delay background work. Set the app to
  **Unrestricted** battery use on every phone.
- The rules were written without a test emulator. If something shows
  "Not allowed", check the **Rules** tab for errors and use the Rules
  Playground, then tell me what it says.
