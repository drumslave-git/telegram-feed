/// Sync of feeds, rules and settings between devices through one JSON file in the user's
/// own cloud storage (ARCHITECTURE.md section 5.5). No server of ours: every device pulls
/// the file, merges it with its database item by item (newest edit wins, deletions are
/// remembered as tombstones), applies the result locally and writes the file back.
library;

import 'dart:convert';

import 'package:app_db/app_db.dart';

/// Where the sync file lives (Google Drive's app data folder in the app; memory in tests).
abstract interface class SyncStore {
  /// The file's content, or null when it does not exist yet.
  Future<String?> read();
  Future<void> write(String content);
}

/// Sync could not run or the file is unusable. The local database is left untouched.
final class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

  @override
  String toString() => 'SyncException: $message';
}

/// Settings that travel between devices. Device state (AI failure note, sync status) and
/// secrets stay local; the AI API key is in the keystore and never in the database at all.
bool isSyncedSetting(String key) =>
    key == SettingKeys.themeMode ||
    key == SettingKeys.syncReadToTelegram ||
    key.startsWith('tts.') ||
    key == 'ai.baseUrl' ||
    key == 'ai.model';

final class SyncedSource {
  const SyncedSource(this.chatId, this.title, this.username);
  final int chatId;
  final String title;
  final String? username;

  Map<String, Object?> toJson() => {
    'chatId': chatId,
    'title': title,
    'username': username,
  };

  static SyncedSource fromJson(Map<String, Object?> m) => SyncedSource(
    m['chatId'] as int,
    m['title'] as String,
    m['username'] as String?,
  );
}

/// A feed with its ordered sources; the unit of merging for feeds.
final class SyncedFeed {
  const SyncedFeed({
    required this.id,
    required this.name,
    required this.position,
    required this.updatedAt,
    required this.sources,
  });
  final String id;
  final String name;
  final int position;
  final int updatedAt;
  final List<SyncedSource> sources;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'position': position,
    'updatedAt': updatedAt,
    'sources': [for (final s in sources) s.toJson()],
  };

  static SyncedFeed fromJson(Map<String, Object?> m) => SyncedFeed(
    id: m['id'] as String,
    name: m['name'] as String,
    position: m['position'] as int,
    updatedAt: m['updatedAt'] as int,
    sources: [
      for (final s in m['sources'] as List)
        SyncedSource.fromJson((s as Map).cast<String, Object?>()),
    ],
  );
}

/// A rule. [fields] is the row as JSON (everything except the local id and sync columns).
final class SyncedRule {
  const SyncedRule({
    required this.id,
    required this.updatedAt,
    required this.fields,
  });
  final String id;
  final int updatedAt;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() => {
    'id': id,
    'updatedAt': updatedAt,
    ...fields,
  };

  static SyncedRule fromJson(Map<String, Object?> m) => SyncedRule(
    id: m['id'] as String,
    updatedAt: m['updatedAt'] as int,
    fields: {...m}
      ..remove('id')
      ..remove('updatedAt'),
  );

  static SyncedRule fromRow(Rule r) => SyncedRule(
    id: r.syncId!,
    updatedAt: _ms(r.updatedAt ?? r.createdAt),
    fields: {
      'name': r.name,
      'enabled': r.enabled,
      'scopeKind': r.scopeKind,
      'scopeChatId': r.scopeChatId,
      'conditionJson': r.conditionJson,
      'priority': r.priority,
      'readAloud': r.readAloud,
      'scheduleJson': r.scheduleJson,
      'semanticPrompt': r.semanticPrompt,
      'createdAt': _ms(r.createdAt),
    },
  );

  RulesCompanion toCompanion() => RulesCompanion.insert(
    name: fields['name'] as String,
    enabled: Value(fields['enabled'] as bool? ?? true),
    scopeKind: fields['scopeKind'] as String,
    scopeChatId: Value(fields['scopeChatId'] as int?),
    conditionJson: fields['conditionJson'] as String,
    priority: fields['priority'] as String,
    readAloud: Value(fields['readAloud'] as bool? ?? false),
    scheduleJson: Value(fields['scheduleJson'] as String?),
    semanticPrompt: Value(fields['semanticPrompt'] as String?),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      fields['createdAt'] as int? ?? updatedAt,
    ),
    syncId: Value(id),
    updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(updatedAt)),
  );
}

final class SyncedSetting {
  const SyncedSetting(this.key, this.value, this.updatedAt);
  final String key;
  final String value;
  final int updatedAt;

  Map<String, Object?> toJson() => {
    'key': key,
    'value': value,
    'updatedAt': updatedAt,
  };

  static SyncedSetting fromJson(Map<String, Object?> m) => SyncedSetting(
    m['key'] as String,
    m['value'] as String,
    m['updatedAt'] as int,
  );
}

