import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/auth/login_screens.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Gateway whose auth state the test drives by hand.
final class ScriptedGateway implements TelegramGateway {
  final _auth = StreamController<AuthState>.broadcast();
  final calls = <String>[];
  AuthState state = const AuthWaitPhoneNumber();
  TelegramException? nextError;

  void go(AuthState s) {
    state = s;
    _auth.add(s);
  }

  Future<void> _record(String call) async {
    calls.add(call);
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
  }

  @override
  Stream<AuthState> get authState async* {
    yield state;
    yield* _auth.stream;
  }

  @override
  Future<void> setPhoneNumber(String phone) => _record('phone:$phone');
  @override
  Future<void> checkCode(String code) => _record('code:$code');
  @override
  Future<void> setEmailAddress(String email) => _record('email:$email');
  @override
  Future<void> checkEmailCode(String code) => _record('emailCode:$code');
  @override
  Future<void> resendCode() => _record('resend');
  @override
  Future<void> checkPassword(String password) => _record('password:$password');
  @override
  Future<void> registerUser({
    required String firstName,
    String lastName = '',
  }) => _record('register:$firstName');
  @override
  Future<void> requestQrCode() => _record('qr');
  @override
  Future<void> logOut() => _record('logout');

  @override
  Stream<ChannelMembershipEvent> get membershipEvents => const Stream.empty();
  @override
  Stream<PostEvent> get postEvents => const Stream.empty();
  @override
  Stream<FileProgress> fileProgress(int fileId) => const Stream.empty();
  @override
  Future<List<Channel>> myChannels() async => const [];
  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async => const [];
  @override
  Future<List<Post>> historyAfter(
    int chatId, {
    required int afterMessageId,
    int limit = 30,
  }) async => const [];
  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async => const SearchPage();
  @override
  Future<int> messageIdByDate(int chatId, int unixDate) async => 0;
  @override
  Future<ChannelInfo> channelInfo(int chatId) async =>
      ChannelInfo(chatId: chatId);
  @override
  Future<void> countViews(int chatId, List<int> messageIds) async {}
  @override
  Future<void> markViewed(int chatId, List<int> messageIds) async {}
  @override
  Future<ReadState> readState(int chatId) async =>
      ReadState(chatId: chatId, lastReadMessageId: 0);
  @override
  Stream<ReadState> get readUpdates => const Stream.empty();
  @override
  Future<void> saveToSavedMessages(int chatId, List<int> messageIds) async {}
  @override
  Future<void> deleteFromSavedMessages(List<int> messageIds) async {}
  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) async => ref;
  @override
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
    int limit = 0,
  }) async => FileProgress(fileId: fileId, downloaded: 0, total: 0);
  @override
  Future<int> downloadedPrefix(int fileId, int offset) async => 0;
  @override
  Future<void> cancelDownload(int fileId) async {}
  @override
  Future<List<ChatFolder>> chatFolders() async => const [];
  @override
  Future<void> close() async {}

  @override
  Future<Thread?> discussion(int chatId, int messageId) async => null;
  @override
  Future<List<Comment>> threadHistory(
    Thread thread, {
    int fromMessageId = 0,
    int limit = 30,
  }) async => const [];
  @override
  Future<void> reply(Thread thread, String text, {int replyToId = 0}) async {}
  @override
  Stream<CommentsGone> get commentsGone => const Stream.empty();
  @override
  Future<void> editComment(Thread thread, int messageId, String text) async {}
  @override
  Future<void> deleteComments(Thread thread, List<int> messageIds) async {}
  @override
  Future<void> retryComment(Thread thread, int messageId) async {}
  @override
  Stream<Comment> get comments => const Stream.empty();
  @override
  Future<void> closeThread(Thread thread) async {}

  /// Ready, unless a test says otherwise.
  final connectionStatus = StreamController<ConnectionStatus>.broadcast();

  @override
  Stream<ConnectionStatus> get connection async* {
    yield ConnectionStatus.ready;
    yield* connectionStatus.stream;
  }

  @override
  Future<List<Channel>> similarChannels(int chatId) async => const [];
  @override
  Future<List<Channel>> archivedChannels() async => const [];
  @override
  Future<Channel> savedMessages() async =>
      const Channel(chatId: 42, title: 'Saved Messages');
  @override
  Future<CommentPage> searchThread(
    Thread thread, {
    required String query,
    int fromMessageId = 0,
    int limit = 30,
  }) async => const CommentPage();
  @override
  Future<List<Comment>> threadAround(
    Thread thread,
    int messageId, {
    int newer = 15,
    int older = 15,
  }) async => const [];
  @override
  Future<GlobalSearchPage> searchAllChannels({
    required String query,
    HistoryFilter filter = HistoryFilter.any,
    String offset = '',
    int limit = 30,
    int minDate = 0,
    int maxDate = 0,
  }) async => const GlobalSearchPage(posts: [], totalCount: 0, nextOffset: '');
  @override
  Future<List<Post>> pinnedPosts(int chatId) async => const [];
  @override
  Future<List<Post>> mediaCalendar(int chatId, {int fromMessageId = 0}) async =>
      const [];
  @override
  Future<void> markCommentsViewed(Thread thread, List<int> messageIds) async {}
  @override
  Future<void> markChannelUnread(int chatId, {required bool unread}) async {}
  @override
  Future<Map<HistoryFilter, int>> mediaCounts(int chatId) async => const {};
  @override
  Future<ReportStep> report(
    int chatId,
    List<int> messageIds, {
    String optionId = '',
    String text = '',
  }) async => const ReportDone();
  @override
  Future<FileRef> mapThumbnail(
    double latitude,
    double longitude, {
    int width = 600,
    int height = 300,
  }) async => const FileRef(id: 1, remoteId: 'map', size: 0);
  @override
  Future<Map<String, StickerMedia>> customEmoji(List<String> ids) async =>
      const {};
  @override
  Future<List<String>> availableReactions(int chatId, int messageId) async =>
      const ['👍', '🔥'];
  @override
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  }) async {}
  @override
  Future<UserInfo> me() async =>
      const UserInfo(id: 1, firstName: 'Test', phoneNumber: '+1');
  @override
  Future<StorageStats> storageStats() async =>
      const StorageStats(filesBytes: 0, fileCount: 0, databaseBytes: 0);
  @override
  Future<StorageStats> clearCache() => storageStats();
}

