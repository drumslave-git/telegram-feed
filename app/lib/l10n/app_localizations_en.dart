// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonOk => 'OK';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonDone => 'Done';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonOn => 'On';

  @override
  String get commonOff => 'Off';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonShare => 'Share';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonMore => 'More';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonLater => 'Later';

  @override
  String get commonNotNow => 'Not now';

  @override
  String get commonAllow => 'Allow';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonReset => 'Reset';

  @override
  String get commonSelect => 'Select';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonRules => 'Rules';

  @override
  String get commonComments => 'Comments';

  @override
  String get commonCopyLink => 'Copy link';

  @override
  String get commonOpenInTelegram => 'Open in Telegram';

  @override
  String get commonOpenSettings => 'Open settings';

  @override
  String get commonDiscard => 'Discard';

  @override
  String get commonKeepEditing => 'Keep editing';

  @override
  String get commonMarkAsRead => 'Mark as read';

  @override
  String get mediaPhoto => 'Photo';

  @override
  String get mediaVideo => 'Video';

  @override
  String get mediaGif => 'GIF';

  @override
  String get mediaVideoMessage => 'Video message';

  @override
  String get mediaVoiceMessage => 'Voice message';

  @override
  String get mediaAudio => 'Audio';

  @override
  String get mediaSticker => 'Sticker';

  @override
  String get mediaFile => 'File';

  @override
  String get mediaPost => 'Post';

  @override
  String get tabMedia => 'Media';

  @override
  String get tabFiles => 'Files';

  @override
  String get tabLinks => 'Links';

  @override
  String get tabMusic => 'Music';

  @override
  String get tabVoice => 'Voice';

  @override
  String get tabGifs => 'GIFs';

  @override
  String get sharedMediaPhotos => 'Photos';

  @override
  String get sharedMediaVideos => 'Videos';

  @override
  String get sharedMediaShowInChat => 'Show in chat';

  @override
  String get sharedMediaScroller => 'Scroll by date';

  @override
  String get sharedMediaFilter => 'Photos and videos';

  @override
  String get sharedMediaSearchHint => 'Search';

  @override
  String sharedMediaNothingFound(String query) {
    return 'Nothing found for \"$query\".';
  }

  @override
  String mediaStickerWithEmoji(String emoji) {
    return '$emoji Sticker';
  }

  @override
  String get timelineSpoiler => 'spoiler';

  @override
  String get timelineCodeCopied => 'Code copied';

  @override
  String get linkOpenTitle => 'Open Link';

  @override
  String linkOpenQuestion(String url) {
    return 'Do you want to open $url?';
  }

  @override
  String get phoneCall => 'Call';

  @override
  String get phoneCopy => 'Copy number';

  @override
  String get phoneCopied => 'Phone number copied';

  @override
  String get timelineCopyCode => 'Copy code';

  @override
  String timelineCannotPlay(String error) {
    return 'Cannot play: $error';
  }

  @override
  String get timelinePlay => 'Play';

  @override
  String get timelinePause => 'Pause';

  @override
  String timelineSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get timelineCopyText => 'Copy text';

  @override
  String get timelineSaveToSavedMessages => 'Save to Saved Messages';

  @override
  String timelinePostsCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count posts copied',
      one: '$count post copied',
    );
    return '$_temp0';
  }

  @override
  String timelinePostsSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count posts saved to Saved Messages',
      one: '$count post saved to Saved Messages',
    );
    return '$_temp0';
  }

  @override
  String get timelineSavePostsFailed => 'Could not save the posts.';

  @override
  String get timelineDeletePostTitle => 'Delete post';

  @override
  String get timelineDeletePostMessage =>
      'Are you sure you want to delete this post?';

  @override
  String timelineDeletePostsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count posts',
      one: 'Delete $count post',
    );
    return '$_temp0';
  }

  @override
  String get timelineDeletePostsMessage =>
      'Are you sure you want to delete these posts?';

  @override
  String get timelineDeletePostsFailed => 'Could not delete the posts.';

  @override
  String get timelineJumpToDate => 'Jump to date';

  @override
  String timelineSubscribers(int count, String shown) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shown subscribers',
    );
    return '$_temp0';
  }

  @override
  String get timelineEditFeed => 'Edit feed';

  @override
  String get timelineJumpToDayFailed => 'Could not jump to that day.';

  @override
  String timelineNothingFromDay(String day) {
    return 'Nothing here from $day or earlier.';
  }

  @override
  String get timelineNoAppForPost => 'No app can open this post.';

  @override
  String get timelineForwardHidden =>
      'That post came from an account that hides itself.';

  @override
  String timelineForwardNotFollowed(String title) {
    return '$title is not a channel you follow.';
  }

  @override
  String get timelineReplyNotFollowed =>
      'That post is in a channel you do not follow.';

  @override
  String timelineNoAppForLink(String url) {
    return 'No app can open $url';
  }

  @override
  String get timelineNoLinkToShare => 'This post has no link to share.';

  @override
  String get timelineTextCopied => 'Text copied';

  @override
  String get timelineNoLinkToCopy => 'This post has no link to copy.';

  @override
  String timelineLinkCopied(String link) {
    return 'Link copied: $link';
  }

  @override
  String get timelineSavedToSavedMessages => 'Saved to Saved Messages';

  @override
  String get timelineSavePostFailed => 'Could not save the post.';

  @override
  String get timelineReactionFailed => 'Could not send the reaction.';

  @override
  String timelineNewPosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new posts',
      one: '$count new post',
    );
    return '$_temp0';
  }

  @override
  String timelineUnreadPostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread posts',
      one: '$count unread post',
    );
    return '$_temp0';
  }

  @override
  String get timelineNewestPosts => 'Newest posts';

  @override
  String get timelineNoChannelsTitle => 'This feed has no channels yet';

  @override
  String get timelineNoChannelsMessage =>
      'Add the channels it should collect; their posts then read as one timeline, oldest first.';

  @override
  String get timelineAddChannels => 'Add channels';

  @override
  String get timelineLoadFailed => 'Could not load the posts.';

  @override
  String get timelineNoPosts => 'No posts.';

  @override
  String timelineNoPostsPassFilter(String filter) {
    return 'No posts pass this feed\'s filter ($filter).';
  }

  @override
  String get timelineBeginningOfFeed => 'Beginning of the feed';

  @override
  String get timelineOlderFailed => 'Could not load older posts.';

  @override
  String get timelinePinnedPost => 'Pinned post';

  @override
  String get timelineHidePinned => 'Hide';

  @override
  String get timelinePreviousPinned => 'Previous post';

  @override
  String timelinePinnedPostNumber(int number) {
    return 'Pinned post #$number';
  }

  @override
  String get timelinePinnedList => 'Pinned posts';

  @override
  String pinnedPostsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pinned posts',
      one: 'Pinned post',
    );
    return '$_temp0';
  }

  @override
  String get pinnedPostsOpen => 'Go to the post';

  @override
  String get pinnedPostsHide => 'Hide pinned posts';

  @override
  String get pinnedPostsHidden =>
      'Pinned posts hidden. They will be shown again when a new post is pinned.';

  @override
  String get timelineUnreadDivider => 'Unread posts';

  @override
  String get searchFilterEverything => 'Everything';

  @override
  String get searchRecent => 'Recent searches';

  @override
  String get searchRemoveRecent => 'Remove from Recent';

  @override
  String get searchClearHistoryTitle => 'Clear search history';

  @override
  String get searchClearHistoryBody =>
      'Do you want to clear your search history?';

  @override
  String get searchClearAll => 'Clear All';

  @override
  String get searchFailed => 'Could not search.';

  @override
  String get searchTypeToSearch => 'Type to search the posts.';

  @override
  String get searchNothingFoundPlain => 'Nothing found.';

  @override
  String searchNothingFound(String query) {
    return 'Nothing found for \"$query\".';
  }

  @override
  String searchPostsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count posts found',
      one: '$count post found',
    );
    return '$_temp0';
  }

  @override
  String get searchMoreFailed => 'Could not load more results.';

  @override
  String get searchOlderMatch => 'Older match';

  @override
  String get searchNewerMatch => 'Newer match';

  @override
  String get searchNoMatches => 'No matches';

  @override
  String get searchShowAsList => 'Show as list';

  @override
  String get searchShowAsChat => 'Show as chat';

  @override
  String searchMatchOf(int current, int total) {
    return '$current of $total';
  }

  @override
  String get searchPostsHint => 'Search posts';

  @override
  String get threadSearchFailed => 'Could not search the comments.';

  @override
  String get threadPostFailed => 'Could not post the comment.';

  @override
  String get threadSearchComments => 'Search comments';

  @override
  String threadTitleWithChannel(String channel) {
    return 'Comments · $channel';
  }

  @override
  String get threadNoDiscussion =>
      'This channel has no discussion group, so posts cannot be commented on.';

  @override
  String get threadLoadFailed => 'Could not load the comments.';

  @override
  String get threadSearching => 'Searching…';

  @override
  String get threadNoComments => 'No comments yet.';

  @override
  String get threadWriteComment => 'Write a comment';

  @override
  String get threadSend => 'Send';

  @override
  String threadCommentsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comments found',
      one: '$count comment found',
    );
    return '$_temp0';
  }

  @override
  String get threadReply => 'Reply';

  @override
  String get threadCopy => 'Copy';

  @override
  String get threadEdit => 'Edit';

  @override
  String get threadEditMessage => 'Edit Message';

  @override
  String threadReplyTo(String name) {
    return 'Reply to $name';
  }

  @override
  String get threadYou => 'yourself';

  @override
  String get threadDeleteTitle => 'Delete message';

  @override
  String get threadDeleteBody =>
      'Are you sure you want to delete this message for everyone?';

  @override
  String get threadEditFailed => 'Could not change the comment.';

  @override
  String get threadDeleteFailed => 'Could not delete the comment.';

  @override
  String get threadJoinNeeded =>
      'Only members of the discussion group can comment here. Join the group in Telegram to write.';

  @override
  String get threadRestricted =>
      'The admins of this group have restricted your ability to send messages.';

  @override
  String threadSlowMode(String time) {
    return 'Slow Mode is active. You can send your next message in $time.';
  }

  @override
  String get threadSending => 'Sending';

  @override
  String get threadNotSent => 'Not sent';

  @override
  String get threadDeletedMessage => 'Deleted message';

  @override
  String get threadLoadOlder => 'Load older comments';

  @override
  String get threadUnreadDivider => 'Unread comments';

  @override
  String get threadDiscussionStarted => 'Discussion started';

  @override
  String get postDayToday => 'Today';

  @override
  String get postDayYesterday => 'Yesterday';

  @override
  String get listDatePattern => 'MMM dd';

  @override
  String get postDayPattern => 'MMMM d';

  @override
  String get postDayYearPattern => 'MMMM d, y';

  @override
  String get linkViewChannel => 'View channel';

  @override
  String get linkViewGroup => 'View group';

  @override
  String get linkViewMessage => 'View message';

  @override
  String get linkSendMessage => 'Send message';

  @override
  String get linkOpenBot => 'Open bot';

  @override
  String get linkViewBackground => 'View wallpaper';

  @override
  String get linkViewTheme => 'View theme';

  @override
  String get linkViewStickers => 'View stickers';

  @override
  String get linkJoinVideoChat => 'Join as listener';

  @override
  String get linkViewStory => 'View story';

  @override
  String get linkBoost => 'Boost';

  @override
  String get linkViewChatFolder => 'View chat list';

  @override
  String get linkOpenApp => 'Launch';

  @override
  String get mediaLocationOpens => 'Location, opens in a map';

  @override
  String get mediaVenueOpens => 'Venue, opens in a map';

  @override
  String get mediaNoMapApp => 'No app on this phone opens a map.';

  @override
  String mediaChecklistDone(int done, int total) {
    return '$done of $total completed';
  }

  @override
  String get postNoAppForFile => 'No app on this phone opens this file.';

  @override
  String get postSaveToDownloads => 'Save to downloads';

  @override
  String get postSaveToMusic => 'Save to music';

  @override
  String postSavedToGallery(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved to gallery.',
      one: 'Saved to gallery.',
    );
    return '$_temp0';
  }

  @override
  String postSavedToDownloads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files saved to Downloads.',
      one: 'File saved to Downloads.',
    );
    return '$_temp0';
  }

  @override
  String postSavedToMusic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count audio files saved to Music.',
      one: 'Audio saved to Music.',
    );
    return '$_temp0';
  }

  @override
  String get postReport => 'Report';

  @override
  String get postReportHint => 'Additional details...';

  @override
  String get postReportSend => 'Send report';

  @override
  String get postReportSent =>
      'Thank you! Your report will be reviewed by Telegram\'s team.';

  @override
  String get postReportFailed => 'Could not send the report.';

  @override
  String get postPinned => 'Pinned';

  @override
  String get mediaCancelDownload => 'Cancel the download';

  @override
  String mediaLoadedOf(String loaded, String total) {
    return '$loaded / $total';
  }

  @override
  String get mediaCoverSpoiler => 'Spoiler. Tap to show';

  @override
  String get mediaCoverSensitive => '18+ content. Tap to show';

  @override
  String get mediaSensitiveLabel => '18+';

  @override
  String get mediaSensitiveQuestion =>
      'This media may contain sensitive content suitable only for adults. Do you still want to view it?';

  @override
  String get mediaSensitiveView => 'View anyway';

  @override
  String get quoteExpand => 'Show the whole quote';

  @override
  String get quoteCollapse => 'Show less of the quote';

  @override
  String postDayJumpToStart(String day) {
    return '$day. Go to the start of the day';
  }

  @override
  String get calendarTitle => 'Calendar';

  @override
  String calendarDayWithMedia(String day) {
    return '$day, with a picture';
  }

  @override
  String postDayJumpToDate(String day) {
    return '$day. Jump to a date';
  }

  @override
  String get postCopyText => 'Copy text';

  @override
  String get postProtected =>
      'Copying and forwarding is not allowed in this channel.';

  @override
  String get postSaveToSavedMessages => 'Save to Saved Messages';

  @override
  String get postMinimize => 'Minimize';

  @override
  String get postAutoplaySettings => 'Autoplay and download settings';

  @override
  String postMinimizedSemantics(String channel, String words, String time) {
    return 'Minimized post of $channel: $words, $time';
  }

  @override
  String postChannelInfoOf(String name) {
    return 'Channel info of $name';
  }

  @override
  String get postHiddenAccount => 'a hidden account';

  @override
  String postForwardedFrom(String name) {
    return 'Forwarded from $name';
  }

  @override
  String postForwardedFromOpen(String name) {
    return 'Forwarded from $name. Open the original';
  }

  @override
  String postInReplyTo(String name) {
    return 'In reply to $name';
  }

  @override
  String postInReplyToOpen(String name) {
    return 'In reply to $name. Go to that post';
  }

  @override
  String get postEdited => 'edited';

  @override
  String postCommentCount(int count, String shown) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shown comments',
      one: '$shown comment',
    );
    return '$_temp0';
  }

  @override
  String get postCommentsUnread => 'New comments';

  @override
  String get postLeaveComment => 'Leave a comment';

  @override
  String get postReactionsLoadFailed => 'Reactions could not be loaded.';

  @override
  String get postReactionsNotAllowed =>
      'This channel does not allow reactions.';

  @override
  String get postDownloadFailed => 'Download failed. Tap to retry.';

  @override
  String get postDownloading => 'Downloading…';

  @override
  String get postTapToDownload => 'Tap to download';

  @override
  String postFileTapToDownload(String size) {
    return '$size · tap to download';
  }

  @override
  String get postOnThisDevice => 'On this device';

  @override
  String get postOpenWith => 'Open with…';

  @override
  String get postPhotoOpensFullScreen => 'Photo, opens full screen';

  @override
  String get postPlay => 'Play';

  @override
  String get sharedMediaNoChannels => 'No channels yet.';

  @override
  String get sharedMediaLoadFailed => 'Could not load this media.';

  @override
  String get sharedMediaEmpty => 'Nothing here yet.';

  @override
  String sharedMediaGifTile(String day) {
    return 'GIF, $day';
  }

  @override
  String sharedMediaVideoTile(String duration, String day) {
    return 'Video $duration, $day';
  }

  @override
  String sharedMediaPhotoTile(String day) {
    return 'Photo, $day';
  }

  @override
  String sharedMediaPostTile(String day) {
    return 'Post of $day';
  }

  @override
  String sharedMediaNoAppCanOpen(String link) {
    return 'No app can open $link';
  }

  @override
  String get channelInfoTitle => 'Channel info';

  @override
  String get channelInfoQrCode => 'QR code';

  @override
  String get channelInfoLinkCopied => 'Link copied';

  @override
  String channelInfoPhotoOf(int current, int total) {
    return 'Photo $current of $total';
  }

  @override
  String get channelInfoCloseGallery => 'Show the small photo';

  @override
  String channelInfoSubscribers(int count, String shown) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shown subscribers',
      one: '$shown subscriber',
    );
    return '$_temp0';
  }

  @override
  String get channelInfoChannel => 'Channel';

  @override
  String get channelInfoLoadFailed => 'Could not load the channel details.';

  @override
  String get channelInfoSimilarChannels => 'Similar channels';

  @override
  String get homeTabFeeds => 'Feeds';

  @override
  String get homeTabAllChannels => 'All channels';

  @override
  String get homeSearchPosts => 'Search posts';

  @override
  String get homeSearchHint => 'Search all channels';

  @override
  String get homeSearchChannelNotInList => 'That channel is not in your list.';

  @override
  String get homeMarkAllAsRead => 'Mark all as read';

  @override
  String get homeNothingToMarkRead => 'Nothing to mark read.';

  @override
  String homeChannelsMarkedRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels marked read.',
      one: '$count channel marked read.',
    );
    return '$_temp0';
  }

  @override
  String get homeFolderCreateFeed => 'Create feed from folder';

  @override
  String get homeRulesHintTitle => 'Nothing notifies you yet';

  @override
  String get homeRulesHintDismiss => 'Dismiss';

  @override
  String get homeRulesHintBody =>
      'This app never repeats Telegram\'s own notifications. A rule of a feed watches its channels for the words you pick and notifies you, and can read the post aloud.';

  @override
  String get homeRulesHintAction => 'Set up rules';

  @override
  String homeUnreadBadge(int count) {
    return '$count unread';
  }

  @override
  String get homeWaitingForNetwork => 'Waiting for network…';

  @override
  String get homeConnecting => 'Connecting…';

  @override
  String get homeConnectingToProxy => 'Connecting to proxy…';

  @override
  String get homeUpdating => 'Updating…';

  @override
  String get feedsNewFeed => 'New feed';

  @override
  String get feedsRenameFeed => 'Rename feed';

  @override
  String get feedsNameLabel => 'Name';

  @override
  String get feedsCreate => 'Create';

  @override
  String get feedsEmptyFeed => 'Empty feed';

  @override
  String get feedsEmptyFeedSubtitle => 'Name it, then pick its channels';

  @override
  String get feedsFromFolder => 'From a folder';

  @override
  String feedsChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels',
      one: '$count channel',
    );
    return '$_temp0';
  }

  @override
  String feedsChannelsWithNews(int fresh, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels',
      one: '$count channel',
    );
    return '$fresh of $_temp0 with news';
  }

  @override
  String feedsCreatedFromFolder(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels',
      one: '$count channel',
    );
    return 'Feed \"$name\" created with $_temp0.';
  }

  @override
  String feedsNothingToMarkRead(String name) {
    return 'Nothing to mark read in \"$name\".';
  }

  @override
  String feedsMarkedRead(String name) {
    return '\"$name\" marked read.';
  }

  @override
  String feedsDeleteTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String feedsDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The feed, its $count rules and its kept positions are removed.',
      one: 'The feed, its rule and its kept positions are removed.',
      zero: 'The feed and its kept positions are removed.',
    );
    return '$_temp0 Channels stay joined in Telegram.';
  }

  @override
  String get feedsCountersRefreshFailed => 'Could not refresh the counters.';

  @override
  String get feedsEmptyTitle => 'No feeds yet';

  @override
  String get feedsEmptyMessage =>
      'A feed is a set of channels read as one timeline. Rules of the feed then notify you about the posts you care about; without them this app stays quiet.';

  @override
  String get feedsEmptyAction => 'Create a feed';

  @override
  String get feedsEmptySecondary =>
      'A feed can also start from one of your Telegram folders, or from the \"Add to a feed\" menu of any channel.';

  @override
  String get feedsEditChannels => 'Edit channels';

  @override
  String get channelsInfo => 'Channel info';

  @override
  String get channelsAddToFeed => 'Add to a feed';

  @override
  String get channelsAlreadyInFeed => 'Already in this feed';

  @override
  String channelsAddedToFeed(String channel, String feed) {
    return '$channel added to \"$feed\".';
  }

  @override
  String channelsAlbumPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '$count photo',
    );
    return '$_temp0';
  }

  @override
  String channelsAlbumVideos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos',
      one: '$count video',
    );
    return '$_temp0';
  }

  @override
  String channelsAlbumFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '$count file',
    );
    return '$_temp0';
  }

  @override
  String channelsAlbumMusic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count music files',
      one: '$count music file',
    );
    return '$_temp0';
  }

  @override
  String channelsAlbumMedia(int count) {
    return '$count media';
  }

  @override
  String get channelsVerified => 'Verified';

  @override
  String get channelsMarkAsUnread => 'Mark as unread';

  @override
  String get channelsMarkedUnread => 'Marked as unread';

  @override
  String get channelsMarkUnreadFailed =>
      'Could not mark the channel as unread.';

  @override
  String get channelsArchive => 'Archive';

  @override
  String get channelsArchiveSubtitle => 'Channels you archived in Telegram';

  @override
  String get channelsArchiveEmpty => 'No archived channels.';

  @override
  String get channelsArchiveOpenFailed => 'Could not open the archive.';

  @override
  String get channelsEmptyAll =>
      'No channels yet. Join channels in Telegram and they show up here.';

  @override
  String get channelsEmptyFolder => 'No channels in this folder.';

  @override
  String get channelsEmpty => 'No channels here.';

  @override
  String get channelsLoadFailed => 'Could not load the channels.';

  @override
  String get channelsRefreshFailed => 'Could not refresh the channels.';

  @override
  String channelsNoMatch(String query) {
    return 'No channel matches \"$query\".';
  }

  @override
  String get channelsSearchHint => 'Search channels';

  @override
  String get logOutTitle => 'Log out?';

  @override
  String get logOutMessage =>
      'Your feeds, rules, settings and the AI key on this device are deleted, and Google Drive sync is turned off. A copy stays in your Drive if sync was on.';

  @override
  String get logOutAction => 'Log out';

  @override
  String get bannerStop => 'Stop';

  @override
  String get bannerStopAndClearQueue => 'Stop and clear queue';

  @override
  String get bannerPaused =>
      'Notifications are paused. Rules notify about nothing and read nothing aloud.';

  @override
  String get bannerResume => 'Resume';

  @override
  String get bannerReadingAloud => 'Reading aloud';

  @override
  String bannerReadingAloudChannel(String channel) {
    return 'Reading aloud: $channel';
  }

  @override
  String bannerReadingQueue(String line, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more posts wait.',
      one: '$count more post waits.',
    );
    return '$line. $_temp0';
  }

  @override
  String get bannerPauseNotifications => 'Pause notifications';

  @override
  String get bannerResumeNotifications => 'Resume notifications';

  @override
  String get errorRateLimited =>
      'Telegram is rate-limiting this account. Wait a minute and try again.';

  @override
  String get errorPhoneNumberInvalid => 'That phone number is not valid.';

  @override
  String get errorPhoneNumberBanned => 'Telegram has banned that phone number.';

  @override
  String get errorPhoneNumberFlood =>
      'That number has asked for too many codes today. Try again tomorrow.';

  @override
  String get errorPhoneNumberOccupied =>
      'That number already belongs to another account.';

  @override
  String get errorCodeInvalid => 'Wrong code.';

  @override
  String get errorCodeExpired => 'The code expired. Ask for a new one.';

  @override
  String get errorPasswordInvalid => 'Wrong password.';

  @override
  String get errorPasswordRecoveryUnavailable =>
      'This account has no recovery email, so the password cannot be reset here.';

  @override
  String get errorApiIdInvalid =>
      'This build has no valid Telegram api_id/api_hash (see README).';

  @override
  String get errorChannelUnknown =>
      'Telegram does not know that channel any more.';

  @override
  String get errorChannelPrivate =>
      'That channel is private now, or the account has left it.';

  @override
  String get errorPostGone => 'That post no longer exists.';

  @override
  String get errorWriteForbidden =>
      'This channel does not let the account write here.';

  @override
  String get errorBannedInChannel => 'The account is banned in that channel.';

  @override
  String get errorReactionInvalid =>
      'This channel does not allow that reaction.';

  @override
  String get errorConnectionClosed =>
      'The connection to Telegram closed. Try again.';

  @override
  String get feedEditorFallbackTitle => 'Feed';

  @override
  String get feedEditorRenameTitle => 'Rename feed';

  @override
  String get feedEditorNameLabel => 'Name';

  @override
  String get feedEditorTabChannels => 'Channels';

  @override
  String get feedEditorTabSharedMedia => 'Shared media';

  @override
  String get feedEditorAddChannel => 'Add channel';

  @override
  String get feedEditorNewRule => 'New rule';

  @override
  String get feedEditorRemoveChannel => 'Remove';

  @override
  String feedEditorRemoveChannelTitle(String channel) {
    return 'Remove $channel?';
  }

  @override
  String feedEditorQuotedRuleName(String name) {
    return '\"$name\"';
  }

  @override
  String feedEditorRemoveChannelOneRule(String names) {
    return 'The rule $names watches only this channel and is deleted with it.';
  }

  @override
  String feedEditorRemoveChannelRules(String names) {
    return 'The rules $names watch only this channel and are deleted with it.';
  }

  @override
  String feedEditorChannelRemoved(String channel) {
    return '$channel removed';
  }

  @override
  String get feedEditorNoChannelsTitle => 'No channels yet';

  @override
  String get feedEditorNoChannelsMessage =>
      'Add channels your Telegram account has joined; this app never joins one for you.';

  @override
  String get feedEditorChannelLeft =>
      'Left in Telegram; history stays readable';

  @override
  String get feedEditorSearchJoinedChannels => 'Search joined channels';

  @override
  String get feedEditorHideChannelsInFeeds => 'Hide channels already in a feed';

  @override
  String get feedEditorAllChannelsInFeed =>
      'Every channel you have joined is already in this feed.';

  @override
  String feedEditorRestInOtherFeeds(String option) {
    return 'The rest are in other feeds. Untick \"$option\" to see them.';
  }

  @override
  String feedEditorNoChannelMatches(String query) {
    return 'No channel matches \"$query\".';
  }

  @override
  String get feedEditorTickChannels => 'Tick the channels to add';

  @override
  String feedEditorChannelsTicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels ticked',
      one: '$count channel ticked',
    );
    return '$_temp0';
  }

  @override
  String get filterTileTitle => 'Show';

  @override
  String get filterSheetTitle => 'Show in this feed';

  @override
  String get filterPosts => 'Posts';

  @override
  String get filterPostsAll => 'All';

  @override
  String get filterPostsWithMedia => 'With media';

  @override
  String get filterPostsTextOnly => 'Text only';

  @override
  String get filterMediaTypes => 'Media types';

  @override
  String get filterMediaTypesNote =>
      'Leave all of them off to allow every type.';

  @override
  String get filterKindPhotos => 'photos';

  @override
  String get filterKindVideos => 'videos';

  @override
  String get filterKindGifs => 'GIFs';

  @override
  String get filterKindAudio => 'audio';

  @override
  String get filterKindVoice => 'voice messages';

  @override
  String get filterKindFiles => 'files';

  @override
  String get filterKindOther => 'other (polls, stickers, …)';

  @override
  String get filterVideoLength => 'Video length';

  @override
  String get filterVideoAnyLength => 'Any length';

  @override
  String filterFromSeconds(int seconds) {
    return 'From $seconds s';
  }

  @override
  String filterFromMinutes(int minutes) {
    return 'From $minutes min';
  }

  @override
  String get filterTextPosts => 'Text posts';

  @override
  String get filterTextAnyLength => 'Any length';

  @override
  String filterFromCharacters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'From $count characters',
    );
    return '$_temp0';
  }

  @override
  String get filterTextContent => 'Text content';

  @override
  String get filterTextContentNote =>
      'Only posts whose words match are shown, as a rule matches them. A \"Must not contain\" term hides the posts that have it.';

  @override
  String get filterWholePost => 'Show the whole post';

  @override
  String get filterWholePostNote =>
      'A post with several pictures or videos is shown complete, with its caption, as soon as one of them passes. Off shows only the parts that pass.';

  @override
  String get filterShowMinimized => 'Show minimized';

  @override
  String get filterShowMinimizedNote =>
      'The posts this feed leaves out stay in it as one line each, and a tap opens one. They count as hidden all the same.';

  @override
  String get filterHiddenCountAsRead =>
      'Posts this feed hides count as read, and rules stay quiet about them unless another feed with the same channel shows them.';

  @override
  String get filterShowEverything => 'Show everything';

  @override
  String get filterDescribeEverything => 'Everything';

  @override
  String get filterDescribeWithMedia => 'with media';

  @override
  String get filterDescribeTextOnly => 'text only';

  @override
  String filterDescribeVideosFromSeconds(int seconds) {
    return 'videos from $seconds s';
  }

  @override
  String filterDescribeVideosFromMinutes(int minutes) {
    return 'videos from $minutes min';
  }

  @override
  String filterDescribeTextFrom(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'text from $count characters',
    );
    return '$_temp0';
  }

  @override
  String filterDescribeText(String condition) {
    return 'text: $condition';
  }

  @override
  String get filterDescribeMatchingParts => 'matching parts only';

  @override
  String get filterDescribeRestMinimized => 'the rest minimized';

  @override
  String get loginTelegramRefused => 'Telegram refused that.';

  @override
  String get loginSomethingWentWrong => 'Something went wrong. Try again.';

  @override
  String get loginShowPassword => 'Show';

  @override
  String get loginHidePassword => 'Hide';

  @override
  String get loginNewCodeSent => 'A new code is on its way.';

  @override
  String get loginPhoneTitle => 'Log in to Telegram';

  @override
  String loginPhoneExplanation(String appName) {
    return '$appName reads the channels your Telegram account has joined. Enter the phone number of that account in international format.';
  }

  @override
  String get loginPhoneNumber => 'Phone number';

  @override
  String get loginSendCode => 'Send code';

  @override
  String get loginWithQrInstead => 'Log in with QR code instead';

  @override
  String get loginCodeTitle => 'Enter the code';

  @override
  String loginCodeExplanation(String phoneNumber) {
    return 'Telegram sent a code to $phoneNumber (by SMS or to another logged-in device).';
  }

  @override
  String get loginCode => 'Code';

  @override
  String get loginResendCode => 'Resend code';

  @override
  String get loginChangeNumber => 'Change number';

  @override
  String get loginEmailTitle => 'Your email';

  @override
  String get loginEmailExplanation =>
      'Telegram asks this account for an email address. Login codes will be sent to it every time you log in from a new device.';

  @override
  String get loginEmail => 'Email address';

  @override
  String get loginEmailCodeTitle => 'Check your email';

  @override
  String loginEmailCodeExplanation(String email) {
    return 'Telegram sent a code to $email. Look in the spam folder too.';
  }

  @override
  String get loginUnsupportedExplanation =>
      'Telegram asks for a Premium purchase before it lets this number log in, which this app cannot do. Log in with the official Telegram app first, or use another number.';

  @override
  String get loginPasswordTitle => 'Two-step verification';

  @override
  String get loginPasswordExplanation => 'Your account has a cloud password.';

  @override
  String loginPasswordExplanationWithHint(String hint) {
    return 'Your account has a cloud password. Hint: $hint';
  }

  @override
  String get loginPassword => 'Password';

  @override
  String get loginPasswordForgotten =>
      'Forgotten it? A cloud password can only be reset in the official Telegram app, under Settings, Privacy and Security.';

  @override
  String get loginNewAccountTitle => 'New account';

  @override
  String get loginNewAccountExplanation =>
      'This number has no Telegram account yet. Enter a first name to create one.';

  @override
  String get loginFirstName => 'First name';

  @override
  String get loginCreateAccount => 'Create account';

  @override
  String get loginQrTitle => 'Log in with QR code';

  @override
  String get loginQrExplanation =>
      'In Telegram on your phone open Settings, Devices, Link Desktop Device, and scan this code. It refreshes automatically.';

  @override
  String get loginQrBackFailed => 'Could not go back to the phone number.';

  @override
  String get loginWithPhoneInstead => 'Use a phone number instead';

  @override
  String loginUseOtherAccount(String account) {
    return 'Use $account instead';
  }

  @override
  String get conditionErrorStoredUnreadable =>
      'Stored condition could not be parsed; rewrite it.';

  @override
  String get conditionErrorTooNested =>
      'Too nested for the builder; keep editing as text.';

  @override
  String get conditionErrorUnreadable => 'This condition cannot be read.';

  @override
  String get conditionErrorExpectedTerm =>
      'Expected a term where the cursor is.';

  @override
  String get conditionErrorExpectedBracket =>
      'Expected \")\" where the cursor is.';

  @override
  String conditionErrorUnexpected(String symbol) {
    return 'Unexpected \"$symbol\" where the cursor is.';
  }

  @override
  String get conditionErrorUnterminatedQuote =>
      'Unterminated quote where the cursor is.';

  @override
  String get conditionErrorDanglingEscape =>
      'Dangling escape where the cursor is.';

  @override
  String get conditionErrorEmptyTerm => 'Empty term where the cursor is.';

  @override
  String conditionErrorKeyword(String word) {
    return '\"$word\" is a keyword; quote it to match the word where the cursor is.';
  }

  @override
  String get conditionModeBuilder => 'Builder';

  @override
  String get conditionModeText => 'Text';

  @override
  String get conditionTextHelper =>
      'Words or \"phrases\" joined by AND, OR, NOT, with brackets.';

  @override
  String get conditionSyntaxTooltip => 'Syntax';

  @override
  String get conditionSyntaxTitle => 'Writing a condition';

  @override
  String get conditionSyntaxWord => 'the word, wherever it stands';

  @override
  String get conditionSyntaxPhrase => 'those words next to each other';

  @override
  String get conditionSyntaxAnd => 'both have to be there';

  @override
  String get conditionSyntaxOr => 'either one is enough';

  @override
  String get conditionSyntaxNot => 'the post must not have it';

  @override
  String get conditionSyntaxBrackets => 'brackets group the parts';

  @override
  String get conditionSyntaxSubstring =>
      'also inside longer words, like \"rates\"';

  @override
  String get conditionSyntaxCase => 'exactly that spelling, capitals included';

  @override
  String get conditionAddTerm => 'Add a term';

  @override
  String get conditionOr => 'OR';

  @override
  String get conditionAnd => 'AND';

  @override
  String get conditionAndAnotherWord => 'AND another word';

  @override
  String get conditionOrAlternative => 'OR alternative';

  @override
  String get conditionTermHint => 'word or phrase';

  @override
  String get conditionTermHintNegated => 'word it must not have';

  @override
  String get conditionMustNotContain => 'Must not contain';

  @override
  String get conditionWholeWord => 'Whole word';

  @override
  String get conditionMatchCase => 'Match case';

  @override
  String get ruleDiscardTitle => 'Discard changes?';

  @override
  String get ruleDiscardMessage => 'The changes to this rule are not saved.';

  @override
  String get ruleErrorNoName => 'Give the rule a name.';

  @override
  String get ruleErrorNoFeed => 'A rule belongs to a feed: create one first.';

  @override
  String get scheduleErrorNoDays =>
      'Pick at least one day, or the rule never notifies.';

  @override
  String get ruleNotifyAskTitle => 'Let the app notify you?';

  @override
  String get ruleNotifyAskMessage =>
      'This rule notifies you about the posts it matches, which Android has to allow. Without it the rule still runs, but stays silent.';

  @override
  String get ruleDndAskTitle => 'Show urgent posts in Do Not Disturb?';

  @override
  String get ruleDndAskMessage =>
      'Urgent rules can break through Do Not Disturb, but Android must allow this app to do so. Open the setting now? The rule works either way.';

  @override
  String ruleDeleteTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String ruleDryRunScopeChannels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'from $count channels',
      one: 'from $count channel',
    );
    return '$_temp0';
  }

  @override
  String ruleDryRunScopeOfTotal(int total, int limit) {
    return 'of $total (the first $limit are checked)';
  }

  @override
  String ruleDryRunScopeFailed(int count) {
    return '($count could not be read)';
  }

  @override
  String ruleDryRunChecked(String scope) {
    return 'Checked the latest posts $scope.';
  }

  @override
  String ruleDryRunAiNone(int checked, int passed, int scanned) {
    return 'The AI matched none of the $checked newest posts it checked ($passed of the last $scanned passed the keywords).';
  }

  @override
  String ruleDryRunAiMatched(int matched, int checked) {
    return 'The AI matched $matched of the $checked newest posts it checked:';
  }

  @override
  String ruleDryRunAiFailed(String message) {
    return 'The AI check failed: $message';
  }

  @override
  String ruleDryRunNoMatch(int scanned) {
    return 'No match in the last $scanned posts.';
  }

  @override
  String ruleDryRunMatches(int matched, int scanned) {
    return '$matched of the last $scanned posts match:';
  }

  @override
  String get ruleNew => 'New rule';

  @override
  String get ruleEditTitle => 'Edit rule';

  @override
  String get ruleNameLabel => 'Name';

  @override
  String get ruleEnabledTitle => 'Enabled';

  @override
  String get ruleEnabledSubtitle => 'Off keeps the rule but stops it notifying';

  @override
  String get ruleFeedLabel => 'Feed';

  @override
  String get ruleChannelsLabel => 'Channels';

  @override
  String get ruleEveryChannelOfFeed => 'Every channel of the feed';

  @override
  String get ruleConditionTitle => 'Condition';

  @override
  String get ruleNoConditionNote =>
      'No condition: every new post from this rule\'s channels notifies. Add terms to notify only about some of them.';

  @override
  String get semanticNoKeywordsNote =>
      'No keywords: every new post from this rule\'s channels goes to the AI. Add terms to send only posts that contain them.';

  @override
  String get semanticAfterKeywordsNote =>
      'The AI checks only the posts that pass these keywords.';

  @override
  String get ruleDryRunTesting => 'Testing…';

  @override
  String get ruleDryRunButton => 'Test on recent posts';

  @override
  String get ruleNotificationTitle => 'Notification';

  @override
  String get rulePrioritySilent => 'Silent';

  @override
  String get rulePriorityNormal => 'Normal';

  @override
  String get rulePriorityUrgent => 'Urgent';

  @override
  String get rulePrioritySilentInfo =>
      'In the tray only, with no sound and no vibration.';

  @override
  String get rulePriorityNormalInfo =>
      'Pops up, with the sound and vibration set in Notifications and sounds.';

  @override
  String get rulePriorityUrgentInfo =>
      'Pops up, and breaks through Do Not Disturb where Android allows it.';

  @override
  String get ruleReadAloud => 'Read the post aloud';

  @override
  String get scheduleSwitch => 'Only at certain times';

  @override
  String get scheduleMon => 'Mon';

  @override
  String get scheduleTue => 'Tue';

  @override
  String get scheduleWed => 'Wed';

  @override
  String get scheduleThu => 'Thu';

  @override
  String get scheduleFri => 'Fri';

  @override
  String get scheduleSat => 'Sat';

  @override
  String get scheduleSun => 'Sun';

  @override
  String scheduleFrom(String time) {
    return 'From $time';
  }

  @override
  String scheduleTo(String time) {
    return 'To $time';
  }

  @override
  String get scheduleNextDay => '(next day)';

  @override
  String get semanticAlsoAsk => 'Also ask the AI';

  @override
  String get semanticAlsoAskSubtitle =>
      'A model you set up in Settings decides whether a post is about what you describe.';

  @override
  String get semanticPromptLabel => 'What the post should be about';

  @override
  String get semanticPromptHint => 'Central bank interest rate decisions';

  @override
  String get semanticNotConfigured =>
      'The AI endpoint is not set up yet (Settings, AI rules). Until then this rule is skipped.';

  @override
  String get rulesNoFeedsTitle => 'No feeds yet';

  @override
  String get rulesNoFeedsMessage =>
      'Every rule belongs to a feed and watches its channels. Make a feed first, then give it rules.';

  @override
  String get rulesGoToFeeds => 'Go to feeds';

  @override
  String get semanticSkippedTitle => 'AI rules are being skipped';

  @override
  String semanticSkippedSubtitle(String message, String time) {
    return '$message (last tried $time)';
  }

  @override
  String get ruleScopeChannelLeft => 'A channel that left the feed';

  @override
  String get rulesEmptyTitle => 'No rules yet';

  @override
  String get rulesEmptyNoFeeds =>
      'Rules belong to feeds. Make a feed first, then give it rules.';

  @override
  String get rulesEmptyFeed =>
      'A rule watches this feed\'s channels, or one of them, and notifies you, optionally reading the post aloud: give it words to look for, or leave the condition empty to be notified about every post the feed shows.';

  @override
  String get rulesEmptyAll =>
      'Every feed has its own rules: a rule watches the feed\'s channels, or one of them, and notifies you, optionally reading the post aloud.';

  @override
  String get ruleScopeEveryChannel => 'Every channel';

  @override
  String get ruleTileUrgent => 'urgent';

  @override
  String get ruleTileSilent => 'silent';

  @override
  String get ruleTileReadAloud => 'read aloud';

  @override
  String get ruleTileEveryPost => 'every post';

  @override
  String get ruleTileInvalidCondition => '(invalid condition)';

  @override
  String get ruleSemanticsUrgent => 'Urgent rule';

  @override
  String get ruleSemanticsSilent => 'Silent rule';

  @override
  String get ruleSemanticsNormal => 'Normal rule';

  @override
  String semanticPreview(String prompt) {
    return 'AI: $prompt';
  }

  @override
  String semanticPreviewWithKeywords(String prompt, String keywords) {
    return 'AI: $prompt · only if $keywords';
  }

  @override
  String get ruleBatteryBanner =>
      'Android may stop background watching, and rules would then go quiet. Allow the app to ignore battery optimisation so they keep working.';

  @override
  String get semanticProblemNotSetUp =>
      'The AI endpoint is not set up in Settings.';

  @override
  String semanticProblemUnreachable(String error) {
    return 'Could not reach the AI endpoint: $error';
  }

  @override
  String semanticProblemHttpStatus(int status, String error) {
    return 'The AI endpoint answered $status: $error';
  }

  @override
  String get semanticProblemUnexpectedAnswer =>
      'The AI endpoint sent an unexpected answer.';

  @override
  String get semanticProblemEmptyAnswer =>
      'The model returned an empty answer.';

  @override
  String get readAloudTitle => 'Read aloud';

  @override
  String get readAloudPreview => 'Preview';

  @override
  String get readAloudPreviewText =>
      'New post in Example channel. This is how posts will sound.';

  @override
  String readAloudSpeed(String speed) {
    return 'Speed  ·  $speed×';
  }

  @override
  String readAloudSpeedSemantics(String speed) {
    return 'Speed $speed times';
  }

  @override
  String readAloudPitch(String pitch) {
    return 'Pitch  ·  $pitch';
  }

  @override
  String readAloudPitchSemantics(String pitch) {
    return 'Pitch $pitch';
  }

  @override
  String get readAloudMaxLength => 'Maximum length';

  @override
  String readAloudMaxLengthSubtitle(int maxChars) {
    return 'Posts longer than $maxChars characters end with \"and more\"';
  }

  @override
  String get readAloudDefaultLanguage => 'Language when unknown';

  @override
  String get readAloudDefaultLanguageSubtitle =>
      'Used when a post\'s language cannot be detected';

  @override
  String get readAloudVoices => 'Voices';

  @override
  String get readAloudNoVoices => 'No voices reported by the speech engine';

  @override
  String get readAloudNoVoicesSubtitle =>
      'The system default voice is used for every language';

  @override
  String get readAloudUseDefaultVoice => 'Use the default voice';

  @override
  String get readAloudAddLanguage => 'Add language';

  @override
  String get readAloudOtherLanguagesFooter =>
      'Every other language is read with the phone\'s default voice for it.';

  @override
  String get readAloudPhoneDefaultVoice => 'The phone\'s default voice';

  @override
  String get readAloudSearchLanguages => 'Search languages';

  @override
  String readAloudVoiceId(String id) {
    return 'Voice $id';
  }

  @override
  String get readAloudVoiceOnline => 'online';

  @override
  String get readAloudVoiceFemale => 'Female';

  @override
  String get readAloudVoiceMale => 'Male';

  @override
  String get notificationSettingsTitle => 'Notifications and sounds';

  @override
  String get notificationSettingsRestartTitle => 'Restart the app?';

  @override
  String get notificationSettingsRestartStartsWatching =>
      'Watching in the background starts when the app starts again.';

  @override
  String get notificationSettingsRestartStopsWatching =>
      'The permanent notification goes away when the app starts again.';

  @override
  String get notificationSettingsRestartDueStopsWatching =>
      'The permanent notification goes when the app starts again.';

  @override
  String get notificationSettingsRestartNow => 'Restart now';

  @override
  String get notificationSettingsBlocked =>
      'Android blocks this app\'s notifications, so no rule can notify you.';

  @override
  String get notificationSettingsTurnOn => 'Turn them on';

  @override
  String get notificationSettingsRuleNotifications => 'Rule notifications';

  @override
  String get notificationSettingsBadgeCounter => 'Badge counter';

  @override
  String get notificationSettingsCountUnreadPosts => 'Count unread posts';

  @override
  String get notificationSettingsCountFooter =>
      'The badges of the feeds and of the folder tabs count the unread posts. Off, they count the channels that have unread posts.';

  @override
  String get notificationSettingsBackground => 'Background';

  @override
  String get notificationSettingsWatchInBackground =>
      'Watch channels in the background';

  @override
  String get notificationSettingsWatchInBackgroundSubtitle =>
      'Rules keep running while the app is closed. Off removes the permanent notification, and rules then only notify while the app is open. The app restarts to apply it.';

  @override
  String get notificationSettingsSystemSettings =>
      'System notification settings';

  @override
  String notificationSettingsNoSoundPicker(String message) {
    return 'No sound picker: $message';
  }

  @override
  String get notificationSettingsNoSoundPickerOnDevice =>
      'No sound picker on this device.';

  @override
  String get notificationSettingsNormalSound => 'Normal rules: sound';

  @override
  String get notificationSettingsNormalVibrate => 'Normal rules: vibrate';

  @override
  String get notificationSettingsUrgentSound => 'Urgent rules: sound';

  @override
  String get notificationSettingsUrgentVibrate => 'Urgent rules: vibrate';

  @override
  String get notificationSettingsSystemDefaultSound => 'The system default';

  @override
  String get notificationSettingsChosenSound => 'A chosen sound';

  @override
  String get notificationSettingsUseDefaultSound => 'Use the default';

  @override
  String get notificationSettingsSilentRulesFooter =>
      'Silent rules stay silent.';

  @override
  String get privacyTitle => 'Privacy and security';

  @override
  String get privacySecurity => 'Security';

  @override
  String get privacyAppLockFooter =>
      'A PIN, or the phone\'s own fingerprint or face, is asked for when the app has rested. Without it anyone holding the unlocked phone can read your channels.';

  @override
  String get appLockTitle => 'App lock';

  @override
  String appLockLocked(String appName) {
    return '$appName is locked';
  }

  @override
  String appLockUnlockReason(String appName) {
    return 'Unlock $appName';
  }

  @override
  String get appLockBiometricsUnavailable =>
      'The phone\'s check is not available; use the PIN.';

  @override
  String get appLockWrongPin => 'Wrong PIN';

  @override
  String appLockTooManyTries(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '1 second',
    );
    return 'Too many tries. Try again in $_temp0.';
  }

  @override
  String get appLockShowContent => 'Show app content in task switcher';

  @override
  String get appLockShowContentSubtitle =>
      'Off, the task switcher shows a blank card and screenshots are refused while the lock is set';

  @override
  String get appLockPin => 'PIN';

  @override
  String get appLockUnlock => 'Unlock';

  @override
  String get appLockUseBiometrics => 'Use fingerprint or face';

  @override
  String get appLockRemoveTitle => 'Remove the lock?';

  @override
  String get appLockRemoveMessage =>
      'Anyone holding the unlocked phone can then read your channels.';

  @override
  String get appLockTooShort => 'At least four digits';

  @override
  String get appLockMismatch => 'The two do not match';

  @override
  String get appLockPinReplaced => 'PIN replaced';

  @override
  String get appLockPinSet => 'PIN set, the lock is on';

  @override
  String get appLockTimeoutAtOnce => 'At once';

  @override
  String get appLockTimeoutMinute => 'After a minute';

  @override
  String get appLockTimeoutFiveMinutes => 'After five minutes';

  @override
  String get appLockTimeoutHour => 'After an hour';

  @override
  String get appLockEnterPinToChange => 'Enter your PIN to change the lock';

  @override
  String get appLockIntroWithPin =>
      'The app asks for this PIN when it has rested. Setting a new one replaces it.';

  @override
  String get appLockIntroNoPin =>
      'A PIN keeps the channels you read out of the hands of whoever holds the unlocked phone.';

  @override
  String get appLockNewPin => 'New PIN';

  @override
  String get appLockPinAgain => 'PIN again';

  @override
  String get appLockReplacePin => 'Replace the PIN';

  @override
  String get appLockSetPin => 'Set the PIN';

  @override
  String get appLockRemove => 'Remove the lock';

  @override
  String get appLockAskAgain => 'Ask again';

  @override
  String get appLockBiometrics => 'Fingerprint or face';

  @override
  String get appLockBiometricsSubtitle =>
      'Offered first when the app is locked; the PIN always works too';

  @override
  String languageName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'af': 'Afrikaans',
      'am': 'Amharic',
      'ar': 'Arabic',
      'as': 'Assamese',
      'az': 'Azerbaijani',
      'be': 'Belarusian',
      'bg': 'Bulgarian',
      'bn': 'Bengali',
      'brx': 'Bodo',
      'bs': 'Bosnian',
      'ca': 'Catalan',
      'cmn': 'Mandarin',
      'cs': 'Czech',
      'cy': 'Welsh',
      'da': 'Danish',
      'de': 'German',
      'doi': 'Dogri',
      'el': 'Greek',
      'en': 'English',
      'es': 'Spanish',
      'et': 'Estonian',
      'eu': 'Basque',
      'fa': 'Persian',
      'fi': 'Finnish',
      'fil': 'Filipino',
      'fr': 'French',
      'ga': 'Irish',
      'gl': 'Galician',
      'gu': 'Gujarati',
      'he': 'Hebrew',
      'hi': 'Hindi',
      'hr': 'Croatian',
      'hu': 'Hungarian',
      'hy': 'Armenian',
      'id': 'Indonesian',
      'is': 'Icelandic',
      'it': 'Italian',
      'ja': 'Japanese',
      'jv': 'Javanese',
      'ka': 'Georgian',
      'kk': 'Kazakh',
      'km': 'Khmer',
      'kn': 'Kannada',
      'ko': 'Korean',
      'kok': 'Konkani',
      'ks': 'Kashmiri',
      'ky': 'Kyrgyz',
      'lo': 'Lao',
      'lt': 'Lithuanian',
      'lv': 'Latvian',
      'mai': 'Maithili',
      'mk': 'Macedonian',
      'ml': 'Malayalam',
      'mn': 'Mongolian',
      'mni': 'Manipuri',
      'mr': 'Marathi',
      'ms': 'Malay',
      'my': 'Burmese',
      'nb': 'Norwegian',
      'ne': 'Nepali',
      'nl': 'Dutch',
      'no': 'Norwegian',
      'or': 'Odia',
      'pa': 'Punjabi',
      'pl': 'Polish',
      'pt': 'Portuguese',
      'ro': 'Romanian',
      'ru': 'Russian',
      'sa': 'Sanskrit',
      'sat': 'Santali',
      'sd': 'Sindhi',
      'si': 'Sinhala',
      'sk': 'Slovak',
      'sl': 'Slovenian',
      'sq': 'Albanian',
      'sr': 'Serbian',
      'su': 'Sundanese',
      'sv': 'Swedish',
      'sw': 'Swahili',
      'ta': 'Tamil',
      'te': 'Telugu',
      'th': 'Thai',
      'tr': 'Turkish',
      'uk': 'Ukrainian',
      'ur': 'Urdu',
      'uz': 'Uzbek',
      'vi': 'Vietnamese',
      'yue': 'Cantonese',
      'zh': 'Chinese',
      'zu': 'Zulu',
      'other': '?',
    });
    return '$_temp0';
  }

  @override
  String get settingsLogOut => 'Log out';

  @override
  String get accountsTitle => 'Accounts';

  @override
  String get settingsSavedMessages => 'Saved Messages';

  @override
  String get chatSettingsTitle => 'Chat settings';

  @override
  String get settingsPrivacyAndSecurity => 'Privacy and security';

  @override
  String get settingsNotificationsAndSounds => 'Notifications and sounds';

  @override
  String get dataStorageTitle => 'Data and storage';

  @override
  String get settingsReadAloud => 'Read aloud';

  @override
  String get aiSettingsTitle => 'AI rules';

  @override
  String get syncTitle => 'Google Drive sync';

  @override
  String get settingsSyncSignedOut => 'Signed out';

  @override
  String get settingsAbout => 'About';

  @override
  String settingsAboutApp(String appName) {
    return 'About $appName';
  }

  @override
  String get settingsLicenses => 'Open-source licenses';

  @override
  String settingsAppForAndroid(String appName) {
    return '$appName for Android';
  }

  @override
  String settingsAppVersion(String appName, String version) {
    return '$appName for Android $version';
  }

  @override
  String get settingsAboutText =>
      'Free software under the GNU GPL v3. Reads your joined channels; nothing leaves the device except Telegram traffic and, if you create AI rules, the posts those rules check, sent to the endpoint you chose.';

  @override
  String get settingsAccountUnavailable => 'Account unavailable';

  @override
  String get settingsReloadProfile => 'Reload the profile';

  @override
  String accountsNumbered(int id) {
    return 'Account $id';
  }

  @override
  String get accountsLimitReached =>
      'Four accounts is as many as the app holds.';

  @override
  String accountsRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get accountsRemoveText =>
      'Its session, feeds, rules and cached posts are deleted from this device. The Telegram account itself stays as it is.';

  @override
  String get accountsLastCannotBeRemoved =>
      'The last account cannot be removed; log out instead.';

  @override
  String get accountsIntro =>
      'Each account has its own session, feeds and rules on this device. Switching takes the watcher down and brings it up again on the other account.';

  @override
  String get accountsInUse => 'In use';

  @override
  String get accountsTapToSwitch => 'Tap to switch to it';

  @override
  String get accountsRemoveTooltip => 'Remove from this device';

  @override
  String get accountsAdd => 'Add an account';

  @override
  String get accountsAddLimit => 'Four is as many as the app holds';

  @override
  String get accountsAddSubtitle =>
      'Logs in as another account and switches to it';

  @override
  String get aiSettingsTestOk => 'Works: the model answered correctly.';

  @override
  String get aiSettingsTestUnexpected =>
      'The endpoint answered, but not as expected. Try a stronger model.';

  @override
  String get aiSettingsIntro =>
      'AI rules describe in your own words what a post should be about. To check them, the app sends the text of candidate posts to the endpoint below. Nothing is sent unless you create such a rule.';

  @override
  String get aiSettingsEndpoint => 'Endpoint';

  @override
  String get aiSettingsEndpointHelper =>
      'Any OpenAI-compatible API: OpenAI, OpenRouter, a local Ollama (…/v1), …';

  @override
  String get aiSettingsHttpWarning =>
      'http:// is not encrypted: posts and the key travel in the clear. Use it only for an endpoint on your own network.';

  @override
  String get aiSettingsModel => 'Model';

  @override
  String get aiSettingsApiKey => 'API key';

  @override
  String get aiSettingsApiKeyHelper =>
      'Stored in the Android keystore. Leave empty for local endpoints.';

  @override
  String get aiSettingsHideKey => 'Hide key';

  @override
  String get aiSettingsShowKey => 'Show key';

  @override
  String get aiSettingsSaveAndTest => 'Save and test';

  @override
  String get chatSettingsTextSize => 'Text size in posts';

  @override
  String get chatSettingsTextSizePreview => 'A post is drawn at this size.';

  @override
  String get chatSettingsQuickReaction => 'Quick reaction';

  @override
  String get chatSettingsQuickReactionInfo =>
      'A double tap on a post sends it.';

  @override
  String get postReactionsAll => 'All reactions';

  @override
  String get chatSettingsTheme => 'Theme';

  @override
  String get chatSettingsThemeSystem => 'System';

  @override
  String get chatSettingsThemeLight => 'Light';

  @override
  String get chatSettingsThemeDark => 'Dark';

  @override
  String get chatSettingsThemeFooter =>
      'System follows the dark theme switch of the phone.';

  @override
  String get dataStorageResetTitle => 'Reset auto-download settings?';

  @override
  String get dataStorageResetText =>
      'Mobile data goes back to Medium, Wi-Fi to High and roaming to Low.';

  @override
  String get dataStorageDiskAndNetwork => 'Disk and network usage';

  @override
  String get dataStorageStorageUsage => 'Storage usage';

  @override
  String get dataStorageAutoDownload => 'Automatic media download';

  @override
  String get dataStorageReset => 'Reset auto-download settings';

  @override
  String get dataStorageAutoplay => 'Autoplay media';

  @override
  String get dataStorageGifs => 'GIFs';

  @override
  String get dataStorageVideos => 'Videos';

  @override
  String get dataStorageAutoplayFooter =>
      'A video that loads by itself on the connection the phone is on plays muted in its post; a tap opens it with sound.';

  @override
  String get dataStorageDataUsage => 'Data usage';

  @override
  String get dataStoragePresetCustom => 'Custom';

  @override
  String get dataStorageMediaTypes => 'Types of media';

  @override
  String get dataStoragePhotos => 'Photos';

  @override
  String get dataStorageEveryPhoto => 'Every photo';

  @override
  String dataStorageUpTo(String size) {
    return 'Up to $size';
  }

  @override
  String get dataStorageTypesFooter =>
      'GIFs and round video messages count as videos, music and voice messages as files. A video within the limit also autoplays, if Autoplay is on for it in Data and storage.';

  @override
  String get dataStorageMaxVideoSize => 'Maximum video size';

  @override
  String get dataStorageMaxFileSize => 'Maximum file size';

  @override
  String get dataStoragePreload => 'Preload larger videos';

  @override
  String dataStoragePreloadFooter(String size) {
    return 'The first seconds of videos larger than $size are loaded ahead, so that they start at once.';
  }

  @override
  String get dataStorageAutoDownloadMedia => 'Auto-download media';

  @override
  String dataStorageClearTitle(String size) {
    return 'Clear $size of cache?';
  }

  @override
  String get dataStorageClearText =>
      'Pictures, videos and files load again from Telegram when you open them.';

  @override
  String get dataStorageStatsFailed =>
      'Telegram did not say how much it stores.';

  @override
  String get dataStorageTelegramCache => 'Telegram\'s cache';

  @override
  String get dataStorageCachedFiles => 'Cached files';

  @override
  String dataStorageFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
    );
    return '$_temp0';
  }

  @override
  String get dataStorageDatabase => 'Database';

  @override
  String get dataStorageClearing => 'Clearing…';

  @override
  String dataStorageClearCache(String size) {
    return 'Clear cache ($size)';
  }

  @override
  String get dataStorageClearFooter =>
      'Pictures, videos and files are loaded again from Telegram when you open them. Your feeds, rules and read positions stay.';

  @override
  String syncAtTime(String time) {
    return 'at $time';
  }

  @override
  String syncYesterdayAt(String time) {
    return 'yesterday at $time';
  }

  @override
  String syncDateAtTime(String date, String time) {
    return '$date at $time';
  }

  @override
  String get syncUnavailable => 'Not available in this build';

  @override
  String syncProblem(String error) {
    return 'Problem: $error';
  }

  @override
  String syncOnAccount(String account) {
    return 'On, $account';
  }

  @override
  String syncOnAccountLastSynced(String account, String when) {
    return 'On, $account · last synced $when';
  }

  @override
  String get syncIntro =>
      'Keeps your feeds with their channels, your rules and your settings the same on all your devices through a hidden app file in your own Google Drive. There is no server of ours. Read positions, the AI API key and your Telegram session stay on each device.';

  @override
  String get syncNoClientIdBuild =>
      'This build was made without a Google client id, so sync cannot be turned on.';

  @override
  String get syncSignIn => 'Sign in with Google and sync';

  @override
  String get syncSyncing => 'Syncing…';

  @override
  String get syncNotSyncedYet => 'Not synced yet';

  @override
  String syncLastSynced(String when) {
    return 'Last synced $when';
  }

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncTurnOff => 'Turn off on this device';

  @override
  String get syncSignedOutError =>
      'Signed out of Google. Sign in again to keep syncing.';

  @override
  String get syncNoClientIdError => 'This build has no Google client id.';

  @override
  String get syncSignInCancelled => 'Sign-in was cancelled.';

  @override
  String syncSignInFailed(String detail) {
    return 'Google sign-in failed: $detail';
  }

  @override
  String get syncNotSignedIn => 'Not signed in to Google Drive.';

  @override
  String syncDriveUnreachable(String detail) {
    return 'Google Drive cannot be reached: $detail';
  }

  @override
  String syncDriveRefused(String request, String status, String detail) {
    String _temp0 = intl.Intl.selectLogic(request, {
      'find': 'look for the sync file',
      'read': 'read the sync file',
      'create': 'create the sync file',
      'other': 'update the sync file',
    });
    return 'Google Drive refused to $_temp0 ($status)$detail';
  }

  @override
  String viewerCounter(int index, int total) {
    return '$index of $total';
  }

  @override
  String get viewerSaveToSavedMessages => 'Save to Saved Messages';

  @override
  String get viewerSaveToGallery => 'Save to gallery';

  @override
  String get viewerVideoSavedToGallery => 'Video saved to gallery';

  @override
  String get viewerPictureSavedToGallery => 'Picture saved to gallery';

  @override
  String viewerSaveFailed(String error) {
    return 'Cannot save: $error';
  }

  @override
  String get viewerShareNeedsDownload =>
      'Download the video first to share it.';

  @override
  String get viewerShareFileMissing => 'Cannot share: the file did not arrive';

  @override
  String viewerShareFailed(String error) {
    return 'Cannot share: $error';
  }

  @override
  String get pipOpen => 'Picture-in-picture';

  @override
  String get pipFloatingPlayer => 'Floating video player';

  @override
  String get pipBackToFullScreen => 'Back to full screen';

  @override
  String get playerPlay => 'Play';

  @override
  String get playerPause => 'Pause';

  @override
  String get playerSpeed => 'Speed';

  @override
  String get audioStop => 'Stop';

  @override
  String get videoSoundOn => 'Sound on';

  @override
  String get videoSoundOff => 'Sound off';

  @override
  String videoSeekSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String videoCannotPlay(String error) {
    return 'Cannot play this video: $error';
  }

  @override
  String get videoDownload => 'Download';

  @override
  String videoDownloadWithSize(String size) {
    return 'Download ($size)';
  }

  @override
  String get videoCancelDownload => 'Cancel download';

  @override
  String get videoDownloadFailed => 'Failed, try again';

  @override
  String get autoDownloadRowMobile => 'When using mobile data';

  @override
  String get autoDownloadRowWifi => 'When connected on Wi-Fi';

  @override
  String get autoDownloadRowRoaming => 'When roaming';

  @override
  String get autoDownloadTitleMobile => 'Using mobile data';

  @override
  String get autoDownloadTitleWifi => 'Using Wi-Fi';

  @override
  String get autoDownloadTitleRoaming => 'Roaming';

  @override
  String get autoDownloadPresetLow => 'Low';

  @override
  String get autoDownloadPresetMedium => 'Medium';

  @override
  String get autoDownloadPresetHigh => 'High';

  @override
  String get autoDownloadSummaryDisabled => 'Disabled';

  @override
  String get autoDownloadSummaryNothing => 'Nothing';

  @override
  String get autoDownloadSummaryPhotos => 'Photos';

  @override
  String autoDownloadSummaryVideos(String limit) {
    return 'Videos ($limit)';
  }

  @override
  String autoDownloadSummaryFiles(String limit) {
    return 'Files ($limit)';
  }

  @override
  String appStartFailed(String error) {
    return 'Could not start the core: $error';
  }

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageFooter =>
      'System picks the phone\'s language when the app is translated into it, and English otherwise.';

  @override
  String ttsIntro(String channel) {
    return 'New post in $channel.';
  }

  @override
  String get ttsLink => 'link';

  @override
  String get ttsMore => '… and more';

  @override
  String get serviceChannelName => 'Watching channels';

  @override
  String get serviceChannelDescription =>
      'Keeps the Telegram connection open for keyword rules';

  @override
  String get serviceStarting => 'Starting…';

  @override
  String get servicePause => 'Pause';

  @override
  String get serviceResume => 'Resume';

  @override
  String get servicePaused => 'Paused: rules are not evaluated';

  @override
  String serviceWatching(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Watching $count channels',
      one: 'Watching 1 channel',
    );
    return '$_temp0';
  }

  @override
  String get notifyNewPost => 'New post';

  @override
  String notifyNewPosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new posts',
      one: '1 new post',
    );
    return '$_temp0';
  }

  @override
  String get notifyListen => 'Listen';

  @override
  String get notifyStop => 'Stop';

  @override
  String get notifyChannelSilent => 'Silent posts';

  @override
  String get notifyChannelSilentDescription =>
      'Rules with silent priority: no sound, no heads-up';

  @override
  String get notifyChannelNormal => 'Posts';

  @override
  String get notifyChannelNormalDescription => 'Rules with normal priority';

  @override
  String get notifyChannelNormalInApp => 'Posts while the app is open';

  @override
  String get notifyChannelNormalInAppDescription =>
      'Rules with normal priority while the app is open, without a pop-up';

  @override
  String get notifyChannelUrgent => 'Urgent posts';

  @override
  String get notifyChannelUrgentDescription => 'Rules with urgent priority';

  @override
  String get notifyChannelUrgentInApp => 'Urgent posts while the app is open';

  @override
  String get notifyChannelUrgentInAppDescription =>
      'Rules with urgent priority while the app is open, without a pop-up';

  @override
  String notifyChannelBypassesDnd(String description) {
    return '$description; bypasses Do Not Disturb';
  }

  @override
  String get mediaPoll => 'Poll';

  @override
  String get mediaLocation => 'Location';

  @override
  String get mediaVenue => 'Venue';

  @override
  String get mediaContact => 'Contact';

  @override
  String get mediaDice => 'Dice';

  @override
  String get mediaGame => 'Game';

  @override
  String get mediaInvoice => 'Invoice';

  @override
  String get mediaGiveaway => 'Giveaway';

  @override
  String get mediaStory => 'Story';

  @override
  String get mediaChecklist => 'Checklist';

  @override
  String get mediaAlbum => 'Album';

  @override
  String get mediaPaidMedia => 'Paid media';

  @override
  String get mediaUnsupported => 'Unsupported post';

  @override
  String servicePinned(String channel) {
    return '$channel pinned a post';
  }

  @override
  String servicePinnedOpen(String channel) {
    return '$channel pinned a post. Open the pinned post';
  }

  @override
  String serviceTitleChanged(String title) {
    return 'Channel name changed to $title';
  }

  @override
  String get servicePhotoChanged => 'Channel photo updated';

  @override
  String get servicePhotoRemoved => 'Channel photo removed';

  @override
  String get serviceChannelCreated => 'Channel created';

  @override
  String get serviceLiveStarted => 'Live stream started';

  @override
  String serviceLiveEnded(String length) {
    return 'Live stream ended ($length)';
  }

  @override
  String serviceLiveScheduled(String date) {
    return 'Live stream scheduled on $date';
  }

  @override
  String get serviceOther => 'Service message';

  @override
  String serviceOfChannel(String channel, String words) {
    return '$channel: $words';
  }

  @override
  String get problemSyncNewerVersion =>
      'The sync file was written by a newer version of the app. Update this device.';

  @override
  String problemSyncUnreadable(String error) {
    return 'The sync file cannot be read: $error';
  }
}