/// A remembered deletion of a feed or rule.
final class SyncedTombstone {
  const SyncedTombstone(this.kind, this.id, this.deletedAt);
  final String kind;
  final String id;
  final int deletedAt;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'deletedAt': deletedAt,
  };

  static SyncedTombstone fromJson(Map<String, Object?> m) => SyncedTombstone(
    m['kind'] as String,
    m['id'] as String,
    m['deletedAt'] as int,
  );
}

int _ms(DateTime t) => t.millisecondsSinceEpoch;

/// Everything that syncs, as one value. Times are Unix milliseconds.
final class SyncSnapshot {
  const SyncSnapshot({
    this.feeds = const [],
    this.rules = const [],
    this.settings = const [],
    this.tombstones = const [],
  });
  final List<SyncedFeed> feeds;
  final List<SyncedRule> rules;
  final List<SyncedSetting> settings;
  final List<SyncedTombstone> tombstones;

  static const formatVersion = 1;

  /// How long deletions are remembered. A device offline for longer may bring an item back.
  static const tombstoneLifetime = Duration(days: 180);

  /// Canonical JSON: lists are sorted, so equal snapshots encode equally.
  String encode() => jsonEncode({
    'version': formatVersion,
    'feeds': [
      for (final f in [...feeds]..sort((a, b) => a.id.compareTo(b.id)))
        f.toJson(),
    ],
    'rules': [
      for (final r in [...rules]..sort((a, b) => a.id.compareTo(b.id)))
        r.toJson(),
    ],
    'settings': [
      for (final s in [...settings]..sort((a, b) => a.key.compareTo(b.key)))
        s.toJson(),
    ],
    'tombstones': [
      for (final t in [
        ...tombstones,
      ]..sort((a, b) => '${a.kind}/${a.id}'.compareTo('${b.kind}/${b.id}')))
        t.toJson(),
    ],
  });

  /// Throws [SyncException] when the file is not a snapshot this version understands.
  static SyncSnapshot decode(String content) {
    try {
      final m = jsonDecode(content) as Map<String, Object?>;
      final version = m['version'] as int;
      if (version > formatVersion) {
        throw const SyncException(
          'The sync file was written by a newer version of the app. Update this device.',
        );
      }
      List<T> list<T>(String key, T Function(Map<String, Object?>) f) => [
        for (final i in (m[key] as List?) ?? const [])
          f((i as Map).cast<String, Object?>()),
      ];
      return SyncSnapshot(
        feeds: list('feeds', SyncedFeed.fromJson),
        rules: list('rules', SyncedRule.fromJson),
        settings: list('settings', SyncedSetting.fromJson),
        tombstones: list('tombstones', SyncedTombstone.fromJson),
      );
    } on SyncException {
      rethrow;
    } catch (e) {
      throw SyncException('The sync file cannot be read: $e');
    }
  }

  /// Item-wise merge. For every feed, rule and setting the newer edit wins ([a] on a tie);
  /// a deletion wins over edits made before it, and an edit made after it brings the item
  /// back. Commutative apart from ties, so devices converge whatever the order of syncs.
  static SyncSnapshot merge(
    SyncSnapshot a,
    SyncSnapshot b, {
    required DateTime now,
  }) {
    final graves = <String, SyncedTombstone>{};
    for (final t in [...a.tombstones, ...b.tombstones]) {
      final k = '${t.kind}/${t.id}';
      final old = graves[k];
      if (old == null || t.deletedAt > old.deletedAt) graves[k] = t;
    }

    Map<String, T> newest<T>(
      Iterable<T> items,
      String Function(T) id,
      int Function(T) at,
    ) {
      final out = <String, T>{};
      for (final i in items) {
        final old = out[id(i)];
        if (old == null || at(i) > at(old)) out[id(i)] = i;
      }
      return out;
    }

    final feeds = newest<SyncedFeed>(
      [...a.feeds, ...b.feeds],
      (f) => f.id,
      (f) => f.updatedAt,
    );
    final rules = newest<SyncedRule>(
      [...a.rules, ...b.rules],
      (r) => r.id,
      (r) => r.updatedAt,
    );
    final settings = newest<SyncedSetting>(
      [...a.settings, ...b.settings],
      (s) => s.key,
      (s) => s.updatedAt,
    );

    void settle<T>(String kind, Map<String, T> items, int Function(T) at) {
      for (final id in items.keys.toList()) {
        final grave = graves['$kind/$id'];
        if (grave == null) continue;
        if (grave.deletedAt >= at(items[id] as T)) {
          items.remove(id);
        } else {
          graves.remove('$kind/$id'); // edited after the deletion: it lives
        }
      }
    }

    settle<SyncedFeed>('feed', feeds, (f) => f.updatedAt);
    settle<SyncedRule>('rule', rules, (r) => r.updatedAt);

    final cutoff = _ms(now.subtract(tombstoneLifetime));
    return SyncSnapshot(
      feeds: feeds.values.toList(),
      rules: rules.values.toList(),
      settings: settings.values.toList(),
      tombstones: [
        for (final t in graves.values)
          if (t.deletedAt >= cutoff) t,
      ],
    );
  }
}

