import 'dart:convert';

import 'package:app_db/app_db.dart';

/// The words the reader searched for last, which every search bar offers when it opens, as
/// the official app does. Kept in `settings` (one list for the whole app), newest first.
class RecentSearches {
  const RecentSearches(this.db, {this.limit = 10});
  final AppDatabase db;

  /// How many are kept; the official app keeps a handful.
  final int limit;

  Future<List<String>> load() async =>
      decode(await db.setting(SettingKeys.recentSearches));

  /// Puts [query] on top, without a second copy of it; blank words are not kept.
  Future<List<String>> remember(String query) async {
    final words = query.trim();
    if (words.isEmpty) return load();
    final kept = [
      words,
      for (final old in await load())
        if (old.toLowerCase() != words.toLowerCase()) old,
    ];
    final cut = kept.take(limit).toList();
    await db.setSetting(SettingKeys.recentSearches, jsonEncode(cut));
    return cut;
  }

  Future<void> clear() async =>
      db.setSetting(SettingKeys.recentSearches, jsonEncode(const <String>[]));

  /// Broken or missing JSON is simply no history.
  static List<String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is String && e.trim().isNotEmpty) e,
      ];
    } on FormatException {
      return const [];
    }
  }
}
