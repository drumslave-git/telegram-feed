import 'dart:ui';

import 'package:core/core.dart'
    show MediaWords, SyncException, SyncProblem, mediaLabel;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:telegram_gateway/telegram_gateway.dart'
    show Media, ServiceKind, ServiceNote, UnsupportedMedia;

import 'app_localizations.dart';

export 'app_localizations.dart';

/// The interface languages, by the value the Language setting stores. A missing value
/// follows the phone.
abstract final class AppLanguage {
  static const system = 'system';
  static const english = 'en';
  static const ukrainian = 'uk';

  /// The languages the app has, in the order the Language screen lists them.
  static const all = [english, ukrainian];

  /// A language under its own name, the same in every interface language.
  static String nameOf(String code) => switch (code) {
    ukrainian => 'Українська',
    _ => 'English',
  };

  /// The locale a setting value asks for; null follows the phone.
  static Locale? localeOf(String? value) => switch (value) {
    english => const Locale('en'),
    ukrainian => const Locale('uk'),
    _ => null,
  };

  /// The language the phone's own list of languages leads to: the first one the app has,
  /// English when it has none of them. Flutter resolves the app's locale the same way.
  static Locale ofPhone([List<Locale>? preferred]) => basicLocaleListResolution(
    preferred ?? PlatformDispatcher.instance.locales,
    AppLocalizations.supportedLocales,
  );

  static final AppLocalizations englishStrings = lookupAppLocalizations(
    const Locale('en'),
  );

  /// The strings of a setting value, where no widget tree is at hand (the service's
  /// notifications).
  static AppLocalizations strings(String? value, [List<Locale>? preferred]) =>
      lookupAppLocalizations(localeOf(value) ?? ofPhone(preferred));

  /// The strings of a language when the app has it, such as the language a post is
  /// written in ('uk', or a tag like 'en-US'); null otherwise.
  static AppLocalizations? stringsOfLanguage(String? tag) {
    final code = tag?.split(RegExp('[-_]')).first.toLowerCase();
    final match = AppLocalizations.supportedLocales.where(
      (l) => l.languageCode == code,
    );
    return match.isEmpty ? null : lookupAppLocalizations(match.first);
  }
}

extension AppLocalizationsOf on BuildContext {
  /// The strings of the interface language. English where no app localizations are in
  /// scope: widget tests that build a bare `MaterialApp`.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLanguage.englishStrings;
}

extension MediaWordsOf on AppLocalizations {
  /// What the kinds of media are called, for `mediaLabel` and `postLabel`.
  MediaWords get mediaWords => MediaWords(
    photo: mediaPhoto,
    video: mediaVideo,
    gif: mediaGif,
    videoMessage: mediaVideoMessage,
    voiceMessage: mediaVoiceMessage,
    audio: mediaAudio,
    sticker: mediaSticker,
    stickerWithEmoji: mediaStickerWithEmoji,
    post: mediaPost,
    location: mediaLocation,
    venue: mediaVenue,
    contact: mediaContact,
    game: mediaGame,
    checklist: mediaChecklist,
  );

  /// One line for what a post without words carries, in a channel list or a reply quote:
  /// content the app does not show is named by its kind.
  String mediaPreview(Media? media, {String channel = ''}) => switch (media) {
    UnsupportedMedia(:final tdType) => unsupportedLabel(tdType),
    final ServiceNote note => serviceLabel(note, channel: channel),
    null => '',
    _ => mediaLabel(media, mediaWords),
  };

  /// The words of a service line, as the official app says them. [channel] is named where
  /// the line stands among other channels' posts ([amongOthers], a feed).
  String serviceLabel(
    ServiceNote note, {
    String channel = '',
    bool amongOthers = false,
  }) {
    // A pin names the channel itself, as the official app's line does.
    if (note.kind == ServiceKind.pinned) return servicePinned(channel);
    final words = switch (note.kind) {
      ServiceKind.pinned => '',
      ServiceKind.titleChanged => serviceTitleChanged(note.title),
      ServiceKind.photoChanged => servicePhotoChanged,
      ServiceKind.photoRemoved => servicePhotoRemoved,
      ServiceKind.channelCreated => serviceChannelCreated,
      ServiceKind.liveStarted => serviceLiveStarted,
      ServiceKind.liveEnded => serviceLiveEnded(
        formatLength(Duration(seconds: note.seconds)),
      ),
      ServiceKind.liveScheduled => serviceLiveScheduled(
        DateFormat.MMMd(localeName)
            .add_Hm()
            .format(DateTime.fromMillisecondsSinceEpoch(note.seconds * 1000)),
      ),
      ServiceKind.other => serviceOther,
    };
    return channel.isEmpty || !amongOthers
        ? words
        : serviceOfChannel(channel, words);
  }

  /// A length as a clock reads it: 4:05, 1:02:03.
  static String formatLength(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return d.inHours > 0 ? '${d.inHours}:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  /// What content the app does not show is called, by TDLib's type (`messagePoll`).
  String unsupportedLabel(String tdType) => switch (tdType) {
    'messagePoll' => mediaPoll,
    'messageLocation' => mediaLocation,
    'messageVenue' => mediaVenue,
    'messageContact' => mediaContact,
    'messageDice' => mediaDice,
    'messageGame' => mediaGame,
    'messageInvoice' => mediaInvoice,
    'messageGiveaway' => mediaGiveaway,
    'messageStory' => mediaStory,
    'messageLiveLocation' => mediaLocation,
    'messageStakeDice' => mediaDice,
    'messageGiveawayWinners' => mediaGiveaway,
    'messageChecklist' => mediaChecklist,
    'messagePaidMedia' => mediaPaidMedia,
    _ => mediaUnsupported,
  };
}

extension ProblemsOf on AppLocalizations {
  /// Why sync could not run. Sign-in and Drive failures come as they are.
  String sync(SyncException e) => switch (e.problem) {
    SyncProblem.newerVersion => problemSyncNewerVersion,
    SyncProblem.unreadable => problemSyncUnreadable(e.detail),
    SyncProblem.other => e.message,
  };
}
