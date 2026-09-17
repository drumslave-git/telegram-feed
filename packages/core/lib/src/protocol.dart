/// Wire format between [CoreClient] and [CoreServer]. Plain maps of JSON-compatible values
/// plus `SendPort`s, so messages cross isolate groups (UI engine ↔ service engine).
///
/// client → server
///   {'type': 'hello', 'port': SendPort}                      subscribe; server replies 'welcome'
///   {'type': 'call', 'id': int, 'method': String, 'args': Map}
///   {'type': 'bye', 'port': SendPort}                        unsubscribe
/// server → client
///   {'type': 'welcome', 'auth': Map}                         current auth state
///   {'type': 'result', 'id': int, 'value': Object?}
///   {'type': 'error', 'id': int, 'code': int, 'message': String}
///   {'type': 'event', 'stream': 'auth'|'posts'|'membership'|'files', 'data': Map}
library;

/// Name under which the core registers its port with `IsolateNameServer`.
const corePortName = 'telegram_feed.core';

/// Named streams pushed to every subscribed client.
enum CoreStream { auth, posts, membership, files }
