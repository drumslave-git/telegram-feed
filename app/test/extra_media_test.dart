import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/extra_media.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  Future<void> pump(WidgetTester tester, Media media, {String text = ''}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PostCard(
                item: TimelineItem(
                  Post(
                    chatId: -1,
                    messageId: 2,
                    date: 300,
                    text: text,
                    media: media,
                  ),
                ),
                channelTitle: 'One',
                gateway: TimelineGateway({}),
              ),
            ),
          ),
        ),
      );

  testWidgets('a venue is a map with its name and address under it', (
    tester,
  ) async {
    await pump(
      tester,
      const LocationMedia(
        latitude: 54.32,
        longitude: 10.13,
        title: 'The Quay',
        address: 'Harbour Road 1',
      ),
    );
    await tester.pump();
    expect(find.byType(LocationView), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
    expect(find.text('The Quay'), findsOneWidget);
    expect(find.text('Harbour Road 1'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Venue, opens in a map')),
      findsOneWidget,
    );
  });

  testWidgets('a bare location is the map alone', (tester) async {
    await pump(tester, const LocationMedia(latitude: 54.32, longitude: 10.13));
    await tester.pump();
    expect(find.byIcon(Icons.location_on), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Location, opens in a map')),
      findsOneWidget,
    );
  });

  testWidgets('a contact shows the name and the number', (tester) async {
    await pump(
      tester,
      const ContactMedia(name: 'Mara Lind', phone: '+1 555 010 0142'),
    );
    expect(find.byType(ContactView), findsOneWidget);
    expect(find.text('Mara Lind'), findsOneWidget);
    expect(find.text('+1 555 010 0142'), findsOneWidget);
  });

  testWidgets('a game shows its title and what it says about itself', (
    tester,
  ) async {
    await pump(
      tester,
      const GameMedia(
        title: 'Tide Runner',
        description: 'Run before the water.',
      ),
      text: 'Beat my score',
    );
    expect(find.text('Game'), findsOneWidget);
    expect(find.text('Tide Runner'), findsOneWidget);
    expect(find.text('Run before the water.'), findsOneWidget);
    expect(find.text('Beat my score'), findsOneWidget);
  });

  testWidgets('a checklist shows its tasks, which are done, and how many', (
    tester,
  ) async {
    await pump(
      tester,
      const ChecklistMedia(
        title: 'Before the ferry',
        tasks: [
          ChecklistTask(text: 'Tickets', done: true),
          ChecklistTask(text: 'Coffee'),
          ChecklistTask(text: 'Feed the cat', done: true),
        ],
      ),
    );
    expect(find.text('Before the ferry'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.text('2 of 3 completed'), findsOneWidget);
  });

  test('such posts are named by what they are in lists and notifications', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    String label(Media m) => l10n.mediaPreview(m);
    expect(label(const LocationMedia(latitude: 1, longitude: 2)), 'Location');
    expect(
      label(const LocationMedia(latitude: 1, longitude: 2, title: 'The Quay')),
      'The Quay',
    );
    expect(label(const ContactMedia(name: 'Mara', phone: '1')), 'Mara');
    expect(label(const GameMedia(title: '')), 'Game');
    expect(
      label(const ChecklistMedia(title: 'Before the ferry')),
      'Before the ferry',
    );
    expect(label(const ChecklistMedia(title: '')), 'Checklist');
  });
}
