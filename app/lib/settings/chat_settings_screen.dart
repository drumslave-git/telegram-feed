import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';

import '../feeds/text_scale.dart';
import 'settings_tiles.dart';

/// How posts look: the text size of posts and the theme, the official app's Chat Settings.
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chat settings')),
    body: ListView(
      children: [
        const SettingsHeader('Text size in posts'),
        StreamBuilder<String?>(
          stream: db.watchSetting(SettingKeys.postTextScale),
          builder: (context, snap) {
            final factor = PostTextScale.parse(snap.data);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: factor,
                          min: PostTextScale.min,
                          max: PostTextScale.max,
                          // 5 % steps: the slider lands on round numbers.
                          divisions:
                              ((PostTextScale.max - PostTextScale.min) / 0.05)
                                  .round(),
                          label: '${(factor * 100).round()} %',
                          onChanged: (v) => db.setSetting(
                            SettingKeys.postTextScale,
                            v.toStringAsFixed(2),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${(factor * 100).round()} %',
                          textAlign: TextAlign.end,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(factor)),
                    child: Text(
                      'A post is drawn at this size.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const Divider(),
        const SettingsHeader('Theme'),
        StreamBuilder<String?>(
          stream: db.watchSetting(SettingKeys.themeMode),
          builder: (context, snap) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'system',
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: 'light',
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: 'dark',
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {snap.data ?? 'system'},
              onSelectionChanged: (s) =>
                  db.setSetting(SettingKeys.themeMode, s.first),
            ),
          ),
        ),
        const SettingsFooter(
          'System follows the dark theme switch of the phone.',
        ),
      ],
    ),
  );
}
