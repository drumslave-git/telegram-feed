import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../l10n/l10n.dart';

/// Settings for AI semantic rules (ARCHITECTURE 6.4). The endpoint and model live in the
/// app database; the API key lives in the platform keystore.
abstract final class AiKeys {
  static const baseUrl = 'ai.baseUrl';
  static const model = 'ai.model';

  /// JSON `{message, at}` while semantic checks are failing; absent when they work.
  static const lastError = 'ai.lastError';

  /// Name of the key in the [SecretStore].
  static const apiKeySecret = 'ai.apiKey';
}

/// Asks the AI endpoint which of [criteria] a post matches (positions). Throws
/// [SemanticException] when the check cannot be done.
typedef SemanticCheck = Future<Set<int>> Function(
  String postText,
  List<String> criteria,
);

/// Small secrets outside the database. Abstract so tests need no platform keystore.
abstract interface class SecretStore {
  Future<String?> read(String key);

  /// Null or empty deletes the entry.
  Future<void> write(String key, String? value);
}

/// Android Keystore-backed storage through `flutter_secure_storage`.
final class SecureSecretStore implements SecretStore {
  const SecureSecretStore();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null || value.isEmpty
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);
}

Future<AiConfig> loadAiConfig(AppDatabase db, SecretStore secrets) async =>
    AiConfig(
      baseUrl: await db.setting(AiKeys.baseUrl) ?? '',
      model: await db.setting(AiKeys.model) ?? '',
      apiKey: await secrets.read(AiKeys.apiKeySecret) ?? '',
    );

/// Why a semantic check could not be done, in the reader's language.
String semanticProblemText(
  AppLocalizations l10n,
  SemanticProblem problem, {
  String detail = '',
  int statusCode = 0,
}) => switch (problem) {
  SemanticProblem.notSetUp => l10n.semanticProblemNotSetUp,
  SemanticProblem.unreachable => l10n.semanticProblemUnreachable(detail),
  SemanticProblem.httpStatus => l10n.semanticProblemHttpStatus(
    statusCode,
    detail,
  ),
  SemanticProblem.unexpectedAnswer => l10n.semanticProblemUnexpectedAnswer,
  SemanticProblem.emptyAnswer => l10n.semanticProblemEmptyAnswer,
};

extension SemanticExceptionText on SemanticException {
  /// What went wrong, in the reader's language; [message] is the English for logs.
  String describe(AppLocalizations l10n) => semanticProblemText(
    l10n,
    problem,
    detail: detail,
    statusCode: statusCode,
  );
}

/// The last failure of a semantic check, as shown on the rules screen.
final class AiFailure {
  const AiFailure(
    this.message,
    this.at, {
    this.problem,
    this.detail = '',
    this.statusCode = 0,
  });

  /// In English; what a failure recorded without a [problem] shows.
  final String message;
  final DateTime at;
  final SemanticProblem? problem;
  final String detail;
  final int statusCode;

  /// The failure in the reader's language.
  String describe(AppLocalizations l10n) {
    final p = problem;
    return p == null
        ? message
        : semanticProblemText(l10n, p, detail: detail, statusCode: statusCode);
  }

  String encode() => jsonEncode({
    'message': message,
    'at': at.millisecondsSinceEpoch,
    if (problem != null) 'problem': problem!.name,
    if (detail.isNotEmpty) 'detail': detail,
    if (statusCode != 0) 'status': statusCode,
  });

  static AiFailure? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json) as Map<String, Object?>;
      return AiFailure(
        m['message'] as String,
        DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        problem: SemanticProblem.values.asNameMap()[m['problem']],
        detail: m['detail'] as String? ?? '',
        statusCode: m['status'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Finishes rule matches that contain AI semantic rules: asks the model once per post and
/// keeps only the rules it confirms. When the check cannot be done those rules are skipped
/// for that post (keyword rules on the same post still fire) and the reason is recorded for
/// a quiet warning on the rules screen.
final class SemanticGate {
  SemanticGate({
    required this.db,
    required this.secrets,
    SemanticClient? client,
    DateTime Function()? clock,
  }) : _client = client ?? SemanticClient(),
       _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final SecretStore secrets;
  final SemanticClient _client;
  final DateTime Function() _clock;
  bool? _failing;

  /// Which of [criteria] the post matches. Throws [SemanticException].
  Future<Set<int>> check(String postText, List<String> criteria) async =>
      _client.matching(
        config: await loadAiConfig(db, secrets),
        postText: postText,
        criteria: criteria,
      );

  /// The match with its semantic rules decided, or null when no rule is left.
  Future<MatchEvent?> resolve(MatchEvent match) async {
    final pending = match.pendingSemantic;
    if (pending.isEmpty) return match;
    Set<int> confirmed;
    try {
      final hits = await check(match.post.text, [
        for (final (_, prompt) in pending) prompt,
      ]);
      confirmed = {for (final h in hits) pending[h].$1};
      if (_failing != false) {
        _failing = false;
        await db.deleteSetting(AiKeys.lastError);
      }
    } on SemanticException catch (e) {
      confirmed = const {};
      _failing = true;
      await db.setSetting(
        AiKeys.lastError,
        AiFailure(
          e.message,
          _clock(),
          problem: e.problem,
          detail: e.detail,
          statusCode: e.statusCode,
        ).encode(),
      );
    }
    return match.withSemanticVerdicts(confirmed);
  }
}