/// What one sync run did.
final class SyncResult {
  const SyncResult({required this.pulled, required this.pushed});

  /// Items changed in the local database.
  final int pulled;

  /// Whether the file was written.
  final bool pushed;
}

/// Pull, merge, apply, push. Safe to run from several devices at any time: a concurrent
/// write can only hide another device's edits until that device syncs again, because every
/// run merges the device's whole local state back in.
final class SyncEngine {
  SyncEngine({
    required this.db,
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final SyncStore store;
  final DateTime Function() _clock;

  /// The local database as a snapshot.
  Future<SyncSnapshot> exportLocal() async {
    final watched = {for (final w in await db.allWatched()) w.chatId: w};
    final feeds = <SyncedFeed>[];
    for (final f in await db.allFeeds()) {
      final id = f.syncId;
      if (id == null) continue;
      feeds.add(
        SyncedFeed(
          id: id,
          name: f.name,
          position: f.position,
          updatedAt: _ms(f.updatedAt ?? f.createdAt),
          sources: [
            for (final s in await db.sourcesOf(f.id))
              SyncedSource(
                s.chatId,
                watched[s.chatId]?.title ?? '',
                watched[s.chatId]?.username,
              ),
          ],
        ),
      );
    }
    return SyncSnapshot(
      feeds: feeds,
      rules: [
        for (final r in await db.allRules())
          if (r.syncId != null) SyncedRule.fromRow(r),
      ],
      settings: [
        for (final s in await db.allSettings())
          if (isSyncedSetting(s.key))
            SyncedSetting(s.key, s.value, _ms(s.updatedAt ?? DateTime(2000))),
      ],
      tombstones: [
        for (final t in await db.allTombstones())
          SyncedTombstone(t.kind, t.syncId, _ms(t.deletedAt)),
      ],
    );
  }

  Future<SyncResult> sync() async {
    final now = _clock();
    final local = await exportLocal();
    final content = await store.read();
    final remote = content == null
        ? const SyncSnapshot()
        : SyncSnapshot.decode(content);
    final merged = SyncSnapshot.merge(local, remote, now: now);
    final pulled = await _apply(local, merged);
    await db.pruneTombstones(now.subtract(SyncSnapshot.tombstoneLifetime));
    final pushed = content == null || merged.encode() != remote.encode();
    if (pushed) await store.write(merged.encode());
    return SyncResult(pulled: pulled, pushed: pushed);
  }

  /// Brings the database to [merged]; returns how many items changed.
  Future<int> _apply(SyncSnapshot local, SyncSnapshot merged) async {
    var changed = 0;
    DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

    final localFeeds = {for (final f in local.feeds) f.id: f};
    for (final f in merged.feeds) {
      final mine = localFeeds[f.id];
      if (mine != null && jsonEncode(mine.toJson()) == jsonEncode(f.toJson())) {
        continue;
      }
      await db.applySyncedFeed(
        syncId: f.id,
        name: f.name,
        position: f.position,
        updatedAt: at(f.updatedAt),
        sources: [
          for (final s in f.sources)
            (chatId: s.chatId, title: s.title, username: s.username),
        ],
      );
      changed++;
    }

    final localRules = {for (final r in local.rules) r.id: r};
    for (final r in merged.rules) {
      final mine = localRules[r.id];
      if (mine != null && jsonEncode(mine.toJson()) == jsonEncode(r.toJson())) {
        continue;
      }
      await db.applySyncedRule(r.toCompanion());
      changed++;
    }

    final localSettings = {for (final s in local.settings) s.key: s};
    for (final s in merged.settings) {
      final mine = localSettings[s.key];
      if (mine != null &&
          mine.value == s.value &&
          mine.updatedAt == s.updatedAt) {
        continue;
      }
      await db.applySyncedSetting(s.key, s.value, at(s.updatedAt));
      if (mine?.value != s.value) changed++;
    }

    final localGraves = {
      for (final t in local.tombstones) '${t.kind}/${t.id}': t,
    };
    for (final t in merged.tombstones) {
      final known = localGraves['${t.kind}/${t.id}'];
      final alive = t.kind == 'feed'
          ? localFeeds.containsKey(t.id)
          : localRules.containsKey(t.id);
      if (known != null && known.deletedAt == t.deletedAt && !alive) continue;
      await db.applySyncedDeletion(t.kind, t.id, at(t.deletedAt));
      if (alive) changed++;
    }
    return changed;
  }
}
