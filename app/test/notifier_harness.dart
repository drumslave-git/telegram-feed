import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// One line of a shown notification's conversation.
typedef Line = ({String text, int at, String sender, String? picture});

/// A notification as it was handed to Android.
class Shown {
  Shown(Map<Object?, Object?> arguments)
    : id = arguments['id']! as int,
      title = arguments['title'] as String?,
      body = arguments['body'] as String?,
      payload = arguments['payload'] as String?,
      specifics = arguments['platformSpecifics']! as Map<Object?, Object?>;

  final int id;
  final String? title;
  final String? body;
  final String? payload;
  final Map<Object?, Object?> specifics;

  String get channel => specifics['channelId']! as String;
  String get icon => specifics['icon'] as String? ?? '';
  String? get avatar => specifics['largeIcon'] as String?;
  String? get rule => specifics['subText'] as String?;

  /// What stands beside the app's name in the header of the conversation.
  String? get header =>
      (specifics['styleInformation'] as Map?)?['conversationTitle'] as String?;
  int? get when => specifics['when'] as int?;
  int get importance => specifics['importance']! as int;

  /// Whether Android sounds and pops up for it though it is shown already.
  bool get alerts => specifics['onlyAlertOnce'] != true;

  /// The ids of its buttons, in order.
  List<String> get buttons => [
    for (final a in specifics['actions'] as List? ?? const [])
      (a as Map)['id']! as String,
  ];

  /// The conversation it lists, oldest first.
  List<Line> get lines => [
    for (final m
        in (specifics['styleInformation'] as Map?)?['messages'] as List? ??
            const [])
      (
        text: (m as Map)['text']! as String,
        at: m['timestamp']! as int,
        sender: (m['person'] as Map?)?['name'] as String? ?? '',
        picture: m['dataUri'] as String?,
      ),
  ];

  List<String> get texts => [for (final l in lines) l.text];

  /// The post a tap opens.
  PostRef get opens => PostRef.decode(payload)!;
}

/// Android's side of the notifications plugin: what was shown, what it still holds.
class FakeShade {
  static const _channel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  final shown = <Shown>[];
  final cancelled = <int>[];

  /// The ids Android reports as still showing.
  final live = <int>{};

  /// Whether Android grants access to the Do Not Disturb policy.
  bool policyAccess = false;

  void install() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'hasNotificationPolicyAccess':
              return policyAccess;
            case 'getActiveNotifications':
              return [
                for (final id in live) <dynamic, dynamic>{'id': id},
              ];
            case 'show':
              final s = Shown(call.arguments as Map);
              shown.add(s);
              live.add(s.id);
            case 'cancel':
              final id = (call.arguments as Map)['id'] as int;
              cancelled.add(id);
              live.remove(id);
          }
          return null;
        });
  }

  void remove() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  /// The reader swiped a channel's notification away, or tapped it.
  void swipe(int chatId, {int account = 0}) =>
      live.remove(NotificationPlan.idForChat(chatId, account));

  /// The newest notification of [chatId], in [account].
  Shown of(int chatId, {int account = 0}) => shown.lastWhere(
    (s) => s.id == NotificationPlan.idForChat(chatId, account),
  );
}

/// Keeps the notifications' lists in memory, as the file does across a restart.
class MemoryStore implements ListedStore {
  String? kept;

  @override
  Future<String?> read() async => kept;

  @override
  Future<void> write(String json) async => kept = json;
}

/// The line a match of [priority] adds to the notification of [chatId].
NotificationPlan planFor(
  int messageId, {
  int chatId = -1001,
  RulePriority priority = RulePriority.normal,
  String text = 'post',
  String title = 'News',
  String rule = 'r',
  int? date,
  Media? media,
  bool hidden = false,
  int account = 0,
  String accountName = '',
}) => NotificationPlan.forMatch(
  MatchEvent.of(
    Post(
      chatId: chatId,
      messageId: messageId,
      date: date ?? messageId,
      text: text,
      media: media,
    ),
    [MatchedRule(name: rule, priority: priority, readAloud: false)],
  ),
  channelTitle: title,
  hidden: hidden,
  account: account,
  accountName: accountName,
);
