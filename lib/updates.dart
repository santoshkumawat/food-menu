import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'links.dart';

/// The newest published release.
class UpdateInfo {
  const UpdateInfo(this.version, this.url, this.notes);
  final String version; // e.g. 1.0.2 (without a leading "v")
  final String url; // release page, where the APK can be downloaded
  final String notes;
}

enum UpdateResult { available, upToDate, failed }

List<int> _numbers(String v) => RegExp(r'\d+')
    .allMatches(v.split('+').first.split('-').first)
    .map((m) => int.parse(m.group(0)!))
    .toList();

/// True when [latest] (such as "v1.0.2") is a higher version than
/// [installed] (such as "1.0.1"). Compares the numbers one by one.
bool isNewerVersion(String latest, String installed) {
  final a = _numbers(latest), b = _numbers(installed);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Turns release notes into plain text for the update banner.
///
/// If the notes contain a hidden line `<!-- summary: ... -->`, that sentence is
/// shown. Otherwise HTML tags, images, links and Markdown symbols are removed,
/// so notes can start with a logo and headings.
String notesForBanner(String body) {
  final summary =
      RegExp(r'<!--\s*summary:\s*(.*?)\s*-->', dotAll: true).firstMatch(body);
  var t = summary != null ? summary.group(1)! : body;
  if (summary == null) {
    t = t
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'[*`]{1,3}'), '');
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > 240 ? '${t.substring(0, 240)}...' : t;
}

/// Reads GitHub's "latest release" answer. Null for drafts, pre-releases or
/// anything without a version tag.
UpdateInfo? parseRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  if (tag is! String || tag.trim().isEmpty) return null;
  if (json['draft'] == true || json['prerelease'] == true) return null;
  return UpdateInfo(
    tag.trim().replaceFirst(RegExp(r'^[vV]'), ''),
    (json['html_url'] as String?) ?? appDownloadUrl,
    notesForBanner((json['body'] as String?) ?? ''),
  );
}

/// Asks GitHub for the newest release at most once a day, and tells the UI
/// when it is newer than the installed version.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker(this._prefs);
  final SharedPreferences _prefs;

  static const _cacheKey = 'update_latest';
  static const _checkedKey = 'update_checked_at';
  static const _dismissedKey = 'update_dismissed';

  UpdateInfo? latest;
  String installed = '';

  bool get available =>
      latest != null && installed.isNotEmpty && isNewerVersion(latest!.version, installed);

  /// Banner shows for a newer version the person has not dismissed yet.
  bool get showBanner =>
      available && _prefs.getString(_dismissedKey) != latest!.version;

  Future<void> _loadInstalled() async {
    if (installed.isNotEmpty) return;
    installed = (await PackageInfo.fromPlatform()).version;
  }

  void _loadCache() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      latest = parseRelease(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  /// [force] ignores the once-a-day limit and brings a dismissed banner back.
  Future<UpdateResult> check({bool force = false}) async {
    if (kIsWeb) return UpdateResult.failed;
    try {
      await _loadInstalled();
      _loadCache();

      final last = _prefs.getInt(_checkedKey) ?? 0;
      final due = DateTime.now().millisecondsSinceEpoch - last > 24 * 3600 * 1000;
      if (force || due) {
        final body = await _fetch(); // null: no release published yet
        final info = body == null
            ? null
            : parseRelease(jsonDecode(body) as Map<String, dynamic>);
        latest = info;
        if (body != null && info != null) {
          await _prefs.setString(_cacheKey, body);
        } else {
          await _prefs.remove(_cacheKey);
        }
        await _prefs.setInt(_checkedKey, DateTime.now().millisecondsSinceEpoch);
        if (force) await _prefs.remove(_dismissedKey);
      }
      notifyListeners();
      return available ? UpdateResult.available : UpdateResult.upToDate;
    } catch (_) {
      notifyListeners(); // a cached release may still be worth showing
      return UpdateResult.failed;
    }
  }

  Future<String?> _fetch() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(releasesApiUrl));
      req.headers
        ..set('Accept', 'application/vnd.github+json')
        ..set('User-Agent', 'aaj-kya-banega');
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode == 404) return null; // no release yet
      if (res.statusCode != 200) {
        throw HttpException('GitHub answered ${res.statusCode}');
      }
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  void dismiss() {
    if (latest != null) _prefs.setString(_dismissedKey, latest!.version);
    notifyListeners();
  }

  Future<void> openDownload() async {
    final url = latest?.url ?? appDownloadUrl;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
