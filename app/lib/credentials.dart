/// Telegram API credentials come from `--dart-define`; never committed (SPEC section 7).
library;

const int tgApiId = int.fromEnvironment('TG_API_ID');
const String tgApiHash = String.fromEnvironment('TG_API_HASH');
const bool tgTestDc = bool.fromEnvironment('TG_TEST_DC');

/// The fake build: the core talks to `FakeTelegram` instead of TDLib, so the app runs
/// without an account, a network or credentials (ARCHITECTURE section 11).
const bool tgFake = bool.fromEnvironment('TG_FAKE');
