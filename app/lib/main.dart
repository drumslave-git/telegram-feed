import 'package:flutter/material.dart';

void main() {
  runApp(const TelegramFeedApp());
}

class TelegramFeedApp extends StatelessWidget {
  const TelegramFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'telegram-feed',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const Scaffold(
        body: Center(child: Text('telegram-feed: phase 1 scaffold')),
      ),
    );
  }
}
