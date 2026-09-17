import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/main.dart';

void main() {
  testWidgets('scaffold renders', (tester) async {
    await tester.pumpWidget(const TelegramFeedApp());
    expect(find.textContaining('telegram-feed'), findsOneWidget);
  });
}
