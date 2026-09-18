/// Release versioning from conventional commits (`feat(P1-8): ...`, `fix: ...`).
///
/// Rules: a breaking change (`type!:` or a `BREAKING CHANGE:` footer) raises the major
/// version, or the minor one while the major is 0; `feat` raises the minor; `fix` and `perf`
/// raise the patch. Commits of other types (docs, chore, test, ci, refactor, ...) alone
/// do not make a release.
library;

enum Bump { none, patch, minor, major }

final class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);
  final int major;
  final int minor;
  final int patch;

  /// Parses `1.2.3`, `v1.2.3` and ignores a build or pre-release suffix (`0.1.0+1`).
  static Version parse(String text) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(text.trim());
    if (m == null) throw FormatException('not a version: "$text"');
    return Version(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  Version bumped(Bump bump) => switch (bump) {
    Bump.none => this,
    Bump.patch => Version(major, minor, patch + 1),
    Bump.minor => Version(major, minor + 1, 0),
    // 0.x: the API is not stable yet, so a breaking change is a minor step.
    Bump.major =>
      major == 0 ? Version(0, minor + 1, 0) : Version(major + 1, 0, 0),
  };

  @override
  int compareTo(Version other) => major != other.major
      ? major.compareTo(other.major)
      : minor != other.minor
      ? minor.compareTo(other.minor)
      : patch.compareTo(other.patch);

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// One commit, as far as releases care.
final class Commit {
  const Commit({required this.hash, required this.subject, this.body = ''});
  final String hash;
  final String subject;
  final String body;

  static final _header = RegExp(r'^([a-zA-Z]+)(?:\(([^)]*)\))?(!)?:\s*(.+)$');

  RegExpMatch? get _match => _header.firstMatch(subject.trim());

  /// `feat`, `fix`, ... or null for a commit that does not follow the convention.
  String? get type => _match?[1]?.toLowerCase();
  String? get scope => _match?[2];
  String get description => _match?[4] ?? subject.trim();

  bool get isBreaking =>
      _match?[3] == '!' ||
      RegExp(r'^BREAKING[ -]CHANGE:', multiLine: true).hasMatch(body);

  Bump get bump {
    if (isBreaking) return Bump.major;
    return switch (type) {
      'feat' => Bump.minor,
      'fix' || 'perf' => Bump.patch,
      _ => Bump.none,
    };
  }
}

Bump bumpFor(Iterable<Commit> commits) => commits.fold(
  Bump.none,
  (max, c) => c.bump.index > max.index ? c.bump : max,
);

/// The version to release for [commits] made since [last] was released, or null when
/// nothing in them warrants a release. Without an earlier release, [initial] is released
/// as it is (whatever the commits are).
Version? nextVersion({
  required Version? last,
  required Version initial,
  required Iterable<Commit> commits,
}) {
  if (last == null) return initial;
  final bump = bumpFor(commits);
  return bump == Bump.none ? null : last.bumped(bump);
}

/// Markdown release notes: what users notice first, housekeeping left out.
String changelog(Iterable<Commit> commits) {
  final sections = <String, List<Commit>>{
    'Breaking changes': [
      for (final c in commits)
        if (c.isBreaking) c,
    ],
    'Features': [
      for (final c in commits)
        if (c.type == 'feat' && !c.isBreaking) c,
    ],
    'Fixes': [
      for (final c in commits)
        if ((c.type == 'fix' || c.type == 'perf') && !c.isBreaking) c,
    ],
  };
  final out = StringBuffer();
  for (final MapEntry(key: title, value: list) in sections.entries) {
    if (list.isEmpty) continue;
    out.writeln('### $title');
    for (final c in list) {
      final scope = c.scope == null ? '' : '**${c.scope}:** ';
      out.writeln('- $scope${c.description} (${c.hash})');
    }
    out.writeln();
  }
  return out.isEmpty ? 'Maintenance only.\n' : out.toString();
}

/// Parses `git log --format=%h%x1f%s%x1f%b%x1e` output.
List<Commit> parseGitLog(String log) => [
  for (final record in log.split('\x1e'))
    if (record.trim().isNotEmpty)
      if (record.trim().split('\x1f') case [
        final hash,
        final subject,
        ...final rest,
      ])
        Commit(hash: hash, subject: subject, body: rest.join('\n')),
];