Widget app(TelegramGateway g) => MaterialApp(
  home: AuthGate(
    gateway: g,
    child: const Scaffold(body: Text('HOME')),
  ),
);

void main() {
  testWidgets('phone → code → password → home', (tester) async {
    final g = ScriptedGateway();
    await tester.pumpWidget(app(g));
    await tester.pump();
    expect(find.text('Log in to Telegram'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '+15551234567');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(g.calls, ['phone:+15551234567']);

    g.go(
      const AuthWaitCode(
        phoneNumber: '+15551234567',
        codeLength: 5,
        viaSms: true,
      ),
    );
    await tester.pump();
    expect(find.text('Enter the code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(g.calls.last, 'code:12345');

    g.go(const AuthWaitPassword(hint: 'pet'));
    await tester.pump();
    expect(find.textContaining('Hint: pet'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(g.calls.last, 'password:secret');

    g.go(const AuthReady());
    await tester.pump();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('Telegram errors are shown inline and the field stays usable', (
    tester,
  ) async {
    final g = ScriptedGateway()
      ..nextError = const TelegramException(400, 'PHONE_CODE_INVALID');
    g.state = const AuthWaitCode(
      phoneNumber: '+1',
      codeLength: 5,
      viaSms: true,
    );
    await tester.pumpWidget(app(g));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '00000');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Wrong code.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('an account that logs in by email: the address, then its code', (
    tester,
  ) async {
    final g = ScriptedGateway()..state = const AuthWaitEmailAddress();
    await tester.pumpWidget(app(g));
    await tester.pump();
    expect(find.text('Your email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ann@example.com');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(g.calls, ['email:ann@example.com']);

    g.go(
      const AuthWaitEmailCode(emailPattern: 'a***@example.com', codeLength: 6),
    );
    await tester.pump();
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('a***@example.com'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(g.calls.last, 'emailCode:123456');

    await tester.tap(find.text('Change number'));
    await tester.pump();
    expect(g.calls.last, 'logout');
  });

  testWidgets('a login step the app cannot do says so and offers another '
      'number', (tester) async {
    final g = ScriptedGateway()..state = const AuthUnsupported();
    await tester.pumpWidget(app(g));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('official Telegram app'), findsOneWidget);
    await tester.tap(find.text('Change number'));
    await tester.pump();
    expect(g.calls.last, 'logout');
  });

  testWidgets('the code screen can go back to change the number', (
    tester,
  ) async {
    final g = ScriptedGateway()
      ..state = const AuthWaitCode(
        phoneNumber: '+1',
        codeLength: 5,
        viaSms: true,
      );
    await tester.pumpWidget(app(g));
    await tester.pump();
    await tester.tap(find.text('Change number'));
    await tester.pump();
    expect(g.calls.last, 'logout');
    g.go(const AuthWaitPhoneNumber());
    await tester.pump();
    expect(find.text('Log in to Telegram'), findsOneWidget);
  });

  testWidgets('QR login shows the link as a code and can go back to phone', (
    tester,
  ) async {
    final g = ScriptedGateway();
    await tester.pumpWidget(app(g));
    await tester.pump();
    await tester.tap(find.text('Log in with QR code instead'));
    await tester.pump();
    expect(g.calls, ['qr']);

    g.go(const AuthWaitOtherDeviceConfirmation('tg://login?token=abc'));
    await tester.pump();
    expect(find.text('Log in with QR code'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == 'QrImageView'),
      findsOneWidget,
    );

    await tester.tap(find.text('Use a phone number instead'));
    await tester.pump();
    expect(g.calls.last, 'logout');
  });

  testWidgets('a failed QR request is shown inline', (tester) async {
    final g = ScriptedGateway()
      ..nextError = const TelegramException(400, 'API_ID_INVALID');
    await tester.pumpWidget(app(g));
    await tester.pump();
    await tester.tap(find.text('Log in with QR code instead'));
    await tester.pump();
    expect(find.textContaining('api_id/api_hash'), findsOneWidget);
  });

  testWidgets('registration asks for a first name', (tester) async {
    final g = ScriptedGateway()..state = const AuthWaitRegistration();
    await tester.pumpWidget(app(g));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Ann');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(g.calls, ['register:Ann']);
  });
}
