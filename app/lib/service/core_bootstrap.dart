import 'dart:io';
import 'dart:isolate';

import 'package:core/native_isolate.dart';
import 'package:path_provider/path_provider.dart';

import '../credentials.dart';
import '../host/accounts.dart';
import '../host/fake_media.dart';

/// Paths shared by the app's host and a run's (`push_run.dart`). Each account has its own
/// TDLib database and its own app database; account 1 keeps the paths the app has always
/// used, so an install that predates several accounts finds its data where it left it.
/// Without an [accountId] the account the switcher last chose is used, which is how the
/// two hosts end up on the same one.
Future<({String support, String tdlib, String db})> appPaths([
  int? accountId,
]) async {
  final support = (await getApplicationSupportDirectory()).path;
  final store = AccountStore(support);
  final id = accountId ?? await store.activeId();
  return (support: support, tdlib: store.tdlibOf(id), db: store.dbOf(id));
}

/// The core's bootstrap for the account at [p]; the fake build points it at the sample
/// media that [installFakeMedia] copied there.
CoreBootstrap coreBootstrap(
  ({String support, String tdlib, String db}) p, {
  List<OtherAccount> others = const [],
  SendPort? replyTo,
}) => CoreBootstrap(
  apiId: tgApiId,
  apiHash: tgApiHash,
  databaseDirectory: p.tdlib,
  filesDirectory: '${p.tdlib}/files',
  appDatabasePath: p.db,
  useTestDc: tgTestDc,
  deviceModel: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
  systemVersion: Platform.operatingSystemVersion,
  fakeMediaDirectory: tgFake ? fakeMediaDirectory(p.support) : null,
  others: others,
  replyTo: replyTo,
);
