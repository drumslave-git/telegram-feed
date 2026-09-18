import 'package:test/test.dart';
import 'package:versioning/versioning.dart';

Commit c(String subject, {String body = '', String hash = 'abc1234'}) =>
    Commit(hash: hash, subject: subject, body: body);

void main() {
  test('versions parse, compare and bump', () {
    expect(Version.parse('v1.2.3'), const Version(1, 2, 3));
    expect(Version.parse('0.1.0+1').toString(), '0.1.0');
    expect(() => Version.parse('nightly'), throwsFormatException);
    expect(
      const Version(0, 9, 9).compareTo(const Version(0, 10, 0)),
      lessThan(0),
    );
    expect(const Version(1, 2, 3).bumped(Bump.patch), const Version(1, 2, 4));
    expect(const Version(1, 2, 3).bumped(Bump.minor), const Version(1, 3, 0));
    expect(const Version(1, 2, 3).bumped(Bump.major), const Version(2, 0, 0));
    // Before 1.0 a breaking change is a minor step.
    expect(const Version(0, 4, 2).bumped(Bump.major), const Version(0, 5, 0));
  });

  test('commit types decide the bump; the biggest one wins', () {
    expect(c('feat(P4-1): Drive sync').bump, Bump.minor);
    expect(c('fix(S-4): fallback to the browser').bump, Bump.patch);
    expect(c('perf: faster merge').bump, Bump.patch);
    expect(c('docs(plan): next task').bump, Bump.none);
    expect(c('chore: drop the web target').bump, Bump.none);
    expect(c('Merge branch main').bump, Bump.none);
    expect(c('feat!: new rule format').bump, Bump.major);
    expect(
      c(
        'fix: migrate',
        body: 'BREAKING CHANGE: schema v5 cannot be downgraded',
      ).bump,
      Bump.major,
    );
    expect(
      bumpFor([c('docs: x'), c('fix: y'), c('feat: z'), c('test: w')]),
      Bump.minor,
    );
    expect(bumpFor([c('docs: x'), c('test: w')]), Bump.none);
  });

  test('next version: first release, bumps, and nothing to release', () {
    const initial = Version(0, 1, 0);
    expect(
      nextVersion(last: null, initial: initial, commits: [c('docs: readme')]),
      initial,
    );
    expect(
      nextVersion(
        last: initial,
        initial: initial,
        commits: [c('feat: a'), c('fix: b')],
      ),
      const Version(0, 2, 0),
    );
    expect(
      nextVersion(
        last: const Version(0, 2, 0),
        initial: initial,
        commits: [c('fix: b')],
      ),
      const Version(0, 2, 1),
    );
    expect(
      nextVersion(
        last: initial,
        initial: initial,
        commits: [c('docs: a'), c('ci: b')],
      ),
      isNull,
    );
  });

  test('changelog groups features and fixes, skips housekeeping', () {
    final notes = changelog([
      c('feat(P4-2): AI semantic rules', hash: '1111111'),
      c('docs: plan'),
      c('fix(S-7): Listen jumps the queue', hash: '2222222'),
      c('feat!: rules v2', hash: '3333333'),
    ]);
    expect(notes, contains('### Breaking changes\n- rules v2 (3333333)'));
    expect(
      notes,
      contains('### Features\n- **P4-2:** AI semantic rules (1111111)'),
    );
    expect(
      notes,
      contains('### Fixes\n- **S-7:** Listen jumps the queue (2222222)'),
    );
    expect(notes, isNot(contains('plan')));
    expect(changelog([c('docs: only')]), 'Maintenance only.\n');
  });

  test('git log records are parsed with bodies', () {
    final commits = parseGitLog(
      'aaa1111\x1ffeat: one\x1fbody line\n\nBREAKING CHANGE: yes\x1e\n'
      'bbb2222\x1ffix: two\x1f\x1e\n',
    );
    expect(commits.map((c) => c.hash), ['aaa1111', 'bbb2222']);
    expect(commits.first.isBreaking, isTrue);
    expect(commits.last.bump, Bump.patch);
  });
}
