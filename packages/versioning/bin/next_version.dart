// Decides whether the current commit gets a release and with which version.
//
//   dart run versioning:next_version [--notes <file>] [--github-output <file>]
//
// Looks for the newest tag `vX.Y.Z` reachable from HEAD and reads the conventional
// commits since then. Prints `release=true|false`, `version=X.Y.Z`, `tag=vX.Y.Z` (also
// appended to --github-output for GitHub Actions) and writes the changelog to --notes.
// Without any earlier tag the version in app/pubspec.yaml is released as it is.
import 'dart:io';

import 'package:versioning/versioning.dart';

String _git(List<String> args) {
  final r = Process.runSync('git', args);
  if (r.exitCode != 0) {
    stderr.writeln('git ${args.join(' ')} failed: ${r.stderr}');
    exit(2);
  }
  return (r.stdout as String).trim();
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

void main(List<String> args) {
  final root = _git(['rev-parse', '--show-toplevel']);
  final tags =
      _git(['tag', '--merged', 'HEAD', '--list', 'v[0-9]*'])
          .split('\n')
          .where((t) => RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(t.trim()))
          .map((t) => Version.parse(t))
          .toList()
        ..sort();
  final last = tags.isEmpty ? null : tags.last;

  final pubspec = File('$root/app/pubspec.yaml').readAsStringSync();
  final initial = Version.parse(
    RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)![1]!,
  );

  final range = last == null ? 'HEAD' : 'v$last..HEAD';
  final commits = parseGitLog(
    _git(['log', range, '--no-merges', '--format=%h%x1f%s%x1f%b%x1e']),
  );
  final alreadyTagged =
      last != null &&
      _git(['rev-list', '-n', '1', 'v$last']) == _git(['rev-parse', 'HEAD']);
  final next = alreadyTagged
      ? null
      : nextVersion(last: last, initial: initial, commits: commits);

  final lines = [
    'release=${next != null}',
    'version=${next ?? last ?? initial}',
    'tag=v${next ?? last ?? initial}',
    'previous=${last == null ? '' : 'v$last'}',
  ];
  lines.forEach(stdout.writeln);
  final output = _arg(args, '--github-output');
  if (output != null) {
    File(output)
        .writeAsStringSync('${lines.join('\n')}\n', mode: FileMode.append);
  }
  final notes = _arg(args, '--notes');
  if (notes != null) File(notes).writeAsStringSync(changelog(commits));
}
