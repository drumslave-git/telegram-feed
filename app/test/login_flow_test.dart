import 'dart:async';

import 'package:fake_telegram/fake_telegram.dart'
    show fakeCountries, fakePhoneInfo;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/auth/login_screens.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_feed/widgets/error_state.dart';
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
  Future<List<Country>> countries({String language = 'en'}) async =>
      fakeCountries(language: language);
  @override
  Future<PhoneInfo> phoneInfo(String digits) async => fakePhoneInfo(digits);
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
  Future<List<StorageSlice>> storageByKind() async => const [];
  @override
  Future<StorageStats> clearCache({Set<StorageKind>? kinds}) => storageStats();
  @override
  Future<void> setCacheLimits({
    required int keepSeconds,
    required int maxBytes,
  }) async {}
}

Widget app(TelegramGateway g) => MaterialApp(
  home: AuthGate(
    gateway: g,
    child: const Scaffold(body: Text('HOME')),
  ),
);

void main() {
  Finder field(String label) => find.widgetWithText(TextField, label);
  String textOf(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;

  testWidgets('phone → code → password → home', (tester) async {
    final g = ScriptedGateway();
    await tester.pumpWidget(app(g));
    await tester.pump();
    expect(find.text('Log in to Telegram'), findsOneWidget);

    // A whole number typed with its plus is taken apart: the code to its field, the
    // rest written as the country writes it, the country named.
    await tester.enterText(field('Phone number'), '+15551234567');
    await tester.pump();
    await tester.pump();
    expect(textOf(tester, 'Code'), '1');
    expect(textOf(tester, 'Phone number'), '555 123 4567');
    expect(find.textContaining('United States'), findsOneWidget);

    // The official app's question, before any code is sent.
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(g.calls, isEmpty);
    expect(find.text('Is this the correct number?'), findsOneWidget);
    expect(find.text('+1 555 123 4567'), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(g.calls, ['phone:+15551234567']);

    g.go(
      const AuthWaitCode(
        phoneNumber: '+15551234567',
        codeLength: 5,
        viaSms: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Enter the code'), findsOneWidget);
    // One box per digit, and no button: the code goes when the last one is typed.
    expect(find.text('Continue'), findsNothing);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.pump();
    expect(g.calls.last, 'phone:+15551234567');
    await tester.enterText(find.byType(TextField), '12345');
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

  testWidgets('"Edit" goes back to the number and sends nothing', (
    tester,
  ) async {
    final g = ScriptedGateway();
    await tester.pumpWidget(app(g));
    await tester.pump();
    await tester.enterText(field('Phone number'), '5551234567');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(g.calls, isEmpty);
    expect(textOf(tester, 'Phone number'), '555 123 4567');
  });

  testWidgets('the country sets the code, the code finds the country, and the '
      'number is written as the country writes it', (tester) async {
    final g = ScriptedGateway();
    await tester.pumpWidget(app(g));
    await tester.pump();
    await tester.pump();
    // The phone's own country to begin with.
    expect(textOf(tester, 'Code'), '1');
    expect(find.textContaining('United States'), findsOneWidget);

    // Picked from the list, which a search narrows by name or by code.
    await tester.tap(find.textContaining('United States'));
    await tester.pumpAndSettle();
    expect(find.text('+380'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ukr');
    await tester.pump();
    expect(find.text('Poland'), findsNothing);
    await tester.enterText(find.byType(TextField), '+48');
    await tester.pump();
    expect(find.text('Poland'), findsOneWidget);
    expect(find.text('Ukraine'), findsNothing);
    await tester.enterText(find.byType(TextField), 'atlantis');
    await tester.pump();
    expect(find.text('No country found'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ukr');
    await tester.pump();
    await tester.tap(find.text('Ukraine'));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'Code'), '380');
    expect(find.textContaining('Ukraine'), findsOneWidget);
    // The hint shows how a number is written there.
    expect(
      tester.widget<TextField>(field('Phone number')).decoration!.hintText,
      '00 000 0000',
    );
    await tester.enterText(field('Phone number'), '671234567');
    await tester.pump();
    expect(textOf(tester, 'Phone number'), '67 123 4567');

    // The code typed by hand finds its country; one that is nobody's says so.
    await tester.enterText(field('Code'), '44');
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('United Kingdom'), findsOneWidget);
    expect(textOf(tester, 'Phone number'), '6712 34567');
    await tester.enterText(field('Code'), '999');
    await tester.pump();
    await tester.pump();
    expect(find.text('Invalid country code'), findsOneWidget);
    await tester.enterText(field('Code'), '');
    await tester.pump();
    expect(find.text('Choose a country'), findsOneWidget);

    // Without a code nothing is sent.
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(g.calls, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a number typed into the code field goes where it belongs', (
    tester,
  ) async {
    final g = ScriptedGateway();
    await tester.pumpWidget(app(g));
    await tester.pump();
    await tester.pump();
    await tester.enterText(field('Code'), '380671234567');
    await tester.pump();
    await tester.pump();
    expect(textOf(tester, 'Code'), '380');
    expect(textOf(tester, 'Phone number'), '67 123 4567');
  });

  test('digits are written into the pattern Telegram gives', () {
    expect(formatPhoneDigits('671234567', '-- --- ----'), '67 123 4567');
    // What is typed so far, with nothing after its last digit.
    expect(formatPhoneDigits('671', '67 1-- ----'), '67 1');
    expect(formatPhoneDigits('', '-- --- ----'), '');
    // More digits than the pattern expects follow at the end.
    expect(formatPhoneDigits('67123456789', '-- --- ----'), '67 123 456789');
    expect(formatPhoneDigits('123', ''), '123');
  });

  testWidgets('a flood wait says how long', (tester) async {
    final g = ScriptedGateway()
      ..nextError = const TelegramException(
        429,
        'Too Many Requests: retry after 187',
      );
    await tester.pumpWidget(app(g));
    await tester.pump();
    await tester.enterText(field('Phone number'), '5551234567');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(
      find.text('Too many attempts. Try again in 4 minutes.'),
      findsOneWidget,
    );

    String line(String message, [String language = 'en']) => telegramErrorLine(
      TelegramException(420, message),
      what: 'x',
      l10n: lookupAppLocalizations(Locale(language)),
    );
    expect(
      line('FLOOD_WAIT_30'),
      'Too many attempts. Try again in 30 seconds.',
    );
    expect(line('FLOOD_WAIT_1'), 'Too many attempts. Try again in 1 second.');
    expect(line('FLOOD_WAIT_60'), 'Too many attempts. Try again in 1 minute.');
    expect(line('FLOOD_WAIT_7201'), 'Too many attempts. Try again in 3 hours.');
    expect(
      line('FLOOD_WAIT_22', 'uk'),
      'Забагато спроб, спробуйте через 22 секунди.',
    );
    expect(
      line('FLOOD_WAIT_300', 'uk'),
      'Забагато спроб, спробуйте через 5 хвилин.',
    );
    // No time given: the old sentence.
    expect(line('Too Many Requests'), contains('rate-limiting'));
  });

  testWidgets('the code can be asked for again when the countdown is over', (
    tester,
  ) async {
    final g = ScriptedGateway();
    var now = DateTime(2026, 10, 4, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: CodeScreen(
          gateway: g,
          phoneNumber: '+1',
          codeLength: 5,
          resendAfter: 75,
          now: () => now,
        ),
      ),
    );
    await tester.pump();
    Finder resend(String label) => find.widgetWithText(OutlinedButton, label);
    expect(resend('Resend code in 1:15'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(resend('Resend code in 1:15')).onPressed,
      isNull,
    );

    now = now.add(const Duration(seconds: 16));
    await tester.pump(const Duration(seconds: 1));
    expect(resend('Resend code in 0:59'), findsOneWidget);

    now = now.add(const Duration(seconds: 59));
    await tester.pump(const Duration(seconds: 1));
    expect(resend('Resend code'), findsOneWidget);
    await tester.tap(resend('Resend code'));
    await tester.pump();
    expect(g.calls, ['resend']);
    expect(find.text('A new code is on its way.'), findsOneWidget);
  });

  testWidgets('with no other way to send the code there is no resend, and a '
      'code of unknown length has a field and a button', (tester) async {
    final g = ScriptedGateway()
      ..state = const AuthWaitCode(
        phoneNumber: '+1',
        codeLength: 0,
        viaSms: true,
        canResend: false,
      );
    await tester.pumpWidget(app(g));
    await tester.pump();
    expect(find.textContaining('Resend code'), findsNothing);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(g.calls, isEmpty);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(g.calls, ['code:123456']);
  });

  testWidgets('a wrong code is said inline and the boxes are empty for the '
      'next try', (tester) async {
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
    await tester.pump();
    await tester.pump();
    expect(g.calls, ['code:00000']);
    expect(find.text('Wrong code.'), findsOneWidget);
    final box = tester.widget<TextField>(find.byType(TextField));
    expect(box.enabled, isTrue);
    expect(box.controller!.text, isEmpty);
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
