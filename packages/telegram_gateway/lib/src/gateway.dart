import 'models.dart';

/// The only thing in the app that knows about Telegram. See ARCHITECTURE.md section 4.
abstract interface class TelegramGateway {
  /// Current state first (replayed to late subscribers), then every change.
  Stream<AuthState> get authState;
  Future<void> setPhoneNumber(String phone);
  Future<void> checkCode(String code);
  Future<void> checkPassword(String password);
  Future<void> registerUser({required String firstName, String lastName = ''});
  Future<void> requestQrCode();
  Future<void> logOut();

  /// Joined channels (supergroups with `is_channel`), newest chat first.
  Future<List<Channel>> myChannels();
  Stream<ChannelMembershipEvent> get membershipEvents;

  /// Posts older than [fromMessageId] (0 = newest), newest first. With [onlyLocal] TDLib answers
  /// from its database only and may return fewer posts than exist.
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  });
  Stream<PostEvent> get postEvents;
  Future<void> markViewed(int chatId, List<int> messageIds);

  /// Starts (or joins) a download and completes with the local path.
  Future<FileRef> download(FileRef ref, {int priority = 16});
  Stream<FileProgress> fileProgress(int fileId);

  Future<void> close();
}
