import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:fake_telegram/fake_telegram.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/push_registration.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// A logged-in account the core serves, with the pushes it was registered for.
final class _Account extends ChannelsGateway implements PushGateway {
  _Account(this.userId) : super(const []);
  final int userId;

  /// `token:other ids`, one per registration.
  final registered = <String>[];

  @override
  Future<UserInfo> me() async => UserInfo(id: userId, firstName: 'U$userId');

  @override
  Future<void> registerPush(
    String token, {
    List<int> otherUserIds = const [],
  }) async => registered.add('$token:${otherUserIds.join(',')}');

  @override
  Future<void> processPush(String payload) async {}
}

void main() {
  late _Account ann;
  late _Account bob;
  late CoreClient annClient;
  late CoreClient bobClient;
  late AppDatabase annDb;
  late AppDatabase bobDb;

  setUp(() async {
    ann = _Account(11);
    bob = _Account(22);
    annClient = await CoreClient.connect(CoreServer(ann).sendPort);
    bobClient = await CoreClient.connect(CoreServer(bob).sendPort);
    annDb = AppDatabase(NativeDatabase.memory());
    bobDb = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await annClient.close();
    await bobClient.close();
    await annDb.close();
    await bobDb.close();
  });

  Future<void> register(String? token) => PushRegistration.ensure(
    main: annClient,
    mainDb: annDb,
    others: [(client: bobClient, db: bobDb)],
    token: () async => token,
    log: (_) {},
  );

  test('every logged-in account registers the token once, naming the others, '
      'and again when the token changes', () async {
    await register('t1');
    expect(ann.registered, ['t1:22']);
    expect(bob.registered, ['t1:11']);

    await register('t1');
    expect(ann.registered, hasLength(1));
    expect(bob.registered, hasLength(1));

    await register('t2');
    expect(ann.registered.last, 't2:22');
    expect(bob.registered.last, 't2:11');
  });

  test(
    'without a token (no push in this build) nothing is registered',
    () async {
      await register(null);
      expect(ann.registered, isEmpty);
      expect(bob.registered, isEmpty);
    },
  );

  test('an account that leaves changes what the others name', () async {
    await register('t1');
    await PushRegistration.ensure(
      main: annClient,
      mainDb: annDb,
      token: () async => 't1',
      log: (_) {},
    );
    expect(ann.registered.last, 't1:');
  });
}
