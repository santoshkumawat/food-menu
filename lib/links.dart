import 'sync.dart' show isEmail;

/// Always opens the newest GitHub release, where the APK can be downloaded.
/// Publish each new version as a release and attach `app-release.apk`.
const appDownloadUrl =
    'https://github.com/santoshkumawat/food-menu/releases/latest';

/// The message the admin shares after inviting someone.
String inviteMessage(String familyName, String inviteKey) {
  final how = isEmail(inviteKey)
      ? 'this email: $inviteKey'
      : 'the username: $inviteKey';
  return 'I invited you to "$familyName" on Aaj Kya Banega?\n\n'
      '1. Download the app (open this link on your phone and install the APK):\n'
      '$appDownloadUrl\n\n'
      '2. Sign up or log in with $how.\n\n'
      '3. Open the app and accept the invitation.';
}
