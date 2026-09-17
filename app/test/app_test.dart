import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/main.dart';

void main() {
  testWidgets('home renders while the core is connecting', (tester) async {
    await tester.pumpWidget(const TelegramFeedApp());
    expect(find.text('telegram-feed'), findsOneWidget);
  });
}
