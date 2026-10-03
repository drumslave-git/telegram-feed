import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('uk'),
  ];

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Value of a settings row whose feature is on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get commonOn;

  /// Value of a settings row whose feature is off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get commonOff;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// Tooltip of an overflow (three dots) menu button.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get commonMore;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @commonLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get commonLater;

  /// No description provided for @commonNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get commonNotNow;

  /// No description provided for @commonAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get commonAllow;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @commonReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get commonReset;

  /// No description provided for @commonSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get commonSelect;

  /// No description provided for @commonOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonSettings;

  /// No description provided for @commonRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get commonRules;

  /// No description provided for @commonComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get commonComments;

  /// No description provided for @commonCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get commonCopyLink;

  /// No description provided for @commonOpenInTelegram.
  ///
  /// In en, this message translates to:
  /// **'Open in Telegram'**
  String get commonOpenInTelegram;

  /// No description provided for @commonOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get commonOpenSettings;

  /// No description provided for @commonDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get commonDiscard;

  /// No description provided for @commonKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get commonKeepEditing;

  /// Menu action on a feed, folder or channel.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get commonMarkAsRead;

  /// No description provided for @mediaPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get mediaPhoto;

  /// No description provided for @mediaVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get mediaVideo;

  /// No description provided for @mediaGif.
  ///
  /// In en, this message translates to:
  /// **'GIF'**
  String get mediaGif;

  /// No description provided for @mediaVideoMessage.
  ///
  /// In en, this message translates to:
  /// **'Video message'**
  String get mediaVideoMessage;

  /// No description provided for @mediaVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get mediaVoiceMessage;

  /// No description provided for @mediaAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get mediaAudio;

  /// No description provided for @mediaSticker.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get mediaSticker;

  /// No description provided for @mediaFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get mediaFile;

  /// What a post without text or known media is called.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get mediaPost;

  /// No description provided for @tabMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get tabMedia;

  /// No description provided for @tabFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get tabFiles;

  /// No description provided for @tabLinks.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get tabLinks;

  /// No description provided for @tabMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get tabMusic;

  /// No description provided for @tabVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get tabVoice;

  /// A sticker named by the emoji it stands for.
  ///
  /// In en, this message translates to:
  /// **'{emoji} Sticker'**
  String mediaStickerWithEmoji(String emoji);

  /// Screen-reader label of hidden spoiler text in a post.
  ///
  /// In en, this message translates to:
  /// **'spoiler'**
  String get timelineSpoiler;

  /// No description provided for @timelineCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get timelineCodeCopied;

  /// No description provided for @linkOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Link'**
  String get linkOpenTitle;

  /// No description provided for @linkOpenQuestion.
  ///
  /// In en, this message translates to:
  /// **'Do you want to open {url}?'**
  String linkOpenQuestion(String url);

  /// No description provided for @phoneCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get phoneCall;

  /// No description provided for @phoneCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy number'**
  String get phoneCopy;

  /// No description provided for @phoneCopied.
  ///
  /// In en, this message translates to:
  /// **'Phone number copied'**
  String get phoneCopied;

  /// Button at the end of a monospace block in a post.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get timelineCopyCode;

  /// A voice message or music file in a post failed to play.
  ///
  /// In en, this message translates to:
  /// **'Cannot play: {error}'**
  String timelineCannotPlay(String error);

  /// No description provided for @timelinePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get timelinePlay;

  /// No description provided for @timelinePause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get timelinePause;

  /// Title of the bar that replaces the app bar while posts are selected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String timelineSelectedCount(int count);

  /// No description provided for @timelineCopyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get timelineCopyText;

  /// Forwards the selected posts to the account's Saved Messages chat.
  ///
  /// In en, this message translates to:
  /// **'Save to Saved Messages'**
  String get timelineSaveToSavedMessages;

  /// No description provided for @timelinePostsCopied.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} post copied} other{{count} posts copied}}'**
  String timelinePostsCopied(int count);

  /// No description provided for @timelinePostsSaved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} post saved to Saved Messages} other{{count} posts saved to Saved Messages}}'**
  String timelinePostsSaved(int count);

  /// No description provided for @timelineSavePostsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the posts.'**
  String get timelineSavePostsFailed;

  /// Title of the dialog that asks before a post of Saved Messages is deleted.
  ///
  /// In en, this message translates to:
  /// **'Delete post'**
  String get timelineDeletePostTitle;

  /// No description provided for @timelineDeletePostMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this post?'**
  String get timelineDeletePostMessage;

  /// Title of the dialog that asks before several posts of Saved Messages are deleted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Delete {count} post} other{Delete {count} posts}}'**
  String timelineDeletePostsTitle(int count);

  /// No description provided for @timelineDeletePostsMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete these posts?'**
  String get timelineDeletePostsMessage;

  /// No description provided for @timelineDeletePostsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the posts.'**
  String get timelineDeletePostsFailed;

  /// No description provided for @timelineJumpToDate.
  ///
  /// In en, this message translates to:
  /// **'Jump to date'**
  String get timelineJumpToDate;

  /// Under a channel's name. shown is count in short form, e.g. 1.2K.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{shown} subscribers}}'**
  String timelineSubscribers(int count, String shown);

  /// No description provided for @timelineEditFeed.
  ///
  /// In en, this message translates to:
  /// **'Edit feed'**
  String get timelineEditFeed;

  /// No description provided for @timelineJumpToDayFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not jump to that day.'**
  String get timelineJumpToDayFailed;

  /// The calendar jump found no post on or before the picked day, e.g. Today, September 12.
  ///
  /// In en, this message translates to:
  /// **'Nothing here from {day} or earlier.'**
  String timelineNothingFromDay(String day);

  /// No description provided for @timelineNoAppForPost.
  ///
  /// In en, this message translates to:
  /// **'No app can open this post.'**
  String get timelineNoAppForPost;

  /// No description provided for @timelineForwardHidden.
  ///
  /// In en, this message translates to:
  /// **'That post came from an account that hides itself.'**
  String get timelineForwardHidden;

  /// No description provided for @timelineForwardNotFollowed.
  ///
  /// In en, this message translates to:
  /// **'{title} is not a channel you follow.'**
  String timelineForwardNotFollowed(String title);

  /// No description provided for @timelineReplyNotFollowed.
  ///
  /// In en, this message translates to:
  /// **'That post is in a channel you do not follow.'**
  String get timelineReplyNotFollowed;

  /// No description provided for @timelineNoAppForLink.
  ///
  /// In en, this message translates to:
  /// **'No app can open {url}'**
  String timelineNoAppForLink(String url);

  /// No description provided for @timelineNoLinkToShare.
  ///
  /// In en, this message translates to:
  /// **'This post has no link to share.'**
  String get timelineNoLinkToShare;

  /// No description provided for @timelineTextCopied.
  ///
  /// In en, this message translates to:
  /// **'Text copied'**
  String get timelineTextCopied;

  /// No description provided for @timelineNoLinkToCopy.
  ///
  /// In en, this message translates to:
  /// **'This post has no link to copy.'**
  String get timelineNoLinkToCopy;

  /// No description provided for @timelineLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied: {link}'**
  String timelineLinkCopied(String link);

  /// No description provided for @timelineSavedToSavedMessages.
  ///
  /// In en, this message translates to:
  /// **'Saved to Saved Messages'**
  String get timelineSavedToSavedMessages;

  /// No description provided for @timelineSavePostFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the post.'**
  String get timelineSavePostFailed;

  /// No description provided for @timelineReactionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send the reaction.'**
  String get timelineReactionFailed;

  /// Tooltip of the button that goes down to the newest posts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} new post} other{{count} new posts}}'**
  String timelineNewPosts(int count);

  /// Tooltip of the button that goes down to the newest posts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} unread post} other{{count} unread posts}}'**
  String timelineUnreadPostsCount(int count);

  /// Tooltip of the button that goes down to the newest posts.
  ///
  /// In en, this message translates to:
  /// **'Newest posts'**
  String get timelineNewestPosts;

  /// No description provided for @timelineNoChannelsTitle.
  ///
  /// In en, this message translates to:
  /// **'This feed has no channels yet'**
  String get timelineNoChannelsTitle;

  /// No description provided for @timelineNoChannelsMessage.
  ///
  /// In en, this message translates to:
  /// **'Add the channels it should collect; their posts then read as one timeline, oldest first.'**
  String get timelineNoChannelsMessage;

  /// No description provided for @timelineAddChannels.
  ///
  /// In en, this message translates to:
  /// **'Add channels'**
  String get timelineAddChannels;

  /// No description provided for @timelineLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the posts.'**
  String get timelineLoadFailed;

  /// No description provided for @timelineNoPosts.
  ///
  /// In en, this message translates to:
  /// **'No posts.'**
  String get timelineNoPosts;

  /// No description provided for @timelineNoPostsPassFilter.
  ///
  /// In en, this message translates to:
  /// **'No posts pass this feed\'s filter ({filter}).'**
  String timelineNoPostsPassFilter(String filter);

  /// No description provided for @timelineBeginningOfFeed.
  ///
  /// In en, this message translates to:
  /// **'Beginning of the feed'**
  String get timelineBeginningOfFeed;

  /// No description provided for @timelineOlderFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load older posts.'**
  String get timelineOlderFailed;

  /// No description provided for @timelinePinnedPost.
  ///
  /// In en, this message translates to:
  /// **'Pinned post'**
  String get timelinePinnedPost;

  /// Tooltip of the cross that puts the pinned-post bar away.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get timelineHidePinned;

  /// Title of the pinned bar over the older of two pinned posts.
  ///
  /// In en, this message translates to:
  /// **'Previous post'**
  String get timelinePreviousPinned;

  /// Title of the pinned bar over an older pinned post; the posts are numbered from the oldest.
  ///
  /// In en, this message translates to:
  /// **'Pinned post #{number}'**
  String timelinePinnedPostNumber(int number);

  /// Tooltip of the button in the pinned bar that opens the list of pinned posts.
  ///
  /// In en, this message translates to:
  /// **'Pinned posts'**
  String get timelinePinnedList;

  /// Title of the screen that lists a channel's pinned posts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Pinned post} other{{count} pinned posts}}'**
  String pinnedPostsTitle(int count);

  /// What a tap on a post in the list of pinned posts does, for screen readers.
  ///
  /// In en, this message translates to:
  /// **'Go to the post'**
  String get pinnedPostsOpen;

  /// No description provided for @pinnedPostsHide.
  ///
  /// In en, this message translates to:
  /// **'Hide pinned posts'**
  String get pinnedPostsHide;

  /// Shown after the pinned bar was hidden, with an Undo action.
  ///
  /// In en, this message translates to:
  /// **'Pinned posts hidden. They will be shown again when a new post is pinned.'**
  String get pinnedPostsHidden;

  /// Divider above the first post that was unread when the timeline opened.
  ///
  /// In en, this message translates to:
  /// **'Unread posts'**
  String get timelineUnreadDivider;

  /// Search filter chip: posts of every kind.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get searchFilterEverything;

  /// No description provided for @searchRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get searchRecent;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not search.'**
  String get searchFailed;

  /// No description provided for @searchTypeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type to search the posts.'**
  String get searchTypeToSearch;

  /// No description provided for @searchNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found for \"{query}\".'**
  String searchNothingFound(String query);

  /// No description provided for @searchPostsFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} post found} other{{count} posts found}}'**
  String searchPostsFound(int count);

  /// No description provided for @searchMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load more results.'**
  String get searchMoreFailed;

  /// No description provided for @searchOlderMatch.
  ///
  /// In en, this message translates to:
  /// **'Older match'**
  String get searchOlderMatch;

  /// No description provided for @searchNewerMatch.
  ///
  /// In en, this message translates to:
  /// **'Newer match'**
  String get searchNewerMatch;

  /// No description provided for @searchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get searchNoMatches;

  /// Which search result the timeline stands on, e.g. 3 of 17.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String searchMatchOf(int current, int total);

  /// No description provided for @searchPostsHint.
  ///
  /// In en, this message translates to:
  /// **'Search posts'**
  String get searchPostsHint;

  /// No description provided for @threadSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not search the comments.'**
  String get threadSearchFailed;

  /// No description provided for @threadPostFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not post the comment.'**
  String get threadPostFailed;

  /// No description provided for @threadSearchComments.
  ///
  /// In en, this message translates to:
  /// **'Search comments'**
  String get threadSearchComments;

  /// No description provided for @threadTitleWithChannel.
  ///
  /// In en, this message translates to:
  /// **'Comments · {channel}'**
  String threadTitleWithChannel(String channel);

  /// No description provided for @threadNoDiscussion.
  ///
  /// In en, this message translates to:
  /// **'This channel has no discussion group, so posts cannot be commented on.'**
  String get threadNoDiscussion;

  /// No description provided for @threadLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the comments.'**
  String get threadLoadFailed;

  /// No description provided for @threadSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get threadSearching;

  /// No description provided for @threadNoComments.
  ///
  /// In en, this message translates to:
  /// **'No comments yet.'**
  String get threadNoComments;

  /// Hint of the comment composer.
  ///
  /// In en, this message translates to:
  /// **'Write a comment'**
  String get threadWriteComment;

  /// No description provided for @threadSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get threadSend;

  /// No description provided for @threadLoadOlder.
  ///
  /// In en, this message translates to:
  /// **'Load older comments'**
  String get threadLoadOlder;

  /// Pill above the first comment of a thread.
  ///
  /// In en, this message translates to:
  /// **'Discussion started'**
  String get threadDiscussionStarted;

  /// Label between two days of a chat.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get postDayToday;

  /// Label between two days of a chat.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get postDayYesterday;

  /// intl DateFormat pattern of a day of this year between two days of a chat, e.g. September 17. Not a sentence: only the order of the fields changes.
  ///
  /// In en, this message translates to:
  /// **'MMMM d'**
  String get postDayPattern;

  /// intl DateFormat pattern of a day of another year between two days of a chat, e.g. March 3, 2025. Not a sentence: only the order of the fields changes.
  ///
  /// In en, this message translates to:
  /// **'MMMM d, y'**
  String get postDayYearPattern;

  /// Screen reader label of the day pill, which opens the calendar.
  ///
  /// In en, this message translates to:
  /// **'{day}. Jump to a date'**
  String postDayJumpToDate(String day);

  /// No description provided for @postCopyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get postCopyText;

  /// No description provided for @postProtected.
  ///
  /// In en, this message translates to:
  /// **'Copying and forwarding is not allowed in this channel.'**
  String get postProtected;

  /// Post menu: forwards the post into the account's Saved Messages.
  ///
  /// In en, this message translates to:
  /// **'Save to Saved Messages'**
  String get postSaveToSavedMessages;

  /// Post menu: folds a post the feed's filter leaves out back into one line.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get postMinimize;

  /// No description provided for @postAutoplaySettings.
  ///
  /// In en, this message translates to:
  /// **'Autoplay and download settings'**
  String get postAutoplaySettings;

  /// Screen reader label of a post shown as one line.
  ///
  /// In en, this message translates to:
  /// **'Minimized post of {channel}: {words}, {time}'**
  String postMinimizedSemantics(String channel, String words, String time);

  /// Screen reader label of the channel name on a post, which opens the channel's info.
  ///
  /// In en, this message translates to:
  /// **'Channel info of {name}'**
  String postChannelInfoOf(String name);

  /// Stands for the name in postForwardedFrom when the original author hides their account.
  ///
  /// In en, this message translates to:
  /// **'a hidden account'**
  String get postHiddenAccount;

  /// Line above a forwarded post; the name is drawn bold.
  ///
  /// In en, this message translates to:
  /// **'Forwarded from {name}'**
  String postForwardedFrom(String name);

  /// Screen reader label of the forwarded-from line when it opens the original post.
  ///
  /// In en, this message translates to:
  /// **'Forwarded from {name}. Open the original'**
  String postForwardedFromOpen(String name);

  /// Screen reader label of the quote block of the post this one answers.
  ///
  /// In en, this message translates to:
  /// **'In reply to {name}'**
  String postInReplyTo(String name);

  /// Screen reader label of the quote block when a tap jumps to the answered post.
  ///
  /// In en, this message translates to:
  /// **'In reply to {name}. Go to that post'**
  String postInReplyToOpen(String name);

  /// In a post's footer, before the time.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get postEdited;

  /// Comments bar under a post. shown is count in short form, e.g. 1.2K.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{shown} comment} other{{shown} comments}}'**
  String postCommentCount(int count, String shown);

  /// Comments bar under a post without comments.
  ///
  /// In en, this message translates to:
  /// **'Leave a comment'**
  String get postLeaveComment;

  /// No description provided for @postReactionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Reactions could not be loaded.'**
  String get postReactionsLoadFailed;

  /// No description provided for @postReactionsNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This channel does not allow reactions.'**
  String get postReactionsNotAllowed;

  /// No description provided for @postDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed. Tap to retry.'**
  String get postDownloadFailed;

  /// No description provided for @postDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get postDownloading;

  /// No description provided for @postTapToDownload.
  ///
  /// In en, this message translates to:
  /// **'Tap to download'**
  String get postTapToDownload;

  /// Under a file's name before it is downloaded; size is e.g. 3.4 MB.
  ///
  /// In en, this message translates to:
  /// **'{size} · tap to download'**
  String postFileTapToDownload(String size);

  /// Under a downloaded file whose size is unknown.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get postOnThisDevice;

  /// Tooltip: hands a downloaded file to another app.
  ///
  /// In en, this message translates to:
  /// **'Open with…'**
  String get postOpenWith;

  /// Screen reader label of a photo that opens the viewer.
  ///
  /// In en, this message translates to:
  /// **'Photo, opens full screen'**
  String get postPhotoOpensFullScreen;

  /// No description provided for @postPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get postPlay;

  /// No description provided for @sharedMediaNoChannels.
  ///
  /// In en, this message translates to:
  /// **'No channels yet.'**
  String get sharedMediaNoChannels;

  /// No description provided for @sharedMediaLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load this media.'**
  String get sharedMediaLoadFailed;

  /// No description provided for @sharedMediaEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get sharedMediaEmpty;

  /// Screen reader label of a GIF in the media grid; day is e.g. Today or March 3.
  ///
  /// In en, this message translates to:
  /// **'GIF, {day}'**
  String sharedMediaGifTile(String day);

  /// Screen reader label of a video in the media grid; duration is e.g. 1:05.
  ///
  /// In en, this message translates to:
  /// **'Video {duration}, {day}'**
  String sharedMediaVideoTile(String duration, String day);

  /// Screen reader label of a photo in the media grid.
  ///
  /// In en, this message translates to:
  /// **'Photo, {day}'**
  String sharedMediaPhotoTile(String day);

  /// Screen reader label of a cell of the media grid that is neither photo nor video.
  ///
  /// In en, this message translates to:
  /// **'Post of {day}'**
  String sharedMediaPostTile(String day);

  /// No description provided for @sharedMediaNoAppCanOpen.
  ///
  /// In en, this message translates to:
  /// **'No app can open {link}'**
  String sharedMediaNoAppCanOpen(String link);

  /// No description provided for @channelInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Channel info'**
  String get channelInfoTitle;

  /// No description provided for @channelInfoQrCode.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get channelInfoQrCode;

  /// No description provided for @channelInfoLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get channelInfoLinkCopied;

  /// Under the channel's name. shown is count in short form, e.g. 1.2K.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{shown} subscriber} other{{shown} subscribers}}'**
  String channelInfoSubscribers(int count, String shown);

  /// Under the channel's name when the number of subscribers is unknown.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get channelInfoChannel;

  /// No description provided for @channelInfoLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the channel details.'**
  String get channelInfoLoadFailed;

  /// No description provided for @channelInfoSimilarChannels.
  ///
  /// In en, this message translates to:
  /// **'Similar channels'**
  String get channelInfoSimilarChannels;

  /// Home screen tab that lists the feeds.
  ///
  /// In en, this message translates to:
  /// **'Feeds'**
  String get homeTabFeeds;

  /// Home screen tab that lists every channel.
  ///
  /// In en, this message translates to:
  /// **'All channels'**
  String get homeTabAllChannels;

  /// Tooltip of the home screen's search button.
  ///
  /// In en, this message translates to:
  /// **'Search posts'**
  String get homeSearchPosts;

  /// Hint of the search field that searches posts of every channel.
  ///
  /// In en, this message translates to:
  /// **'Search all channels'**
  String get homeSearchHint;

  /// No description provided for @homeSearchChannelNotInList.
  ///
  /// In en, this message translates to:
  /// **'That channel is not in your list.'**
  String get homeSearchChannelNotInList;

  /// Menu action on a folder tab or a feed.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get homeMarkAllAsRead;

  /// No description provided for @homeNothingToMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Nothing to mark read.'**
  String get homeNothingToMarkRead;

  /// No description provided for @homeChannelsMarkedRead.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} channel marked read.} other{{count} channels marked read.}}'**
  String homeChannelsMarkedRead(int count);

  /// Long-press menu of a folder tab.
  ///
  /// In en, this message translates to:
  /// **'Create feed from folder'**
  String get homeFolderCreateFeed;

  /// Title of the card on the Feeds tab shown until the reader has rules.
  ///
  /// In en, this message translates to:
  /// **'Nothing notifies you yet'**
  String get homeRulesHintTitle;

  /// Tooltip of the close button of a hint card.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get homeRulesHintDismiss;

  /// No description provided for @homeRulesHintBody.
  ///
  /// In en, this message translates to:
  /// **'This app never repeats Telegram\'s own notifications. A rule of a feed watches its channels for the words you pick and notifies you, and can read the post aloud.'**
  String get homeRulesHintBody;

  /// No description provided for @homeRulesHintAction.
  ///
  /// In en, this message translates to:
  /// **'Set up rules'**
  String get homeRulesHintAction;

  /// Screen-reader label of an unread counter (posts or channels).
  ///
  /// In en, this message translates to:
  /// **'{count} unread'**
  String homeUnreadBadge(int count);

  /// App bar subtitle while there is no network.
  ///
  /// In en, this message translates to:
  /// **'Waiting for network…'**
  String get homeWaitingForNetwork;

  /// App bar subtitle while connecting to Telegram.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get homeConnecting;

  /// App bar subtitle while connecting to a proxy.
  ///
  /// In en, this message translates to:
  /// **'Connecting to proxy…'**
  String get homeConnectingToProxy;

  /// App bar subtitle while Telegram catches up on missed updates.
  ///
  /// In en, this message translates to:
  /// **'Updating…'**
  String get homeUpdating;

  /// No description provided for @feedsNewFeed.
  ///
  /// In en, this message translates to:
  /// **'New feed'**
  String get feedsNewFeed;

  /// No description provided for @feedsRenameFeed.
  ///
  /// In en, this message translates to:
  /// **'Rename feed'**
  String get feedsRenameFeed;

  /// Label of a feed's name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get feedsNameLabel;

  /// No description provided for @feedsCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get feedsCreate;

  /// Choice in the New feed sheet: a feed without channels.
  ///
  /// In en, this message translates to:
  /// **'Empty feed'**
  String get feedsEmptyFeed;

  /// No description provided for @feedsEmptyFeedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name it, then pick its channels'**
  String get feedsEmptyFeedSubtitle;

  /// Header in the New feed sheet above the Telegram folders.
  ///
  /// In en, this message translates to:
  /// **'From a folder'**
  String get feedsFromFolder;

  /// No description provided for @feedsChannelCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} channel} other{{count} channels}}'**
  String feedsChannelCount(int count);

  /// Line under a feed's name: how many of its channels have unread posts.
  ///
  /// In en, this message translates to:
  /// **'{fresh} of {count, plural, =1{{count} channel} other{{count} channels}} with news'**
  String feedsChannelsWithNews(int fresh, int count);

  /// No description provided for @feedsCreatedFromFolder.
  ///
  /// In en, this message translates to:
  /// **'Feed \"{name}\" created with {count, plural, =1{{count} channel} other{{count} channels}}.'**
  String feedsCreatedFromFolder(String name, int count);

  /// No description provided for @feedsNothingToMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Nothing to mark read in \"{name}\".'**
  String feedsNothingToMarkRead(String name);

  /// No description provided for @feedsMarkedRead.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" marked read.'**
  String feedsMarkedRead(String name);

  /// No description provided for @feedsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String feedsDeleteTitle(String name);

  /// Body of the Delete feed dialog; count is the number of the feed's rules.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{The feed and its kept positions are removed.} =1{The feed, its rule and its kept positions are removed.} other{The feed, its {count} rules and its kept positions are removed.}} Channels stay joined in Telegram.'**
  String feedsDeleteMessage(int count);

  /// No description provided for @feedsCountersRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh the counters.'**
  String get feedsCountersRefreshFailed;

  /// No description provided for @feedsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No feeds yet'**
  String get feedsEmptyTitle;

  /// No description provided for @feedsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'A feed is a set of channels read as one timeline. Rules of the feed then notify you about the posts you care about; without them this app stays quiet.'**
  String get feedsEmptyMessage;

  /// No description provided for @feedsEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Create a feed'**
  String get feedsEmptyAction;

  /// No description provided for @feedsEmptySecondary.
  ///
  /// In en, this message translates to:
  /// **'A feed can also start from one of your Telegram folders, or from the \"Add to a feed\" menu of any channel.'**
  String get feedsEmptySecondary;

  /// Feed row menu: opens the feed's channel list.
  ///
  /// In en, this message translates to:
  /// **'Edit channels'**
  String get feedsEditChannels;

  /// Long-press menu of a channel row.
  ///
  /// In en, this message translates to:
  /// **'Channel info'**
  String get channelsInfo;

  /// Long-press menu of a channel row.
  ///
  /// In en, this message translates to:
  /// **'Add to a feed'**
  String get channelsAddToFeed;

  /// No description provided for @channelsAlreadyInFeed.
  ///
  /// In en, this message translates to:
  /// **'Already in this feed'**
  String get channelsAlreadyInFeed;

  /// No description provided for @channelsAddedToFeed.
  ///
  /// In en, this message translates to:
  /// **'{channel} added to \"{feed}\".'**
  String channelsAddedToFeed(String channel, String feed);

  /// The channels archived in Telegram (a row and a screen title).
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get channelsArchive;

  /// No description provided for @channelsArchiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Channels you archived in Telegram'**
  String get channelsArchiveSubtitle;

  /// No description provided for @channelsArchiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'No archived channels.'**
  String get channelsArchiveEmpty;

  /// No description provided for @channelsArchiveOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the archive.'**
  String get channelsArchiveOpenFailed;

  /// No description provided for @channelsEmptyAll.
  ///
  /// In en, this message translates to:
  /// **'No channels yet. Join channels in Telegram and they show up here.'**
  String get channelsEmptyAll;

  /// No description provided for @channelsEmptyFolder.
  ///
  /// In en, this message translates to:
  /// **'No channels in this folder.'**
  String get channelsEmptyFolder;

  /// No description provided for @channelsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No channels here.'**
  String get channelsEmpty;

  /// No description provided for @channelsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the channels.'**
  String get channelsLoadFailed;

  /// No description provided for @channelsRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh the channels.'**
  String get channelsRefreshFailed;

  /// No description provided for @channelsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No channel matches \"{query}\".'**
  String channelsNoMatch(String query);

  /// No description provided for @channelsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search channels'**
  String get channelsSearchHint;

  /// No description provided for @logOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logOutTitle;

  /// No description provided for @logOutMessage.
  ///
  /// In en, this message translates to:
  /// **'Your feeds, rules, settings and the AI key on this device are deleted, and Google Drive sync is turned off. A copy stays in your Drive if sync was on.'**
  String get logOutMessage;

  /// No description provided for @logOutAction.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOutAction;

  /// Banner button: stops reading the current post aloud.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get bannerStop;

  /// No description provided for @bannerStopAndClearQueue.
  ///
  /// In en, this message translates to:
  /// **'Stop and clear queue'**
  String get bannerStopAndClearQueue;

  /// No description provided for @bannerPaused.
  ///
  /// In en, this message translates to:
  /// **'Notifications are paused. Rules notify about nothing and read nothing aloud.'**
  String get bannerPaused;

  /// Banner button: ends the pause of notifications.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get bannerResume;

  /// No description provided for @bannerReadingAloud.
  ///
  /// In en, this message translates to:
  /// **'Reading aloud'**
  String get bannerReadingAloud;

  /// No description provided for @bannerReadingAloudChannel.
  ///
  /// In en, this message translates to:
  /// **'Reading aloud: {channel}'**
  String bannerReadingAloudChannel(String channel);

  /// The reading-aloud banner with the number of posts queued after the current one; line is the banner's first part.
  ///
  /// In en, this message translates to:
  /// **'{line}. {count, plural, =1{{count} more post waits.} other{{count} more posts wait.}}'**
  String bannerReadingQueue(String line, int count);

  /// No description provided for @bannerPauseNotifications.
  ///
  /// In en, this message translates to:
  /// **'Pause notifications'**
  String get bannerPauseNotifications;

  /// No description provided for @bannerResumeNotifications.
  ///
  /// In en, this message translates to:
  /// **'Resume notifications'**
  String get bannerResumeNotifications;

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Telegram is rate-limiting this account. Wait a minute and try again.'**
  String get errorRateLimited;

  /// No description provided for @errorPhoneNumberInvalid.
  ///
  /// In en, this message translates to:
  /// **'That phone number is not valid.'**
  String get errorPhoneNumberInvalid;

  /// No description provided for @errorPhoneNumberBanned.
  ///
  /// In en, this message translates to:
  /// **'Telegram has banned that phone number.'**
  String get errorPhoneNumberBanned;

  /// No description provided for @errorPhoneNumberFlood.
  ///
  /// In en, this message translates to:
  /// **'That number has asked for too many codes today. Try again tomorrow.'**
  String get errorPhoneNumberFlood;

  /// No description provided for @errorPhoneNumberOccupied.
  ///
  /// In en, this message translates to:
  /// **'That number already belongs to another account.'**
  String get errorPhoneNumberOccupied;

  /// No description provided for @errorCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Wrong code.'**
  String get errorCodeInvalid;

  /// No description provided for @errorCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'The code expired. Ask for a new one.'**
  String get errorCodeExpired;

  /// No description provided for @errorPasswordInvalid.
  ///
  /// In en, this message translates to:
  /// **'Wrong password.'**
  String get errorPasswordInvalid;

  /// No description provided for @errorPasswordRecoveryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This account has no recovery email, so the password cannot be reset here.'**
  String get errorPasswordRecoveryUnavailable;

  /// No description provided for @errorApiIdInvalid.
  ///
  /// In en, this message translates to:
  /// **'This build has no valid Telegram api_id/api_hash (see README).'**
  String get errorApiIdInvalid;

  /// No description provided for @errorChannelUnknown.
  ///
  /// In en, this message translates to:
  /// **'Telegram does not know that channel any more.'**
  String get errorChannelUnknown;

  /// No description provided for @errorChannelPrivate.
  ///
  /// In en, this message translates to:
  /// **'That channel is private now, or the account has left it.'**
  String get errorChannelPrivate;

  /// No description provided for @errorPostGone.
  ///
  /// In en, this message translates to:
  /// **'That post no longer exists.'**
  String get errorPostGone;

  /// No description provided for @errorWriteForbidden.
  ///
  /// In en, this message translates to:
  /// **'This channel does not let the account write here.'**
  String get errorWriteForbidden;

  /// No description provided for @errorBannedInChannel.
  ///
  /// In en, this message translates to:
  /// **'The account is banned in that channel.'**
  String get errorBannedInChannel;

  /// No description provided for @errorReactionInvalid.
  ///
  /// In en, this message translates to:
  /// **'This channel does not allow that reaction.'**
  String get errorReactionInvalid;

  /// No description provided for @errorConnectionClosed.
  ///
  /// In en, this message translates to:
  /// **'The connection to Telegram closed. Try again.'**
  String get errorConnectionClosed;

  /// Title of the feed's info screen while its name is loading.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get feedEditorFallbackTitle;

  /// No description provided for @feedEditorRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename feed'**
  String get feedEditorRenameTitle;

  /// Label of the feed name field in the rename dialog.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get feedEditorNameLabel;

  /// No description provided for @feedEditorTabChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get feedEditorTabChannels;

  /// Tab with the photos, videos, files, links and voice messages of all the feed's channels.
  ///
  /// In en, this message translates to:
  /// **'Shared media'**
  String get feedEditorTabSharedMedia;

  /// No description provided for @feedEditorAddChannel.
  ///
  /// In en, this message translates to:
  /// **'Add channel'**
  String get feedEditorAddChannel;

  /// No description provided for @feedEditorNewRule.
  ///
  /// In en, this message translates to:
  /// **'New rule'**
  String get feedEditorNewRule;

  /// Takes a channel out of the feed (the channel itself stays). Tooltip of the row's button and the confirming button of the dialog.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get feedEditorRemoveChannel;

  /// Title of the dialog that takes a channel out of the feed.
  ///
  /// In en, this message translates to:
  /// **'Remove {channel}?'**
  String feedEditorRemoveChannelTitle(String channel);

  /// A rule's name in quotes, inside a sentence. Several are joined by commas.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\"'**
  String feedEditorQuotedRuleName(String name);

  /// No description provided for @feedEditorRemoveChannelOneRule.
  ///
  /// In en, this message translates to:
  /// **'The rule {names} watches only this channel and is deleted with it.'**
  String feedEditorRemoveChannelOneRule(String names);

  /// Two or more rules; {names} is their quoted names joined by commas.
  ///
  /// In en, this message translates to:
  /// **'The rules {names} watch only this channel and are deleted with it.'**
  String feedEditorRemoveChannelRules(String names);

  /// Snackbar after a channel was taken out of the feed, with Undo.
  ///
  /// In en, this message translates to:
  /// **'{channel} removed'**
  String feedEditorChannelRemoved(String channel);

  /// No description provided for @feedEditorNoChannelsTitle.
  ///
  /// In en, this message translates to:
  /// **'No channels yet'**
  String get feedEditorNoChannelsTitle;

  /// No description provided for @feedEditorNoChannelsMessage.
  ///
  /// In en, this message translates to:
  /// **'Add channels your Telegram account has joined; this app never joins one for you.'**
  String get feedEditorNoChannelsMessage;

  /// Subtitle of a feed's channel the account has left.
  ///
  /// In en, this message translates to:
  /// **'Left in Telegram; history stays readable'**
  String get feedEditorChannelLeft;

  /// No description provided for @feedEditorSearchJoinedChannels.
  ///
  /// In en, this message translates to:
  /// **'Search joined channels'**
  String get feedEditorSearchJoinedChannels;

  /// No description provided for @feedEditorHideChannelsInFeeds.
  ///
  /// In en, this message translates to:
  /// **'Hide channels already in a feed'**
  String get feedEditorHideChannelsInFeeds;

  /// No description provided for @feedEditorAllChannelsInFeed.
  ///
  /// In en, this message translates to:
  /// **'Every channel you have joined is already in this feed.'**
  String get feedEditorAllChannelsInFeed;

  /// {option} is the checkbox label 'Hide channels already in a feed'.
  ///
  /// In en, this message translates to:
  /// **'The rest are in other feeds. Untick \"{option}\" to see them.'**
  String feedEditorRestInOtherFeeds(String option);

  /// No description provided for @feedEditorNoChannelMatches.
  ///
  /// In en, this message translates to:
  /// **'No channel matches \"{query}\".'**
  String feedEditorNoChannelMatches(String query);

  /// No description provided for @feedEditorTickChannels.
  ///
  /// In en, this message translates to:
  /// **'Tick the channels to add'**
  String get feedEditorTickChannels;

  /// No description provided for @feedEditorChannelsTicked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} channel ticked} other{{count} channels ticked}}'**
  String feedEditorChannelsTicked(int count);

  /// Row of the feed's info screen that opens the feed's filter; its subtitle says what the filter lets through.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get filterTileTitle;

  /// No description provided for @filterSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Show in this feed'**
  String get filterSheetTitle;

  /// No description provided for @filterPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get filterPosts;

  /// Filter choice: posts with and without media.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterPostsAll;

  /// No description provided for @filterPostsWithMedia.
  ///
  /// In en, this message translates to:
  /// **'With media'**
  String get filterPostsWithMedia;

  /// No description provided for @filterPostsTextOnly.
  ///
  /// In en, this message translates to:
  /// **'Text only'**
  String get filterPostsTextOnly;

  /// No description provided for @filterMediaTypes.
  ///
  /// In en, this message translates to:
  /// **'Media types'**
  String get filterMediaTypes;

  /// No description provided for @filterMediaTypesNote.
  ///
  /// In en, this message translates to:
  /// **'Leave all of them off to allow every type.'**
  String get filterMediaTypesNote;

  /// Kind of media in a feed's filter, lowercase: it is listed mid-line, and capitalized on the filter's chips.
  ///
  /// In en, this message translates to:
  /// **'photos'**
  String get filterKindPhotos;

  /// No description provided for @filterKindVideos.
  ///
  /// In en, this message translates to:
  /// **'videos'**
  String get filterKindVideos;

  /// No description provided for @filterKindGifs.
  ///
  /// In en, this message translates to:
  /// **'GIFs'**
  String get filterKindGifs;

  /// No description provided for @filterKindAudio.
  ///
  /// In en, this message translates to:
  /// **'audio'**
  String get filterKindAudio;

  /// No description provided for @filterKindVoice.
  ///
  /// In en, this message translates to:
  /// **'voice messages'**
  String get filterKindVoice;

  /// No description provided for @filterKindFiles.
  ///
  /// In en, this message translates to:
  /// **'files'**
  String get filterKindFiles;

  /// No description provided for @filterKindOther.
  ///
  /// In en, this message translates to:
  /// **'other (polls, stickers, …)'**
  String get filterKindOther;

  /// No description provided for @filterVideoLength.
  ///
  /// In en, this message translates to:
  /// **'Video length'**
  String get filterVideoLength;

  /// Choice of the 'Video length' row: no minimum duration.
  ///
  /// In en, this message translates to:
  /// **'Any length'**
  String get filterVideoAnyLength;

  /// Minimum video duration in seconds.
  ///
  /// In en, this message translates to:
  /// **'From {seconds} s'**
  String filterFromSeconds(int seconds);

  /// Minimum video duration in minutes.
  ///
  /// In en, this message translates to:
  /// **'From {minutes} min'**
  String filterFromMinutes(int minutes);

  /// Row that sets the minimum text length of posts without media.
  ///
  /// In en, this message translates to:
  /// **'Text posts'**
  String get filterTextPosts;

  /// Choice of the 'Text posts' row: no minimum length.
  ///
  /// In en, this message translates to:
  /// **'Any length'**
  String get filterTextAnyLength;

  /// Minimum text length of posts without media.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{From {count} characters}}'**
  String filterFromCharacters(int count);

  /// Heading of the words a feed's posts must match.
  ///
  /// In en, this message translates to:
  /// **'Text content'**
  String get filterTextContent;

  /// No description provided for @filterTextContentNote.
  ///
  /// In en, this message translates to:
  /// **'Only posts whose words match are shown, as a rule matches them. A \"Must not contain\" term hides the posts that have it.'**
  String get filterTextContentNote;

  /// No description provided for @filterWholePost.
  ///
  /// In en, this message translates to:
  /// **'Show the whole post'**
  String get filterWholePost;

  /// No description provided for @filterWholePostNote.
  ///
  /// In en, this message translates to:
  /// **'A post with several pictures or videos is shown complete, with its caption, as soon as one of them passes. Off shows only the parts that pass.'**
  String get filterWholePostNote;

  /// No description provided for @filterShowMinimized.
  ///
  /// In en, this message translates to:
  /// **'Show minimized'**
  String get filterShowMinimized;

  /// No description provided for @filterShowMinimizedNote.
  ///
  /// In en, this message translates to:
  /// **'The posts this feed leaves out stay in it as one line each, and a tap opens one. They count as hidden all the same.'**
  String get filterShowMinimizedNote;

  /// No description provided for @filterHiddenCountAsRead.
  ///
  /// In en, this message translates to:
  /// **'Posts this feed hides count as read, and rules stay quiet about them unless another feed with the same channel shows them.'**
  String get filterHiddenCountAsRead;

  /// No description provided for @filterShowEverything.
  ///
  /// In en, this message translates to:
  /// **'Show everything'**
  String get filterShowEverything;

  /// Summary of a feed filter that hides nothing.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get filterDescribeEverything;

  /// Part of a feed filter's one-line summary; parts are joined by ' · '.
  ///
  /// In en, this message translates to:
  /// **'with media'**
  String get filterDescribeWithMedia;

  /// No description provided for @filterDescribeTextOnly.
  ///
  /// In en, this message translates to:
  /// **'text only'**
  String get filterDescribeTextOnly;

  /// No description provided for @filterDescribeVideosFromSeconds.
  ///
  /// In en, this message translates to:
  /// **'videos from {seconds} s'**
  String filterDescribeVideosFromSeconds(int seconds);

  /// No description provided for @filterDescribeVideosFromMinutes.
  ///
  /// In en, this message translates to:
  /// **'videos from {minutes} min'**
  String filterDescribeVideosFromMinutes(int minutes);

  /// No description provided for @filterDescribeTextFrom.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{text from {count} characters}}'**
  String filterDescribeTextFrom(int count);

  /// {condition} is the filter's word condition in rule syntax.
  ///
  /// In en, this message translates to:
  /// **'text: {condition}'**
  String filterDescribeText(String condition);

  /// No description provided for @filterDescribeMatchingParts.
  ///
  /// In en, this message translates to:
  /// **'matching parts only'**
  String get filterDescribeMatchingParts;

  /// No description provided for @filterDescribeRestMinimized.
  ///
  /// In en, this message translates to:
  /// **'the rest minimized'**
  String get filterDescribeRestMinimized;

  /// Shown with Telegram's error code when a login step fails.
  ///
  /// In en, this message translates to:
  /// **'Telegram refused that.'**
  String get loginTelegramRefused;

  /// No description provided for @loginSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get loginSomethingWentWrong;

  /// Tooltip of the button that shows the typed password.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get loginShowPassword;

  /// Tooltip of the button that hides the typed password.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get loginHidePassword;

  /// No description provided for @loginNewCodeSent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way.'**
  String get loginNewCodeSent;

  /// No description provided for @loginPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to Telegram'**
  String get loginPhoneTitle;

  /// No description provided for @loginPhoneExplanation.
  ///
  /// In en, this message translates to:
  /// **'{appName} reads the channels your Telegram account has joined. Enter the phone number of that account in international format.'**
  String loginPhoneExplanation(String appName);

  /// No description provided for @loginPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get loginPhoneNumber;

  /// No description provided for @loginSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get loginSendCode;

  /// No description provided for @loginWithQrInstead.
  ///
  /// In en, this message translates to:
  /// **'Log in with QR code instead'**
  String get loginWithQrInstead;

  /// No description provided for @loginCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get loginCodeTitle;

  /// No description provided for @loginCodeExplanation.
  ///
  /// In en, this message translates to:
  /// **'Telegram sent a code to {phoneNumber} (by SMS or to another logged-in device).'**
  String loginCodeExplanation(String phoneNumber);

  /// No description provided for @loginCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get loginCode;

  /// No description provided for @loginResendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get loginResendCode;

  /// No description provided for @loginChangeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get loginChangeNumber;

  /// No description provided for @loginEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Your email'**
  String get loginEmailTitle;

  /// No description provided for @loginEmailExplanation.
  ///
  /// In en, this message translates to:
  /// **'Telegram asks this account for an email address. Login codes will be sent to it every time you log in from a new device.'**
  String get loginEmailExplanation;

  /// No description provided for @loginEmail.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get loginEmail;

  /// No description provided for @loginEmailCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get loginEmailCodeTitle;

  /// No description provided for @loginEmailCodeExplanation.
  ///
  /// In en, this message translates to:
  /// **'Telegram sent a code to {email}. Look in the spam folder too.'**
  String loginEmailCodeExplanation(String email);

  /// No description provided for @loginUnsupportedExplanation.
  ///
  /// In en, this message translates to:
  /// **'Telegram asks for a Premium purchase before it lets this number log in, which this app cannot do. Log in with the official Telegram app first, or use another number.'**
  String get loginUnsupportedExplanation;

  /// No description provided for @loginPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Two-step verification'**
  String get loginPasswordTitle;

  /// No description provided for @loginPasswordExplanation.
  ///
  /// In en, this message translates to:
  /// **'Your account has a cloud password.'**
  String get loginPasswordExplanation;

  /// No description provided for @loginPasswordExplanationWithHint.
  ///
  /// In en, this message translates to:
  /// **'Your account has a cloud password. Hint: {hint}'**
  String loginPasswordExplanationWithHint(String hint);

  /// No description provided for @loginPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPassword;

  /// No description provided for @loginPasswordForgotten.
  ///
  /// In en, this message translates to:
  /// **'Forgotten it? A cloud password can only be reset in the official Telegram app, under Settings, Privacy and Security.'**
  String get loginPasswordForgotten;

  /// No description provided for @loginNewAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get loginNewAccountTitle;

  /// No description provided for @loginNewAccountExplanation.
  ///
  /// In en, this message translates to:
  /// **'This number has no Telegram account yet. Enter a first name to create one.'**
  String get loginNewAccountExplanation;

  /// No description provided for @loginFirstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get loginFirstName;

  /// No description provided for @loginCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get loginCreateAccount;

  /// No description provided for @loginQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in with QR code'**
  String get loginQrTitle;

  /// The Ukrainian names the menu items as the official app shows them today.
  ///
  /// In en, this message translates to:
  /// **'In Telegram on your phone open Settings, Devices, Link Desktop Device, and scan this code. It refreshes automatically.'**
  String get loginQrExplanation;

  /// No description provided for @loginQrBackFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not go back to the phone number.'**
  String get loginQrBackFailed;

  /// No description provided for @loginWithPhoneInstead.
  ///
  /// In en, this message translates to:
  /// **'Use a phone number instead'**
  String get loginWithPhoneInstead;

  /// Button on the login screens that switches back to an account already logged in; {account} is its name.
  ///
  /// In en, this message translates to:
  /// **'Use {account} instead'**
  String loginUseOtherAccount(String account);

  /// No description provided for @conditionErrorStoredUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Stored condition could not be parsed; rewrite it.'**
  String get conditionErrorStoredUnreadable;

  /// No description provided for @conditionErrorTooNested.
  ///
  /// In en, this message translates to:
  /// **'Too nested for the builder; keep editing as text.'**
  String get conditionErrorTooNested;

  /// No description provided for @conditionErrorUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This condition cannot be read.'**
  String get conditionErrorUnreadable;

  /// Syntax error in the text form of a condition; the cursor is placed where it is.
  ///
  /// In en, this message translates to:
  /// **'Expected a term where the cursor is.'**
  String get conditionErrorExpectedTerm;

  /// Syntax error: a closing bracket is missing.
  ///
  /// In en, this message translates to:
  /// **'Expected \")\" where the cursor is.'**
  String get conditionErrorExpectedBracket;

  /// Syntax error: a character that does not belong there.
  ///
  /// In en, this message translates to:
  /// **'Unexpected \"{symbol}\" where the cursor is.'**
  String conditionErrorUnexpected(String symbol);

  /// No description provided for @conditionErrorUnterminatedQuote.
  ///
  /// In en, this message translates to:
  /// **'Unterminated quote where the cursor is.'**
  String get conditionErrorUnterminatedQuote;

  /// Syntax error: a backslash at the end with nothing after it.
  ///
  /// In en, this message translates to:
  /// **'Dangling escape where the cursor is.'**
  String get conditionErrorDanglingEscape;

  /// Syntax error: quotes with nothing inside.
  ///
  /// In en, this message translates to:
  /// **'Empty term where the cursor is.'**
  String get conditionErrorEmptyTerm;

  /// Syntax error: AND, OR or NOT used as a search word.
  ///
  /// In en, this message translates to:
  /// **'\"{word}\" is a keyword; quote it to match the word where the cursor is.'**
  String conditionErrorKeyword(String word);

  /// Segment: edit the condition with the visual builder.
  ///
  /// In en, this message translates to:
  /// **'Builder'**
  String get conditionModeBuilder;

  /// Segment: edit the condition as text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get conditionModeText;

  /// No description provided for @conditionTextHelper.
  ///
  /// In en, this message translates to:
  /// **'Words or \"phrases\" joined by AND, OR, NOT, with brackets.'**
  String get conditionTextHelper;

  /// No description provided for @conditionSyntaxTooltip.
  ///
  /// In en, this message translates to:
  /// **'Syntax'**
  String get conditionSyntaxTooltip;

  /// No description provided for @conditionSyntaxTitle.
  ///
  /// In en, this message translates to:
  /// **'Writing a condition'**
  String get conditionSyntaxTitle;

  /// No description provided for @conditionSyntaxWord.
  ///
  /// In en, this message translates to:
  /// **'the word, wherever it stands'**
  String get conditionSyntaxWord;

  /// No description provided for @conditionSyntaxPhrase.
  ///
  /// In en, this message translates to:
  /// **'those words next to each other'**
  String get conditionSyntaxPhrase;

  /// No description provided for @conditionSyntaxAnd.
  ///
  /// In en, this message translates to:
  /// **'both have to be there'**
  String get conditionSyntaxAnd;

  /// No description provided for @conditionSyntaxOr.
  ///
  /// In en, this message translates to:
  /// **'either one is enough'**
  String get conditionSyntaxOr;

  /// No description provided for @conditionSyntaxNot.
  ///
  /// In en, this message translates to:
  /// **'the post must not have it'**
  String get conditionSyntaxNot;

  /// No description provided for @conditionSyntaxBrackets.
  ///
  /// In en, this message translates to:
  /// **'brackets group the parts'**
  String get conditionSyntaxBrackets;

  /// No description provided for @conditionSyntaxSubstring.
  ///
  /// In en, this message translates to:
  /// **'also inside longer words, like \"rates\"'**
  String get conditionSyntaxSubstring;

  /// No description provided for @conditionSyntaxCase.
  ///
  /// In en, this message translates to:
  /// **'exactly that spelling, capitals included'**
  String get conditionSyntaxCase;

  /// No description provided for @conditionAddTerm.
  ///
  /// In en, this message translates to:
  /// **'Add a term'**
  String get conditionAddTerm;

  /// Between two groups of words in the visual condition builder.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get conditionOr;

  /// Between two words of a group in the visual condition builder.
  ///
  /// In en, this message translates to:
  /// **'AND'**
  String get conditionAnd;

  /// No description provided for @conditionAndAnotherWord.
  ///
  /// In en, this message translates to:
  /// **'AND another word'**
  String get conditionAndAnotherWord;

  /// No description provided for @conditionOrAlternative.
  ///
  /// In en, this message translates to:
  /// **'OR alternative'**
  String get conditionOrAlternative;

  /// No description provided for @conditionTermHint.
  ///
  /// In en, this message translates to:
  /// **'word or phrase'**
  String get conditionTermHint;

  /// No description provided for @conditionTermHintNegated.
  ///
  /// In en, this message translates to:
  /// **'word it must not have'**
  String get conditionTermHintNegated;

  /// No description provided for @conditionMustNotContain.
  ///
  /// In en, this message translates to:
  /// **'Must not contain'**
  String get conditionMustNotContain;

  /// No description provided for @conditionWholeWord.
  ///
  /// In en, this message translates to:
  /// **'Whole word'**
  String get conditionWholeWord;

  /// No description provided for @conditionMatchCase.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get conditionMatchCase;

  /// No description provided for @ruleDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get ruleDiscardTitle;

  /// No description provided for @ruleDiscardMessage.
  ///
  /// In en, this message translates to:
  /// **'The changes to this rule are not saved.'**
  String get ruleDiscardMessage;

  /// No description provided for @ruleErrorNoName.
  ///
  /// In en, this message translates to:
  /// **'Give the rule a name.'**
  String get ruleErrorNoName;

  /// No description provided for @ruleErrorNoFeed.
  ///
  /// In en, this message translates to:
  /// **'A rule belongs to a feed: create one first.'**
  String get ruleErrorNoFeed;

  /// No description provided for @scheduleErrorNoDays.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one day, or the rule never notifies.'**
  String get scheduleErrorNoDays;

  /// No description provided for @ruleNotifyAskTitle.
  ///
  /// In en, this message translates to:
  /// **'Let the app notify you?'**
  String get ruleNotifyAskTitle;

  /// No description provided for @ruleNotifyAskMessage.
  ///
  /// In en, this message translates to:
  /// **'This rule notifies you about the posts it matches, which Android has to allow. Without it the rule still runs, but stays silent.'**
  String get ruleNotifyAskMessage;

  /// No description provided for @ruleDndAskTitle.
  ///
  /// In en, this message translates to:
  /// **'Show urgent posts in Do Not Disturb?'**
  String get ruleDndAskTitle;

  /// No description provided for @ruleDndAskMessage.
  ///
  /// In en, this message translates to:
  /// **'Urgent rules can break through Do Not Disturb, but Android must allow this app to do so. Open the setting now? The rule works either way.'**
  String get ruleDndAskMessage;

  /// No description provided for @ruleDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String ruleDeleteTitle(String name);

  /// Part of the dry-run footer: how many channels' posts were read.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{from {count} channel} other{from {count} channels}}'**
  String ruleDryRunScopeChannels(int count);

  /// Part of the dry-run footer, after the channel count, when the feed has more channels than a dry run reads.
  ///
  /// In en, this message translates to:
  /// **'of {total} (the first {limit} are checked)'**
  String ruleDryRunScopeOfTotal(int total, int limit);

  /// Part of the dry-run footer: channels whose posts could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'({count} could not be read)'**
  String ruleDryRunScopeFailed(int count);

  /// Dry-run footer. scope is ruleDryRunScopeChannels, optionally followed by ruleDryRunScopeOfTotal and ruleDryRunScopeFailed.
  ///
  /// In en, this message translates to:
  /// **'Checked the latest posts {scope}.'**
  String ruleDryRunChecked(String scope);

  /// No description provided for @ruleDryRunAiNone.
  ///
  /// In en, this message translates to:
  /// **'The AI matched none of the {checked} newest posts it checked ({passed} of the last {scanned} passed the keywords).'**
  String ruleDryRunAiNone(int checked, int passed, int scanned);

  /// No description provided for @ruleDryRunAiMatched.
  ///
  /// In en, this message translates to:
  /// **'The AI matched {matched} of the {checked} newest posts it checked:'**
  String ruleDryRunAiMatched(int matched, int checked);

  /// No description provided for @ruleDryRunAiFailed.
  ///
  /// In en, this message translates to:
  /// **'The AI check failed: {message}'**
  String ruleDryRunAiFailed(String message);

  /// No description provided for @ruleDryRunNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No match in the last {scanned} posts.'**
  String ruleDryRunNoMatch(int scanned);

  /// Heading above the posts a dry run matched.
  ///
  /// In en, this message translates to:
  /// **'{matched} of the last {scanned} posts match:'**
  String ruleDryRunMatches(int matched, int scanned);

  /// Title of the rule editor for a new rule, and the button that opens it.
  ///
  /// In en, this message translates to:
  /// **'New rule'**
  String get ruleNew;

  /// No description provided for @ruleEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit rule'**
  String get ruleEditTitle;

  /// No description provided for @ruleNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get ruleNameLabel;

  /// No description provided for @ruleEnabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get ruleEnabledTitle;

  /// No description provided for @ruleEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Off keeps the rule but stops it notifying'**
  String get ruleEnabledSubtitle;

  /// No description provided for @ruleFeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get ruleFeedLabel;

  /// No description provided for @ruleChannelsLabel.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get ruleChannelsLabel;

  /// No description provided for @ruleEveryChannelOfFeed.
  ///
  /// In en, this message translates to:
  /// **'Every channel of the feed'**
  String get ruleEveryChannelOfFeed;

  /// No description provided for @ruleConditionTitle.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get ruleConditionTitle;

  /// No description provided for @ruleNoConditionNote.
  ///
  /// In en, this message translates to:
  /// **'No condition: every new post from this rule\'s channels notifies. Add terms to notify only about some of them.'**
  String get ruleNoConditionNote;

  /// No description provided for @semanticNoKeywordsNote.
  ///
  /// In en, this message translates to:
  /// **'No keywords: every new post from this rule\'s channels goes to the AI. Add terms to send only posts that contain them.'**
  String get semanticNoKeywordsNote;

  /// No description provided for @semanticAfterKeywordsNote.
  ///
  /// In en, this message translates to:
  /// **'The AI checks only the posts that pass these keywords.'**
  String get semanticAfterKeywordsNote;

  /// No description provided for @ruleDryRunTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get ruleDryRunTesting;

  /// No description provided for @ruleDryRunButton.
  ///
  /// In en, this message translates to:
  /// **'Test on recent posts'**
  String get ruleDryRunButton;

  /// Heading above the priority choice of a rule.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get ruleNotificationTitle;

  /// No description provided for @rulePrioritySilent.
  ///
  /// In en, this message translates to:
  /// **'Silent'**
  String get rulePrioritySilent;

  /// No description provided for @rulePriorityNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get rulePriorityNormal;

  /// No description provided for @rulePriorityUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get rulePriorityUrgent;

  /// No description provided for @rulePrioritySilentInfo.
  ///
  /// In en, this message translates to:
  /// **'In the tray only, with no sound and no vibration.'**
  String get rulePrioritySilentInfo;

  /// No description provided for @rulePriorityNormalInfo.
  ///
  /// In en, this message translates to:
  /// **'Pops up, with the sound and vibration set in Notifications and sounds.'**
  String get rulePriorityNormalInfo;

  /// No description provided for @rulePriorityUrgentInfo.
  ///
  /// In en, this message translates to:
  /// **'Pops up, and breaks through Do Not Disturb where Android allows it.'**
  String get rulePriorityUrgentInfo;

  /// No description provided for @ruleReadAloud.
  ///
  /// In en, this message translates to:
  /// **'Read the post aloud'**
  String get ruleReadAloud;

  /// No description provided for @scheduleSwitch.
  ///
  /// In en, this message translates to:
  /// **'Only at certain times'**
  String get scheduleSwitch;

  /// No description provided for @scheduleMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get scheduleMon;

  /// No description provided for @scheduleTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get scheduleTue;

  /// No description provided for @scheduleWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get scheduleWed;

  /// No description provided for @scheduleThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get scheduleThu;

  /// No description provided for @scheduleFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get scheduleFri;

  /// No description provided for @scheduleSat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get scheduleSat;

  /// No description provided for @scheduleSun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get scheduleSun;

  /// Button with the start time of a rule's schedule.
  ///
  /// In en, this message translates to:
  /// **'From {time}'**
  String scheduleFrom(String time);

  /// Button with the end time of a rule's schedule.
  ///
  /// In en, this message translates to:
  /// **'To {time}'**
  String scheduleTo(String time);

  /// No description provided for @scheduleNextDay.
  ///
  /// In en, this message translates to:
  /// **'(next day)'**
  String get scheduleNextDay;

  /// No description provided for @semanticAlsoAsk.
  ///
  /// In en, this message translates to:
  /// **'Also ask the AI'**
  String get semanticAlsoAsk;

  /// No description provided for @semanticAlsoAskSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A model you set up in Settings decides whether a post is about what you describe.'**
  String get semanticAlsoAskSubtitle;

  /// No description provided for @semanticPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'What the post should be about'**
  String get semanticPromptLabel;

  /// No description provided for @semanticPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Central bank interest rate decisions'**
  String get semanticPromptHint;

  /// No description provided for @semanticNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'The AI endpoint is not set up yet (Settings, AI rules). Until then this rule is skipped.'**
  String get semanticNotConfigured;

  /// No description provided for @rulesNoFeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'No feeds yet'**
  String get rulesNoFeedsTitle;

  /// No description provided for @rulesNoFeedsMessage.
  ///
  /// In en, this message translates to:
  /// **'Every rule belongs to a feed and watches its channels. Make a feed first, then give it rules.'**
  String get rulesNoFeedsMessage;

  /// No description provided for @rulesGoToFeeds.
  ///
  /// In en, this message translates to:
  /// **'Go to feeds'**
  String get rulesGoToFeeds;

  /// No description provided for @semanticSkippedTitle.
  ///
  /// In en, this message translates to:
  /// **'AI rules are being skipped'**
  String get semanticSkippedTitle;

  /// Why AI rules fail, and the time of the last attempt.
  ///
  /// In en, this message translates to:
  /// **'{message} (last tried {time})'**
  String semanticSkippedSubtitle(String message, String time);

  /// No description provided for @ruleScopeChannelLeft.
  ///
  /// In en, this message translates to:
  /// **'A channel that left the feed'**
  String get ruleScopeChannelLeft;

  /// No description provided for @rulesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No rules yet'**
  String get rulesEmptyTitle;

  /// No description provided for @rulesEmptyNoFeeds.
  ///
  /// In en, this message translates to:
  /// **'Rules belong to feeds. Make a feed first, then give it rules.'**
  String get rulesEmptyNoFeeds;

  /// No description provided for @rulesEmptyFeed.
  ///
  /// In en, this message translates to:
  /// **'A rule watches this feed\'s channels, or one of them, and notifies you, optionally reading the post aloud: give it words to look for, or leave the condition empty to be notified about every post the feed shows.'**
  String get rulesEmptyFeed;

  /// No description provided for @rulesEmptyAll.
  ///
  /// In en, this message translates to:
  /// **'Every feed has its own rules: a rule watches the feed\'s channels, or one of them, and notifies you, optionally reading the post aloud.'**
  String get rulesEmptyAll;

  /// In a rule's summary line: the rule watches every channel of its feed.
  ///
  /// In en, this message translates to:
  /// **'Every channel'**
  String get ruleScopeEveryChannel;

  /// In a rule's summary line: its priority.
  ///
  /// In en, this message translates to:
  /// **'urgent'**
  String get ruleTileUrgent;

  /// In a rule's summary line: its priority.
  ///
  /// In en, this message translates to:
  /// **'silent'**
  String get ruleTileSilent;

  /// In a rule's summary line: the rule reads the post aloud.
  ///
  /// In en, this message translates to:
  /// **'read aloud'**
  String get ruleTileReadAloud;

  /// In a rule's summary line: a rule without a condition.
  ///
  /// In en, this message translates to:
  /// **'every post'**
  String get ruleTileEveryPost;

  /// No description provided for @ruleTileInvalidCondition.
  ///
  /// In en, this message translates to:
  /// **'(invalid condition)'**
  String get ruleTileInvalidCondition;

  /// No description provided for @ruleSemanticsUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent rule'**
  String get ruleSemanticsUrgent;

  /// No description provided for @ruleSemanticsSilent.
  ///
  /// In en, this message translates to:
  /// **'Silent rule'**
  String get ruleSemanticsSilent;

  /// No description provided for @ruleSemanticsNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal rule'**
  String get ruleSemanticsNormal;

  /// In a rule's summary line: the description the AI checks.
  ///
  /// In en, this message translates to:
  /// **'AI: {prompt}'**
  String semanticPreview(String prompt);

  /// In a rule's summary line: the AI description and the keyword condition (in rule syntax) a post must pass first.
  ///
  /// In en, this message translates to:
  /// **'AI: {prompt} · only if {keywords}'**
  String semanticPreviewWithKeywords(String prompt, String keywords);

  /// No description provided for @ruleBatteryBanner.
  ///
  /// In en, this message translates to:
  /// **'Android may stop background watching, and rules would then go quiet. Allow the app to ignore battery optimisation so they keep working.'**
  String get ruleBatteryBanner;

  /// No description provided for @semanticProblemNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'The AI endpoint is not set up in Settings.'**
  String get semanticProblemNotSetUp;

  /// error is the network error, in English.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the AI endpoint: {error}'**
  String semanticProblemUnreachable(String error);

  /// status is the HTTP status code; error is the endpoint's own error text.
  ///
  /// In en, this message translates to:
  /// **'The AI endpoint answered {status}: {error}'**
  String semanticProblemHttpStatus(int status, String error);

  /// No description provided for @semanticProblemUnexpectedAnswer.
  ///
  /// In en, this message translates to:
  /// **'The AI endpoint sent an unexpected answer.'**
  String get semanticProblemUnexpectedAnswer;

  /// No description provided for @semanticProblemEmptyAnswer.
  ///
  /// In en, this message translates to:
  /// **'The model returned an empty answer.'**
  String get semanticProblemEmptyAnswer;

  /// No description provided for @readAloudTitle.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get readAloudTitle;

  /// Tooltip of the button that speaks a sample with the chosen speed, pitch and voice.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get readAloudPreview;

  /// The sample sentence the preview button speaks aloud.
  ///
  /// In en, this message translates to:
  /// **'New post in Example channel. This is how posts will sound.'**
  String get readAloudPreviewText;

  /// Title of the speech speed slider with its value, e.g. 1.0×.
  ///
  /// In en, this message translates to:
  /// **'Speed  ·  {speed}×'**
  String readAloudSpeed(String speed);

  /// What a screen reader says for the speed slider's value.
  ///
  /// In en, this message translates to:
  /// **'Speed {speed} times'**
  String readAloudSpeedSemantics(String speed);

  /// Title of the voice pitch slider with its value.
  ///
  /// In en, this message translates to:
  /// **'Pitch  ·  {pitch}'**
  String readAloudPitch(String pitch);

  /// What a screen reader says for the pitch slider's value.
  ///
  /// In en, this message translates to:
  /// **'Pitch {pitch}'**
  String readAloudPitchSemantics(String pitch);

  /// No description provided for @readAloudMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Maximum length'**
  String get readAloudMaxLength;

  /// The quoted words are what read-aloud says where it cuts a long post short.
  ///
  /// In en, this message translates to:
  /// **'Posts longer than {maxChars} characters end with \"and more\"'**
  String readAloudMaxLengthSubtitle(int maxChars);

  /// No description provided for @readAloudDefaultLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language when unknown'**
  String get readAloudDefaultLanguage;

  /// No description provided for @readAloudDefaultLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used when a post\'s language cannot be detected'**
  String get readAloudDefaultLanguageSubtitle;

  /// No description provided for @readAloudVoices.
  ///
  /// In en, this message translates to:
  /// **'Voices'**
  String get readAloudVoices;

  /// No description provided for @readAloudNoVoices.
  ///
  /// In en, this message translates to:
  /// **'No voices reported by the speech engine'**
  String get readAloudNoVoices;

  /// No description provided for @readAloudNoVoicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The system default voice is used for every language'**
  String get readAloudNoVoicesSubtitle;

  /// Tooltip of the button that drops a language's chosen voice.
  ///
  /// In en, this message translates to:
  /// **'Use the default voice'**
  String get readAloudUseDefaultVoice;

  /// No description provided for @readAloudAddLanguage.
  ///
  /// In en, this message translates to:
  /// **'Add language'**
  String get readAloudAddLanguage;

  /// No description provided for @readAloudOtherLanguagesFooter.
  ///
  /// In en, this message translates to:
  /// **'Every other language is read with the phone\'s default voice for it.'**
  String get readAloudOtherLanguagesFooter;

  /// No description provided for @readAloudPhoneDefaultVoice.
  ///
  /// In en, this message translates to:
  /// **'The phone\'s default voice'**
  String get readAloudPhoneDefaultVoice;

  /// No description provided for @readAloudSearchLanguages.
  ///
  /// In en, this message translates to:
  /// **'Search languages'**
  String get readAloudSearchLanguages;

  /// A speech engine voice named by its id, e.g. Voice SFG.
  ///
  /// In en, this message translates to:
  /// **'Voice {id}'**
  String readAloudVoiceId(String id);

  /// Marks a voice that needs the internet, e.g. Voice HFD · UA · online.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get readAloudVoiceOnline;

  /// A female voice, followed by its number, e.g. Female 1 · US.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get readAloudVoiceFemale;

  /// A male voice, followed by its number, e.g. Male 2 · GB.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get readAloudVoiceMale;

  /// No description provided for @notificationSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications and sounds'**
  String get notificationSettingsTitle;

  /// No description provided for @notificationSettingsRestartTitle.
  ///
  /// In en, this message translates to:
  /// **'Restart the app?'**
  String get notificationSettingsRestartTitle;

  /// No description provided for @notificationSettingsRestartStartsWatching.
  ///
  /// In en, this message translates to:
  /// **'Watching in the background starts when the app starts again.'**
  String get notificationSettingsRestartStartsWatching;

  /// No description provided for @notificationSettingsRestartStopsWatching.
  ///
  /// In en, this message translates to:
  /// **'The permanent notification goes away when the app starts again.'**
  String get notificationSettingsRestartStopsWatching;

  /// Banner shown while background watching is off but the app has not restarted yet.
  ///
  /// In en, this message translates to:
  /// **'The permanent notification goes when the app starts again.'**
  String get notificationSettingsRestartDueStopsWatching;

  /// No description provided for @notificationSettingsRestartNow.
  ///
  /// In en, this message translates to:
  /// **'Restart now'**
  String get notificationSettingsRestartNow;

  /// No description provided for @notificationSettingsBlocked.
  ///
  /// In en, this message translates to:
  /// **'Android blocks this app\'s notifications, so no rule can notify you.'**
  String get notificationSettingsBlocked;

  /// Button that opens Android's notification settings of the app.
  ///
  /// In en, this message translates to:
  /// **'Turn them on'**
  String get notificationSettingsTurnOn;

  /// No description provided for @notificationSettingsRuleNotifications.
  ///
  /// In en, this message translates to:
  /// **'Rule notifications'**
  String get notificationSettingsRuleNotifications;

  /// No description provided for @notificationSettingsBadgeCounter.
  ///
  /// In en, this message translates to:
  /// **'Badge counter'**
  String get notificationSettingsBadgeCounter;

  /// No description provided for @notificationSettingsCountUnreadPosts.
  ///
  /// In en, this message translates to:
  /// **'Count unread posts'**
  String get notificationSettingsCountUnreadPosts;

  /// No description provided for @notificationSettingsCountFooter.
  ///
  /// In en, this message translates to:
  /// **'The badges of the feeds and of the folder tabs count the unread posts. Off, they count the channels that have unread posts.'**
  String get notificationSettingsCountFooter;

  /// No description provided for @notificationSettingsBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get notificationSettingsBackground;

  /// No description provided for @notificationSettingsWatchInBackground.
  ///
  /// In en, this message translates to:
  /// **'Watch channels in the background'**
  String get notificationSettingsWatchInBackground;

  /// No description provided for @notificationSettingsWatchInBackgroundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rules keep running while the app is closed. Off removes the permanent notification, and rules then only notify while the app is open. The app restarts to apply it.'**
  String get notificationSettingsWatchInBackgroundSubtitle;

  /// No description provided for @notificationSettingsSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'System notification settings'**
  String get notificationSettingsSystemSettings;

  /// The message is Android's own error text.
  ///
  /// In en, this message translates to:
  /// **'No sound picker: {message}'**
  String notificationSettingsNoSoundPicker(String message);

  /// No description provided for @notificationSettingsNoSoundPickerOnDevice.
  ///
  /// In en, this message translates to:
  /// **'No sound picker on this device.'**
  String get notificationSettingsNoSoundPickerOnDevice;

  /// No description provided for @notificationSettingsNormalSound.
  ///
  /// In en, this message translates to:
  /// **'Normal rules: sound'**
  String get notificationSettingsNormalSound;

  /// No description provided for @notificationSettingsNormalVibrate.
  ///
  /// In en, this message translates to:
  /// **'Normal rules: vibrate'**
  String get notificationSettingsNormalVibrate;

  /// No description provided for @notificationSettingsUrgentSound.
  ///
  /// In en, this message translates to:
  /// **'Urgent rules: sound'**
  String get notificationSettingsUrgentSound;

  /// No description provided for @notificationSettingsUrgentVibrate.
  ///
  /// In en, this message translates to:
  /// **'Urgent rules: vibrate'**
  String get notificationSettingsUrgentVibrate;

  /// Subtitle of a sound row when no sound was chosen.
  ///
  /// In en, this message translates to:
  /// **'The system default'**
  String get notificationSettingsSystemDefaultSound;

  /// Subtitle of a sound row when Android cannot name the chosen sound.
  ///
  /// In en, this message translates to:
  /// **'A chosen sound'**
  String get notificationSettingsChosenSound;

  /// Tooltip of the button that resets a rule sound to the system default.
  ///
  /// In en, this message translates to:
  /// **'Use the default'**
  String get notificationSettingsUseDefaultSound;

  /// No description provided for @notificationSettingsSilentRulesFooter.
  ///
  /// In en, this message translates to:
  /// **'Silent rules stay silent.'**
  String get notificationSettingsSilentRulesFooter;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy and security'**
  String get privacyTitle;

  /// No description provided for @privacySecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get privacySecurity;

  /// No description provided for @privacyAppLockFooter.
  ///
  /// In en, this message translates to:
  /// **'A PIN, or the phone\'s own fingerprint or face, is asked for when the app has rested. Without it anyone holding the unlocked phone can read your channels.'**
  String get privacyAppLockFooter;

  /// No description provided for @appLockTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLockTitle;

  /// No description provided for @appLockLocked.
  ///
  /// In en, this message translates to:
  /// **'{appName} is locked'**
  String appLockLocked(String appName);

  /// What Android's fingerprint or face prompt says it is for.
  ///
  /// In en, this message translates to:
  /// **'Unlock {appName}'**
  String appLockUnlockReason(String appName);

  /// No description provided for @appLockBiometricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The phone\'s check is not available; use the PIN.'**
  String get appLockBiometricsUnavailable;

  /// No description provided for @appLockWrongPin.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN'**
  String get appLockWrongPin;

  /// No description provided for @appLockTooManyTries.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Try again in {seconds, plural, =1{1 second} other{{seconds} seconds}}.'**
  String appLockTooManyTries(int seconds);

  /// No description provided for @appLockShowContent.
  ///
  /// In en, this message translates to:
  /// **'Show app content in task switcher'**
  String get appLockShowContent;

  /// No description provided for @appLockShowContentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Off, the task switcher shows a blank card and screenshots are refused while the lock is set'**
  String get appLockShowContentSubtitle;

  /// No description provided for @appLockPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get appLockPin;

  /// No description provided for @appLockUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get appLockUnlock;

  /// No description provided for @appLockUseBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint or face'**
  String get appLockUseBiometrics;

  /// No description provided for @appLockRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the lock?'**
  String get appLockRemoveTitle;

  /// No description provided for @appLockRemoveMessage.
  ///
  /// In en, this message translates to:
  /// **'Anyone holding the unlocked phone can then read your channels.'**
  String get appLockRemoveMessage;

  /// No description provided for @appLockTooShort.
  ///
  /// In en, this message translates to:
  /// **'At least four digits'**
  String get appLockTooShort;

  /// The PIN and its repetition differ.
  ///
  /// In en, this message translates to:
  /// **'The two do not match'**
  String get appLockMismatch;

  /// No description provided for @appLockPinReplaced.
  ///
  /// In en, this message translates to:
  /// **'PIN replaced'**
  String get appLockPinReplaced;

  /// No description provided for @appLockPinSet.
  ///
  /// In en, this message translates to:
  /// **'PIN set, the lock is on'**
  String get appLockPinSet;

  /// Ask for the PIN again as soon as the app is left.
  ///
  /// In en, this message translates to:
  /// **'At once'**
  String get appLockTimeoutAtOnce;

  /// No description provided for @appLockTimeoutMinute.
  ///
  /// In en, this message translates to:
  /// **'After a minute'**
  String get appLockTimeoutMinute;

  /// No description provided for @appLockTimeoutFiveMinutes.
  ///
  /// In en, this message translates to:
  /// **'After five minutes'**
  String get appLockTimeoutFiveMinutes;

  /// No description provided for @appLockTimeoutHour.
  ///
  /// In en, this message translates to:
  /// **'After an hour'**
  String get appLockTimeoutHour;

  /// No description provided for @appLockEnterPinToChange.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN to change the lock'**
  String get appLockEnterPinToChange;

  /// No description provided for @appLockIntroWithPin.
  ///
  /// In en, this message translates to:
  /// **'The app asks for this PIN when it has rested. Setting a new one replaces it.'**
  String get appLockIntroWithPin;

  /// No description provided for @appLockIntroNoPin.
  ///
  /// In en, this message translates to:
  /// **'A PIN keeps the channels you read out of the hands of whoever holds the unlocked phone.'**
  String get appLockIntroNoPin;

  /// No description provided for @appLockNewPin.
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get appLockNewPin;

  /// No description provided for @appLockPinAgain.
  ///
  /// In en, this message translates to:
  /// **'PIN again'**
  String get appLockPinAgain;

  /// No description provided for @appLockReplacePin.
  ///
  /// In en, this message translates to:
  /// **'Replace the PIN'**
  String get appLockReplacePin;

  /// No description provided for @appLockSetPin.
  ///
  /// In en, this message translates to:
  /// **'Set the PIN'**
  String get appLockSetPin;

  /// No description provided for @appLockRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove the lock'**
  String get appLockRemove;

  /// Header above the choices of how long the app may rest before it asks for the PIN again.
  ///
  /// In en, this message translates to:
  /// **'Ask again'**
  String get appLockAskAgain;

  /// No description provided for @appLockBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint or face'**
  String get appLockBiometrics;

  /// No description provided for @appLockBiometricsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Offered first when the app is locked; the PIN always works too'**
  String get appLockBiometricsSubtitle;

  /// The name of a language a speech engine offers, by its ISO 639 code, as a list item. The app shows the code itself for codes outside this list.
  ///
  /// In en, this message translates to:
  /// **'{code, select, af{Afrikaans} am{Amharic} ar{Arabic} as{Assamese} az{Azerbaijani} be{Belarusian} bg{Bulgarian} bn{Bengali} brx{Bodo} bs{Bosnian} ca{Catalan} cmn{Mandarin} cs{Czech} cy{Welsh} da{Danish} de{German} doi{Dogri} el{Greek} en{English} es{Spanish} et{Estonian} eu{Basque} fa{Persian} fi{Finnish} fil{Filipino} fr{French} ga{Irish} gl{Galician} gu{Gujarati} he{Hebrew} hi{Hindi} hr{Croatian} hu{Hungarian} hy{Armenian} id{Indonesian} is{Icelandic} it{Italian} ja{Japanese} jv{Javanese} ka{Georgian} kk{Kazakh} km{Khmer} kn{Kannada} ko{Korean} kok{Konkani} ks{Kashmiri} ky{Kyrgyz} lo{Lao} lt{Lithuanian} lv{Latvian} mai{Maithili} mk{Macedonian} ml{Malayalam} mn{Mongolian} mni{Manipuri} mr{Marathi} ms{Malay} my{Burmese} nb{Norwegian} ne{Nepali} nl{Dutch} no{Norwegian} or{Odia} pa{Punjabi} pl{Polish} pt{Portuguese} ro{Romanian} ru{Russian} sa{Sanskrit} sat{Santali} sd{Sindhi} si{Sinhala} sk{Slovak} sl{Slovenian} sq{Albanian} sr{Serbian} su{Sundanese} sv{Swedish} sw{Swahili} ta{Tamil} te{Telugu} th{Thai} tr{Turkish} uk{Ukrainian} ur{Urdu} uz{Uzbek} vi{Vietnamese} yue{Cantonese} zh{Chinese} zu{Zulu} other{?}}'**
  String languageName(String code);

  /// Overflow menu item on the Settings screen that logs the account out.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settingsLogOut;

  /// Settings row and title of the screen listing the accounts on this device.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsTitle;

  /// Settings row that opens Telegram's chat with oneself.
  ///
  /// In en, this message translates to:
  /// **'Saved Messages'**
  String get settingsSavedMessages;

  /// Settings row and screen title: text size of posts and the theme.
  ///
  /// In en, this message translates to:
  /// **'Chat settings'**
  String get chatSettingsTitle;

  /// No description provided for @settingsPrivacyAndSecurity.
  ///
  /// In en, this message translates to:
  /// **'Privacy and security'**
  String get settingsPrivacyAndSecurity;

  /// No description provided for @settingsNotificationsAndSounds.
  ///
  /// In en, this message translates to:
  /// **'Notifications and sounds'**
  String get settingsNotificationsAndSounds;

  /// Settings row and screen title: storage usage, automatic downloads, autoplay.
  ///
  /// In en, this message translates to:
  /// **'Data and storage'**
  String get dataStorageTitle;

  /// Settings row that opens the read-aloud settings.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get settingsReadAloud;

  /// Settings row and screen title for the AI endpoint that AI rules use.
  ///
  /// In en, this message translates to:
  /// **'AI rules'**
  String get aiSettingsTitle;

  /// Settings row and screen title.
  ///
  /// In en, this message translates to:
  /// **'Google Drive sync'**
  String get syncTitle;

  /// Value of the Google Drive sync row: sync is meant to be on, but Google wants the user to sign in again.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get settingsSyncSignedOut;

  /// Section header over the About and licenses rows.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsAboutApp.
  ///
  /// In en, this message translates to:
  /// **'About {appName}'**
  String settingsAboutApp(String appName);

  /// No description provided for @settingsLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get settingsLicenses;

  /// Signature under the Settings list when the version is unknown.
  ///
  /// In en, this message translates to:
  /// **'{appName} for Android'**
  String settingsAppForAndroid(String appName);

  /// Signature under the Settings list, e.g. 'v0.1.0 (1)' as the version.
  ///
  /// In en, this message translates to:
  /// **'{appName} for Android {version}'**
  String settingsAppVersion(String appName, String version);

  /// Text of the About dialog.
  ///
  /// In en, this message translates to:
  /// **'Free software under the GNU GPL v3. Reads your joined channels; nothing leaves the device except Telegram traffic and, if you create AI rules, the posts those rules check, sent to the endpoint you chose.'**
  String get settingsAboutText;

  /// Profile header when the profile could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Account unavailable'**
  String get settingsAccountUnavailable;

  /// Tooltip of the refresh button beside the profile.
  ///
  /// In en, this message translates to:
  /// **'Reload the profile'**
  String get settingsReloadProfile;

  /// Name of an account whose profile is not known yet: its number on this device.
  ///
  /// In en, this message translates to:
  /// **'Account {id}'**
  String accountsNumbered(int id);

  /// Snackbar when a fifth account is added.
  ///
  /// In en, this message translates to:
  /// **'Four accounts is as many as the app holds.'**
  String get accountsLimitReached;

  /// No description provided for @accountsRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String accountsRemoveTitle(String name);

  /// No description provided for @accountsRemoveText.
  ///
  /// In en, this message translates to:
  /// **'Its session, feeds, rules and cached posts are deleted from this device. The Telegram account itself stays as it is.'**
  String get accountsRemoveText;

  /// No description provided for @accountsLastCannotBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'The last account cannot be removed; log out instead.'**
  String get accountsLastCannotBeRemoved;

  /// No description provided for @accountsIntro.
  ///
  /// In en, this message translates to:
  /// **'Each account has its own session, feeds and rules on this device. Switching takes the watcher down and brings it up again on the other account.'**
  String get accountsIntro;

  /// Subtitle of the account the app is on now.
  ///
  /// In en, this message translates to:
  /// **'In use'**
  String get accountsInUse;

  /// Subtitle of an account the app is not on.
  ///
  /// In en, this message translates to:
  /// **'Tap to switch to it'**
  String get accountsTapToSwitch;

  /// No description provided for @accountsRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove from this device'**
  String get accountsRemoveTooltip;

  /// No description provided for @accountsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get accountsAdd;

  /// Subtitle of the disabled Add an account row when four accounts exist.
  ///
  /// In en, this message translates to:
  /// **'Four is as many as the app holds'**
  String get accountsAddLimit;

  /// No description provided for @accountsAddSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Logs in as another account and switches to it'**
  String get accountsAddSubtitle;

  /// No description provided for @aiSettingsTestOk.
  ///
  /// In en, this message translates to:
  /// **'Works: the model answered correctly.'**
  String get aiSettingsTestOk;

  /// No description provided for @aiSettingsTestUnexpected.
  ///
  /// In en, this message translates to:
  /// **'The endpoint answered, but not as expected. Try a stronger model.'**
  String get aiSettingsTestUnexpected;

  /// No description provided for @aiSettingsIntro.
  ///
  /// In en, this message translates to:
  /// **'AI rules describe in your own words what a post should be about. To check them, the app sends the text of candidate posts to the endpoint below. Nothing is sent unless you create such a rule.'**
  String get aiSettingsIntro;

  /// Label of the field holding the base URL of an OpenAI-compatible API.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get aiSettingsEndpoint;

  /// No description provided for @aiSettingsEndpointHelper.
  ///
  /// In en, this message translates to:
  /// **'Any OpenAI-compatible API: OpenAI, OpenRouter, a local Ollama (…/v1), …'**
  String get aiSettingsEndpointHelper;

  /// No description provided for @aiSettingsHttpWarning.
  ///
  /// In en, this message translates to:
  /// **'http:// is not encrypted: posts and the key travel in the clear. Use it only for an endpoint on your own network.'**
  String get aiSettingsHttpWarning;

  /// No description provided for @aiSettingsModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiSettingsModel;

  /// No description provided for @aiSettingsApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get aiSettingsApiKey;

  /// No description provided for @aiSettingsApiKeyHelper.
  ///
  /// In en, this message translates to:
  /// **'Stored in the Android keystore. Leave empty for local endpoints.'**
  String get aiSettingsApiKeyHelper;

  /// No description provided for @aiSettingsHideKey.
  ///
  /// In en, this message translates to:
  /// **'Hide key'**
  String get aiSettingsHideKey;

  /// No description provided for @aiSettingsShowKey.
  ///
  /// In en, this message translates to:
  /// **'Show key'**
  String get aiSettingsShowKey;

  /// No description provided for @aiSettingsSaveAndTest.
  ///
  /// In en, this message translates to:
  /// **'Save and test'**
  String get aiSettingsSaveAndTest;

  /// No description provided for @chatSettingsTextSize.
  ///
  /// In en, this message translates to:
  /// **'Text size in posts'**
  String get chatSettingsTextSize;

  /// Sample line drawn at the chosen text size.
  ///
  /// In en, this message translates to:
  /// **'A post is drawn at this size.'**
  String get chatSettingsTextSizePreview;

  /// No description provided for @chatSettingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get chatSettingsTheme;

  /// Theme that follows the phone's dark theme switch.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get chatSettingsThemeSystem;

  /// No description provided for @chatSettingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get chatSettingsThemeLight;

  /// No description provided for @chatSettingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get chatSettingsThemeDark;

  /// No description provided for @chatSettingsThemeFooter.
  ///
  /// In en, this message translates to:
  /// **'System follows the dark theme switch of the phone.'**
  String get chatSettingsThemeFooter;

  /// No description provided for @dataStorageResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset auto-download settings?'**
  String get dataStorageResetTitle;

  /// Medium, High and Low are the data-usage presets.
  ///
  /// In en, this message translates to:
  /// **'Mobile data goes back to Medium, Wi-Fi to High and roaming to Low.'**
  String get dataStorageResetText;

  /// No description provided for @dataStorageDiskAndNetwork.
  ///
  /// In en, this message translates to:
  /// **'Disk and network usage'**
  String get dataStorageDiskAndNetwork;

  /// Row and screen title: how much Telegram's cache takes on the phone.
  ///
  /// In en, this message translates to:
  /// **'Storage usage'**
  String get dataStorageStorageUsage;

  /// Section header over the three connections.
  ///
  /// In en, this message translates to:
  /// **'Automatic media download'**
  String get dataStorageAutoDownload;

  /// No description provided for @dataStorageReset.
  ///
  /// In en, this message translates to:
  /// **'Reset auto-download settings'**
  String get dataStorageReset;

  /// No description provided for @dataStorageAutoplay.
  ///
  /// In en, this message translates to:
  /// **'Autoplay media'**
  String get dataStorageAutoplay;

  /// No description provided for @dataStorageGifs.
  ///
  /// In en, this message translates to:
  /// **'GIFs'**
  String get dataStorageGifs;

  /// No description provided for @dataStorageVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get dataStorageVideos;

  /// No description provided for @dataStorageAutoplayFooter.
  ///
  /// In en, this message translates to:
  /// **'A video that loads by itself on the connection the phone is on plays muted in its post; a tap opens it with sound.'**
  String get dataStorageAutoplayFooter;

  /// Header over the Low / Medium / High slider.
  ///
  /// In en, this message translates to:
  /// **'Data usage'**
  String get dataStorageDataUsage;

  /// Stop on the data-usage slider for settings that match no preset.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get dataStoragePresetCustom;

  /// No description provided for @dataStorageMediaTypes.
  ///
  /// In en, this message translates to:
  /// **'Types of media'**
  String get dataStorageMediaTypes;

  /// No description provided for @dataStoragePhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get dataStoragePhotos;

  /// Subtitle of the Photos row when photos load by themselves.
  ///
  /// In en, this message translates to:
  /// **'Every photo'**
  String get dataStorageEveryPhoto;

  /// Size limit of videos or files that load by themselves, e.g. 'Up to 10 MB'.
  ///
  /// In en, this message translates to:
  /// **'Up to {size}'**
  String dataStorageUpTo(String size);

  /// No description provided for @dataStorageTypesFooter.
  ///
  /// In en, this message translates to:
  /// **'GIFs and round video messages count as videos, music and voice messages as files. A video within the limit also autoplays, if Autoplay is on for it in Data and storage.'**
  String get dataStorageTypesFooter;

  /// No description provided for @dataStorageMaxVideoSize.
  ///
  /// In en, this message translates to:
  /// **'Maximum video size'**
  String get dataStorageMaxVideoSize;

  /// No description provided for @dataStorageMaxFileSize.
  ///
  /// In en, this message translates to:
  /// **'Maximum file size'**
  String get dataStorageMaxFileSize;

  /// No description provided for @dataStoragePreload.
  ///
  /// In en, this message translates to:
  /// **'Preload larger videos'**
  String get dataStoragePreload;

  /// No description provided for @dataStoragePreloadFooter.
  ///
  /// In en, this message translates to:
  /// **'The first seconds of videos larger than {size} are loaded ahead, so that they start at once.'**
  String dataStoragePreloadFooter(String size);

  /// Switch of a whole connection at the top of its screen.
  ///
  /// In en, this message translates to:
  /// **'Auto-download media'**
  String get dataStorageAutoDownloadMedia;

  /// No description provided for @dataStorageClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear {size} of cache?'**
  String dataStorageClearTitle(String size);

  /// No description provided for @dataStorageClearText.
  ///
  /// In en, this message translates to:
  /// **'Pictures, videos and files load again from Telegram when you open them.'**
  String get dataStorageClearText;

  /// No description provided for @dataStorageStatsFailed.
  ///
  /// In en, this message translates to:
  /// **'Telegram did not say how much it stores.'**
  String get dataStorageStatsFailed;

  /// No description provided for @dataStorageTelegramCache.
  ///
  /// In en, this message translates to:
  /// **'Telegram\'s cache'**
  String get dataStorageTelegramCache;

  /// No description provided for @dataStorageCachedFiles.
  ///
  /// In en, this message translates to:
  /// **'Cached files'**
  String get dataStorageCachedFiles;

  /// How many files Telegram's cache holds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} files}}'**
  String dataStorageFileCount(int count);

  /// No description provided for @dataStorageDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get dataStorageDatabase;

  /// No description provided for @dataStorageClearing.
  ///
  /// In en, this message translates to:
  /// **'Clearing…'**
  String get dataStorageClearing;

  /// No description provided for @dataStorageClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache ({size})'**
  String dataStorageClearCache(String size);

  /// No description provided for @dataStorageClearFooter.
  ///
  /// In en, this message translates to:
  /// **'Pictures, videos and files are loaded again from Telegram when you open them. Your feeds, rules and read positions stay.'**
  String get dataStorageClearFooter;

  /// When the last sync ran today, e.g. 'at 14:32'; follows 'Last synced'.
  ///
  /// In en, this message translates to:
  /// **'at {time}'**
  String syncAtTime(String time);

  /// No description provided for @syncYesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'yesterday at {time}'**
  String syncYesterdayAt(String time);

  /// When the last sync ran, e.g. 'Sep 20 at 14:32'.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String syncDateAtTime(String date, String time);

  /// No description provided for @syncUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available in this build'**
  String get syncUnavailable;

  /// No description provided for @syncProblem.
  ///
  /// In en, this message translates to:
  /// **'Problem: {error}'**
  String syncProblem(String error);

  /// Sync state with the Google account's email.
  ///
  /// In en, this message translates to:
  /// **'On, {account}'**
  String syncOnAccount(String account);

  /// when is e.g. 'at 14:32', 'yesterday at 14:32' or 'Sep 20 at 14:32'.
  ///
  /// In en, this message translates to:
  /// **'On, {account} · last synced {when}'**
  String syncOnAccountLastSynced(String account, String when);

  /// No description provided for @syncIntro.
  ///
  /// In en, this message translates to:
  /// **'Keeps your feeds with their channels, your rules and your settings the same on all your devices through a hidden app file in your own Google Drive. There is no server of ours. Read positions, the AI API key and your Telegram session stay on each device.'**
  String get syncIntro;

  /// No description provided for @syncNoClientIdBuild.
  ///
  /// In en, this message translates to:
  /// **'This build was made without a Google client id, so sync cannot be turned on.'**
  String get syncNoClientIdBuild;

  /// No description provided for @syncSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google and sync'**
  String get syncSignIn;

  /// No description provided for @syncSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncSyncing;

  /// No description provided for @syncNotSyncedYet.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get syncNotSyncedYet;

  /// when is e.g. 'at 14:32', 'yesterday at 14:32' or 'Sep 20 at 14:32'.
  ///
  /// In en, this message translates to:
  /// **'Last synced {when}'**
  String syncLastSynced(String when);

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off on this device'**
  String get syncTurnOff;

  /// No description provided for @syncSignedOutError.
  ///
  /// In en, this message translates to:
  /// **'Signed out of Google. Sign in again to keep syncing.'**
  String get syncSignedOutError;

  /// No description provided for @syncNoClientIdError.
  ///
  /// In en, this message translates to:
  /// **'This build has no Google client id.'**
  String get syncNoClientIdError;

  /// No description provided for @syncSignInCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was cancelled.'**
  String get syncSignInCancelled;

  /// detail is Google's own description of the failure.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in failed: {detail}'**
  String syncSignInFailed(String detail);

  /// No description provided for @syncNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in to Google Drive.'**
  String get syncNotSignedIn;

  /// detail is the technical error text.
  ///
  /// In en, this message translates to:
  /// **'Google Drive cannot be reached: {detail}'**
  String syncDriveUnreachable(String detail);

  /// status is the HTTP status code; detail is empty or ': ' followed by Google's own message.
  ///
  /// In en, this message translates to:
  /// **'Google Drive refused to {request, select, find{look for the sync file} read{read the sync file} create{create the sync file} other{update the sync file}} ({status}){detail}'**
  String syncDriveRefused(String request, String status, String detail);

  /// Position of the picture in front within its album in the full-screen viewer.
  ///
  /// In en, this message translates to:
  /// **'{index} of {total}'**
  String viewerCounter(int index, int total);

  /// Viewer menu item: forwards the post into the Saved Messages chat.
  ///
  /// In en, this message translates to:
  /// **'Save to Saved Messages'**
  String get viewerSaveToSavedMessages;

  /// Viewer menu item: copies the picture or video into the phone's gallery.
  ///
  /// In en, this message translates to:
  /// **'Save to gallery'**
  String get viewerSaveToGallery;

  /// No description provided for @viewerVideoSavedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Video saved to gallery'**
  String get viewerVideoSavedToGallery;

  /// No description provided for @viewerPictureSavedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Picture saved to gallery'**
  String get viewerPictureSavedToGallery;

  /// No description provided for @viewerSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot save: {error}'**
  String viewerSaveFailed(String error);

  /// No description provided for @viewerShareNeedsDownload.
  ///
  /// In en, this message translates to:
  /// **'Download the video first to share it.'**
  String get viewerShareNeedsDownload;

  /// No description provided for @viewerShareFileMissing.
  ///
  /// In en, this message translates to:
  /// **'Cannot share: the file did not arrive'**
  String get viewerShareFileMissing;

  /// No description provided for @viewerShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot share: {error}'**
  String viewerShareFailed(String error);

  /// Tooltip of the viewer button that shrinks the video into a floating player.
  ///
  /// In en, this message translates to:
  /// **'Picture-in-picture'**
  String get pipOpen;

  /// Accessibility label of the small floating video player.
  ///
  /// In en, this message translates to:
  /// **'Floating video player'**
  String get pipFloatingPlayer;

  /// Tooltip of the floating player's button that reopens the full-screen viewer.
  ///
  /// In en, this message translates to:
  /// **'Back to full screen'**
  String get pipBackToFullScreen;

  /// Tooltip of a play button.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playerPlay;

  /// Tooltip of a pause button.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get playerPause;

  /// Tooltip of the playback speed menu.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get playerSpeed;

  /// Tooltip of the audio bar's close button, which stops playback.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get audioStop;

  /// Tooltip of the mute button while the video is muted.
  ///
  /// In en, this message translates to:
  /// **'Sound on'**
  String get videoSoundOn;

  /// Tooltip of the mute button while the video plays with sound.
  ///
  /// In en, this message translates to:
  /// **'Sound off'**
  String get videoSoundOff;

  /// Hint shown when a double tap seeks the video by this many seconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String videoSeekSeconds(int seconds);

  /// No description provided for @videoCannotPlay.
  ///
  /// In en, this message translates to:
  /// **'Cannot play this video: {error}'**
  String videoCannotPlay(String error);

  /// No description provided for @videoDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get videoDownload;

  /// Viewer menu item; size is the file size, e.g. 12 MB.
  ///
  /// In en, this message translates to:
  /// **'Download ({size})'**
  String videoDownloadWithSize(String size);

  /// No description provided for @videoCancelDownload.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get videoCancelDownload;

  /// Label of the download pill on a video after the download failed.
  ///
  /// In en, this message translates to:
  /// **'Failed, try again'**
  String get videoDownloadFailed;

  /// Row in Data and storage that opens the automatic download settings for mobile data.
  ///
  /// In en, this message translates to:
  /// **'When using mobile data'**
  String get autoDownloadRowMobile;

  /// No description provided for @autoDownloadRowWifi.
  ///
  /// In en, this message translates to:
  /// **'When connected on Wi-Fi'**
  String get autoDownloadRowWifi;

  /// No description provided for @autoDownloadRowRoaming.
  ///
  /// In en, this message translates to:
  /// **'When roaming'**
  String get autoDownloadRowRoaming;

  /// Title of the automatic download screen for mobile data.
  ///
  /// In en, this message translates to:
  /// **'Using mobile data'**
  String get autoDownloadTitleMobile;

  /// No description provided for @autoDownloadTitleWifi.
  ///
  /// In en, this message translates to:
  /// **'Using Wi-Fi'**
  String get autoDownloadTitleWifi;

  /// No description provided for @autoDownloadTitleRoaming.
  ///
  /// In en, this message translates to:
  /// **'Roaming'**
  String get autoDownloadTitleRoaming;

  /// Data usage preset of automatic downloads.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get autoDownloadPresetLow;

  /// Data usage preset of automatic downloads.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get autoDownloadPresetMedium;

  /// Data usage preset of automatic downloads.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get autoDownloadPresetHigh;

  /// Line under a connection's row when nothing downloads automatically on it.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get autoDownloadSummaryDisabled;

  /// Line under a connection's row when it is on but no kind of media is chosen.
  ///
  /// In en, this message translates to:
  /// **'Nothing'**
  String get autoDownloadSummaryNothing;

  /// Part of the line under a connection's row, e.g. Photos, Videos (10 MB), Files (1 MB).
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get autoDownloadSummaryPhotos;

  /// Part of the line under a connection's row; limit is the size limit, e.g. 10 MB.
  ///
  /// In en, this message translates to:
  /// **'Videos ({limit})'**
  String autoDownloadSummaryVideos(String limit);

  /// Part of the line under a connection's row; limit is the size limit, e.g. 1 MB.
  ///
  /// In en, this message translates to:
  /// **'Files ({limit})'**
  String autoDownloadSummaryFiles(String limit);

  /// No description provided for @appStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start the core: {error}'**
  String appStartFailed(String error);

  /// Settings row and screen that pick the interface language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// Language choice that follows the phone's language.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageFooter.
  ///
  /// In en, this message translates to:
  /// **'System picks the phone\'s language when the app is translated into it, and English otherwise.'**
  String get languageFooter;

  /// Spoken before a post that is read aloud.
  ///
  /// In en, this message translates to:
  /// **'New post in {channel}.'**
  String ttsIntro(String channel);

  /// Spoken in place of a web address when a post is read aloud.
  ///
  /// In en, this message translates to:
  /// **'link'**
  String get ttsLink;

  /// Spoken after a post cut short when it is read aloud.
  ///
  /// In en, this message translates to:
  /// **'… and more'**
  String get ttsMore;

  /// Android notification channel of the permanent notification.
  ///
  /// In en, this message translates to:
  /// **'Watching channels'**
  String get serviceChannelName;

  /// No description provided for @serviceChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Keeps the Telegram connection open for keyword rules'**
  String get serviceChannelDescription;

  /// No description provided for @serviceStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get serviceStarting;

  /// Button on the permanent notification that pauses every rule.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get servicePause;

  /// No description provided for @serviceResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get serviceResume;

  /// No description provided for @servicePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused: rules are not evaluated'**
  String get servicePaused;

  /// No description provided for @serviceWatching.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Watching 1 channel} other{Watching {count} channels}}'**
  String serviceWatching(int count);

  /// Title of a rule notification whose channel has no name.
  ///
  /// In en, this message translates to:
  /// **'New post'**
  String get notifyNewPost;

  /// Group summary of a channel's rule notifications.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new post} other{{count} new posts}}'**
  String notifyNewPosts(int count);

  /// Notification action that reads the post aloud.
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get notifyListen;

  /// Notification action that stops reading the post aloud.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get notifyStop;

  /// Android notification channel name.
  ///
  /// In en, this message translates to:
  /// **'Silent posts'**
  String get notifyChannelSilent;

  /// No description provided for @notifyChannelSilentDescription.
  ///
  /// In en, this message translates to:
  /// **'Rules with silent priority: no sound, no heads-up'**
  String get notifyChannelSilentDescription;

  /// Android notification channel name.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get notifyChannelNormal;

  /// No description provided for @notifyChannelNormalDescription.
  ///
  /// In en, this message translates to:
  /// **'Rules with normal priority'**
  String get notifyChannelNormalDescription;

  /// No description provided for @notifyChannelNormalInApp.
  ///
  /// In en, this message translates to:
  /// **'Posts while the app is open'**
  String get notifyChannelNormalInApp;

  /// No description provided for @notifyChannelNormalInAppDescription.
  ///
  /// In en, this message translates to:
  /// **'Rules with normal priority while the app is open, without a pop-up'**
  String get notifyChannelNormalInAppDescription;

  /// No description provided for @notifyChannelUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent posts'**
  String get notifyChannelUrgent;

  /// No description provided for @notifyChannelUrgentDescription.
  ///
  /// In en, this message translates to:
  /// **'Rules with urgent priority'**
  String get notifyChannelUrgentDescription;

  /// No description provided for @notifyChannelUrgentInApp.
  ///
  /// In en, this message translates to:
  /// **'Urgent posts while the app is open'**
  String get notifyChannelUrgentInApp;

  /// No description provided for @notifyChannelUrgentInAppDescription.
  ///
  /// In en, this message translates to:
  /// **'Rules with urgent priority while the app is open, without a pop-up'**
  String get notifyChannelUrgentInAppDescription;

  /// A channel description, then that its notifications sound in Do Not Disturb.
  ///
  /// In en, this message translates to:
  /// **'{description}; bypasses Do Not Disturb'**
  String notifyChannelBypassesDnd(String description);

  /// No description provided for @mediaPoll.
  ///
  /// In en, this message translates to:
  /// **'Poll'**
  String get mediaPoll;

  /// No description provided for @mediaLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get mediaLocation;

  /// No description provided for @mediaVenue.
  ///
  /// In en, this message translates to:
  /// **'Venue'**
  String get mediaVenue;

  /// No description provided for @mediaContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get mediaContact;

  /// No description provided for @mediaDice.
  ///
  /// In en, this message translates to:
  /// **'Dice'**
  String get mediaDice;

  /// No description provided for @mediaGame.
  ///
  /// In en, this message translates to:
  /// **'Game'**
  String get mediaGame;

  /// No description provided for @mediaInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get mediaInvoice;

  /// No description provided for @mediaGiveaway.
  ///
  /// In en, this message translates to:
  /// **'Giveaway'**
  String get mediaGiveaway;

  /// No description provided for @mediaStory.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get mediaStory;

  /// No description provided for @mediaChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get mediaChecklist;

  /// No description provided for @mediaAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get mediaAlbum;

  /// No description provided for @mediaPaidMedia.
  ///
  /// In en, this message translates to:
  /// **'Paid media'**
  String get mediaPaidMedia;

  /// No description provided for @mediaUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported post'**
  String get mediaUnsupported;

  /// No description provided for @servicePinned.
  ///
  /// In en, this message translates to:
  /// **'{channel} pinned a post'**
  String servicePinned(String channel);

  /// No description provided for @servicePinnedOpen.
  ///
  /// In en, this message translates to:
  /// **'{channel} pinned a post. Open the pinned post'**
  String servicePinnedOpen(String channel);

  /// No description provided for @serviceTitleChanged.
  ///
  /// In en, this message translates to:
  /// **'Channel name changed to {title}'**
  String serviceTitleChanged(String title);

  /// No description provided for @servicePhotoChanged.
  ///
  /// In en, this message translates to:
  /// **'Channel photo updated'**
  String get servicePhotoChanged;

  /// No description provided for @servicePhotoRemoved.
  ///
  /// In en, this message translates to:
  /// **'Channel photo removed'**
  String get servicePhotoRemoved;

  /// No description provided for @serviceChannelCreated.
  ///
  /// In en, this message translates to:
  /// **'Channel created'**
  String get serviceChannelCreated;

  /// No description provided for @serviceLiveStarted.
  ///
  /// In en, this message translates to:
  /// **'Live stream started'**
  String get serviceLiveStarted;

  /// No description provided for @serviceLiveEnded.
  ///
  /// In en, this message translates to:
  /// **'Live stream ended ({length})'**
  String serviceLiveEnded(String length);

  /// No description provided for @serviceLiveScheduled.
  ///
  /// In en, this message translates to:
  /// **'Live stream scheduled on {date}'**
  String serviceLiveScheduled(String date);

  /// No description provided for @serviceOther.
  ///
  /// In en, this message translates to:
  /// **'Service message'**
  String get serviceOther;

  /// No description provided for @serviceOfChannel.
  ///
  /// In en, this message translates to:
  /// **'{channel}: {words}'**
  String serviceOfChannel(String channel, String words);

  /// No description provided for @problemSyncNewerVersion.
  ///
  /// In en, this message translates to:
  /// **'The sync file was written by a newer version of the app. Update this device.'**
  String get problemSyncNewerVersion;

  /// No description provided for @problemSyncUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The sync file cannot be read: {error}'**
  String problemSyncUnreadable(String error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
