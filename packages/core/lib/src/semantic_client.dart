import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where AI semantic rules are checked: any OpenAI-compatible chat completions endpoint
/// (OpenAI, OpenRouter, a local Ollama, ...). Entered by the user in Settings.
final class AiConfig {
  const AiConfig({
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
  });

  /// Up to and including the version segment, e.g. `https://api.openai.com/v1`.
  final String baseUrl;
  final String model;

  /// Sent as a bearer token; empty for local endpoints that need none.
  final String apiKey;

  bool get isComplete => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  Uri get chatCompletionsUri {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/chat/completions');
  }
}

/// The semantic check could not be done (no endpoint, network, bad key, odd answer).
/// Callers treat the semantic rules of that post as not matching (ARCHITECTURE 6.4).
final class SemanticException implements Exception {
  const SemanticException(this.message);
  final String message;

  @override
  String toString() => 'SemanticException: $message';
}

/// Asks the model which of the user's descriptions a post matches. One request per post,
/// however many semantic rules apply to it.
final class SemanticClient {
  SemanticClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _http = client ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  /// Longest post text sent to the model.
  static const maxPostChars = 4000;

  static const _system =
      'You filter posts from news channels for a user. You get numbered descriptions of '
      'what the user wants to be alerted about, and one post. Decide for each description '
      'whether the post is about it. Judge the meaning, in any language; do not require the '
      'same words. Reply with only the numbers of the matching descriptions separated by '
      'commas, or NONE if none matches. No other text.';

  static String userMessage(String postText, List<String> criteria) {
    final post = postText.length > maxPostChars
        ? postText.substring(0, maxPostChars)
        : postText;
    final list = [
      for (var i = 0; i < criteria.length; i++)
        '${i + 1}. ${criteria[i].trim()}',
    ].join('\n');
    return 'Descriptions:\n$list\n\nPost:\n"""\n$post\n"""';
  }

  /// Indices into [criteria] that the post matches. Throws [SemanticException].
  Future<Set<int>> matching({
    required AiConfig config,
    required String postText,
    required List<String> criteria,
  }) async {
    if (criteria.isEmpty) return const {};
    if (!config.isComplete) {
      throw const SemanticException(
        'The AI endpoint is not set up in Settings.',
      );
    }
    final http.Response res;
    try {
      res = await _http
          .post(
            config.chatCompletionsUri,
            headers: {
              'content-type': 'application/json',
              if (config.apiKey.isNotEmpty)
                'authorization': 'Bearer ${config.apiKey}',
            },
            body: jsonEncode({
              // Only the universally accepted fields: reasoning models need room to think
              // before the short answer (a token cap leaves them with empty content), and
              // some reject a custom temperature.
              'model': config.model.trim(),
              'messages': [
                {'role': 'system', 'content': _system},
                {'role': 'user', 'content': userMessage(postText, criteria)},
              ],
            }),
          )
          .timeout(timeout);
    } on Exception catch (e) {
      throw SemanticException('Could not reach the AI endpoint: $e');
    }
    if (res.statusCode != 200) {
      throw SemanticException(
        'The AI endpoint answered ${res.statusCode}: ${_errorText(res.body)}',
      );
    }
    final String answer;
    try {
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
      final choice = (json['choices'] as List).first as Map<String, Object?>;
      answer =
          ((choice['message'] as Map<String, Object?>)['content'] as String?) ??
          '';
    } catch (_) {
      throw const SemanticException(
        'The AI endpoint sent an unexpected answer.',
      );
    }
    if (answer.trim().isEmpty) {
      // Not the same as NONE: the model never got to its answer (cut off while reasoning).
      throw const SemanticException('The model returned an empty answer.');
    }
    return parseAnswer(answer, criteria.length);
  }

  /// `"1, 3"` → {0, 2}; `"NONE"` → {}. Numbers out of range are ignored.
  static Set<int> parseAnswer(String answer, int count) => {
    for (final m in RegExp(r'\d+').allMatches(answer))
      if (int.parse(m[0]!) case final n when n >= 1 && n <= count) n - 1,
  };

  static String _errorText(String body) {
    try {
      final json = jsonDecode(body);
      if (json case {'error': {'message': final String message}}) {
        return message;
      }
      if (json case {'error': final String message}) return message;
    } catch (_) {
      // not JSON
    }
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > 160 ? '${flat.substring(0, 160)}…' : flat;
  }

  void close() => _http.close();
}
