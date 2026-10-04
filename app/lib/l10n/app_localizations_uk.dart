// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get commonCancel => 'Скасувати';

  @override
  String get commonOk => 'Гаразд';

  @override
  String get commonSave => 'Зберегти';

  @override
  String get commonDelete => 'Видалити';

  @override
  String get commonDone => 'Готово';

  @override
  String get commonClose => 'Закрити';

  @override
  String get commonRetry => 'Повторити';

  @override
  String get commonTryAgain => 'Спробувати ще раз';

  @override
  String get commonOn => 'Увімк.';

  @override
  String get commonOff => 'Вимк.';

  @override
  String get commonUndo => 'Скасувати';

  @override
  String get commonShare => 'Поділитися';

  @override
  String get commonRemove => 'Видалити';

  @override
  String get commonClear => 'Очистити';

  @override
  String get commonRename => 'Перейменувати';

  @override
  String get commonMore => 'Більше';

  @override
  String get commonLoading => 'Завантаження…';

  @override
  String get commonLater => 'Пізніше';

  @override
  String get commonNotNow => 'Не зараз';

  @override
  String get commonAllow => 'Дозволити';

  @override
  String get commonContinue => 'Продовжити';

  @override
  String get commonApply => 'Застосувати';

  @override
  String get commonReset => 'Скинути';

  @override
  String get commonSelect => 'Вибрати';

  @override
  String get commonOpen => 'Відкрити';

  @override
  String get commonAdd => 'Додати';

  @override
  String get commonSearch => 'Пошук';

  @override
  String get commonSettings => 'Налаштування';

  @override
  String get commonRules => 'Правила';

  @override
  String get commonComments => 'Коментарі';

  @override
  String get commonCopyLink => 'Копіювати посилання';

  @override
  String get commonOpenInTelegram => 'Відкрити в Telegram';

  @override
  String get commonOpenSettings => 'Відкрити налаштування';

  @override
  String get commonDiscard => 'Відхилити';

  @override
  String get commonKeepEditing => 'Продовжити редагування';

  @override
  String get commonMarkAsRead => 'Позначити прочитаним';

  @override
  String get mediaPhoto => 'Фото';

  @override
  String get mediaVideo => 'Відео';

  @override
  String get mediaGif => 'GIF';

  @override
  String get mediaVideoMessage => 'Відеоповідомлення';

  @override
  String get mediaVoiceMessage => 'Голосове повідомлення';

  @override
  String get mediaAudio => 'Аудіо';

  @override
  String get mediaSticker => 'Наліпка';

  @override
  String get mediaFile => 'Файл';

  @override
  String get mediaPost => 'Допис';

  @override
  String get tabMedia => 'Медіа';

  @override
  String get tabFiles => 'Файли';

  @override
  String get tabLinks => 'Посилання';

  @override
  String get tabMusic => 'Музика';

  @override
  String get tabVoice => 'Голосові';

  @override
  String mediaStickerWithEmoji(String emoji) {
    return '$emoji Наліпка';
  }

  @override
  String get timelineSpoiler => 'спойлер';

  @override
  String get timelineCodeCopied => 'Код скопійовано';

  @override
  String get linkOpenTitle => 'Відкрити посилання';

  @override
  String linkOpenQuestion(String url) {
    return 'Ви дійсно хочете відкрити $url?';
  }

  @override
  String get phoneCall => 'Виклик';

  @override
  String get phoneCopy => 'Копіювати номер';

  @override
  String get phoneCopied => 'Номер скопійовано';

  @override
  String get timelineCopyCode => 'Копіювати код';

  @override
  String timelineCannotPlay(String error) {
    return 'Не вдалося відтворити: $error';
  }

  @override
  String get timelinePlay => 'Відтворити';

  @override
  String get timelinePause => 'Пауза';

  @override
  String timelineSelectedCount(int count) {
    return 'Вибрано $count';
  }

  @override
  String get timelineCopyText => 'Копіювати текст';

  @override
  String get timelineSaveToSavedMessages => 'Зберегти до Збереженого';

  @override
  String timelinePostsCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count допису скопійовано',
      many: '$count дописів скопійовано',
      few: '$count дописи скопійовано',
      one: '$count допис скопійовано',
    );
    return '$_temp0';
  }

  @override
  String timelinePostsSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count допису збережено до Збереженого',
      many: '$count дописів збережено до Збереженого',
      few: '$count дописи збережено до Збереженого',
      one: '$count допис збережено до Збереженого',
    );
    return '$_temp0';
  }

  @override
  String get timelineSavePostsFailed => 'Не вдалося зберегти дописи.';

  @override
  String get timelineDeletePostTitle => 'Видалити допис';

  @override
  String get timelineDeletePostMessage =>
      'Ви впевнені, що хочете видалити цей допис?';

  @override
  String timelineDeletePostsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалити $count допису',
      many: 'Видалити $count дописів',
      few: 'Видалити $count дописи',
      one: 'Видалити $count допис',
    );
    return '$_temp0';
  }

  @override
  String get timelineDeletePostsMessage =>
      'Ви впевнені, що хочете видалити ці дописи?';

  @override
  String get timelineDeletePostsFailed => 'Не вдалося видалити дописи.';

  @override
  String get timelineJumpToDate => 'Перейти до дати';

  @override
  String timelineSubscribers(int count, String shown) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shown підписника',
      many: '$shown підписників',
      few: '$shown підписники',
      one: '$shown підписник',
    );
    return '$_temp0';
  }

  @override
  String get timelineEditFeed => 'Редагувати стрічку';

  @override
  String get timelineJumpToDayFailed => 'Не вдалося перейти до цього дня.';

  @override
  String timelineNothingFromDay(String day) {
    return '$day і раніше тут нічого немає.';
  }

  @override
  String get timelineNoAppForPost =>
      'Жоден застосунок не може відкрити цей допис.';

  @override
  String get timelineForwardHidden =>
      'Цей допис переслано з прихованого акаунта.';

  @override
  String timelineForwardNotFollowed(String title) {
    return '«$title» немає серед ваших каналів.';
  }

  @override
  String get timelineReplyNotFollowed =>
      'Цей допис у каналі, на який ви не підписані.';

  @override
  String timelineNoAppForLink(String url) {
    return 'Жоден застосунок не може відкрити $url';
  }

  @override
  String get timelineNoLinkToShare =>
      'У цього допису немає посилання, щоб ним поділитися.';

  @override
  String get timelineTextCopied => 'Текст скопійовано';

  @override
  String get timelineNoLinkToCopy =>
      'У цього допису немає посилання, щоб його скопіювати.';

  @override
  String timelineLinkCopied(String link) {
    return 'Посилання скопійовано: $link';
  }

  @override
  String get timelineSavedToSavedMessages => 'Збережено до Збереженого';

  @override
  String get timelineSavePostFailed => 'Не вдалося зберегти допис.';

  @override
  String get timelineReactionFailed => 'Не вдалося надіслати реакцію.';

  @override
  String timelineNewPosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count нового допису',
      many: '$count нових дописів',
      few: '$count нові дописи',
      one: '$count новий допис',
    );
    return '$_temp0';
  }

  @override
  String timelineUnreadPostsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count непрочитаного допису',
      many: '$count непрочитаних дописів',
      few: '$count непрочитані дописи',
      one: '$count непрочитаний допис',
    );
    return '$_temp0';
  }

  @override
  String get timelineNewestPosts => 'До найновіших дописів';

  @override
  String get timelineNoChannelsTitle => 'У цій стрічці ще немає каналів';

  @override
  String get timelineNoChannelsMessage =>
      'Додайте канали, з яких вона збиратиме дописи. Вони читатимуться одним потоком, від найстаріших.';

  @override
  String get timelineAddChannels => 'Додати канали';

  @override
  String get timelineLoadFailed => 'Не вдалося завантажити дописи.';

  @override
  String get timelineNoPosts => 'Дописів немає.';

  @override
  String timelineNoPostsPassFilter(String filter) {
    return 'Жоден допис не проходить фільтр цієї стрічки ($filter).';
  }

  @override
  String get timelineBeginningOfFeed => 'Початок стрічки';

  @override
  String get timelineOlderFailed => 'Не вдалося завантажити старіші дописи.';

  @override
  String get timelinePinnedPost => 'Прикріплений допис';

  @override
  String get timelineHidePinned => 'Приховати';

  @override
  String get timelinePreviousPinned => 'Попередній допис';

  @override
  String timelinePinnedPostNumber(int number) {
    return 'Прикріплений допис #$number';
  }

  @override
  String get timelinePinnedList => 'Прикріплені дописи';

  @override
  String pinnedPostsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count прикріпленого допису',
      many: '$count прикріплених дописів',
      few: '$count прикріплені дописи',
      one: '$count прикріплений допис',
    );
    return '$_temp0';
  }

  @override
  String get pinnedPostsOpen => 'Перейти до допису';

  @override
  String get pinnedPostsHide => 'Приховати всі прикріплені';

  @override
  String get pinnedPostsHidden =>
      'Прикріплені дописи приховано. Ви знову побачите їх, коли буде прикріплено новий допис.';

  @override
  String get timelineUnreadDivider => 'Непрочитані дописи';

  @override
  String get searchFilterEverything => 'Усе';

  @override
  String get searchRecent => 'Недавні пошуки';

  @override
  String get searchRemoveRecent => 'Прибрати з недавніх';

  @override
  String get searchClearHistoryTitle => 'Очистити історію пошуку';

  @override
  String get searchClearHistoryBody => 'Ви хочете очистити історію пошуку?';

  @override
  String get searchClearAll => 'Очистити все';

  @override
  String get searchFailed => 'Не вдалося виконати пошук.';

  @override
  String get searchTypeToSearch => 'Введіть запит, щоб шукати дописи.';

  @override
  String get searchNothingFoundPlain => 'Нічого не знайдено.';

  @override
  String searchNothingFound(String query) {
    return 'За запитом «$query» нічого не знайдено.';
  }

  @override
  String searchPostsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Знайдено $count допису',
      many: 'Знайдено $count дописів',
      few: 'Знайдено $count дописи',
      one: 'Знайдено $count допис',
    );
    return '$_temp0';
  }

  @override
  String get searchMoreFailed => 'Не вдалося завантажити інші результати.';

  @override
  String get searchOlderMatch => 'Старіший результат';

  @override
  String get searchNewerMatch => 'Новіший результат';

  @override
  String get searchNoMatches => 'Немає результатів';

  @override
  String get searchShowAsList => 'Показати списком';

  @override
  String get searchShowAsChat => 'Показати в чаті';

  @override
  String searchMatchOf(int current, int total) {
    return '$current з $total';
  }

  @override
  String get searchPostsHint => 'Пошук дописів';

  @override
  String get threadSearchFailed => 'Не вдалося виконати пошук у коментарях.';

  @override
  String get threadPostFailed => 'Не вдалося надіслати коментар.';

  @override
  String get threadSearchComments => 'Пошук коментарів';

  @override
  String threadTitleWithChannel(String channel) {
    return 'Коментарі · $channel';
  }

  @override
  String get threadNoDiscussion =>
      'У цього каналу немає групи для обговорення, тому дописи не можна коментувати.';

  @override
  String get threadLoadFailed => 'Не вдалося завантажити коментарі.';

  @override
  String get threadSearching => 'Пошук…';

  @override
  String get threadNoComments => 'Коментарів ще немає.';

  @override
  String get threadWriteComment => 'Напишіть коментар';

  @override
  String get threadSend => 'Надіслати';

  @override
  String threadCommentsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Знайдено $count коментаря',
      many: 'Знайдено $count коментарів',
      few: 'Знайдено $count коментарі',
      one: 'Знайдено $count коментар',
    );
    return '$_temp0';
  }

  @override
  String get threadReply => 'Відповісти';

  @override
  String get threadCopy => 'Копіювати';

  @override
  String get threadEdit => 'Змінити';

  @override
  String get threadEditMessage => 'Змінити повідомлення';

  @override
  String threadReplyTo(String name) {
    return 'Відповідь для $name';
  }

  @override
  String get threadYou => 'себе';

  @override
  String get threadDeleteTitle => 'Видалити повідомлення';

  @override
  String get threadDeleteBody =>
      'Ви дійсно хочете видалити це повідомлення для всіх?';

  @override
  String get threadEditFailed => 'Не вдалося змінити коментар.';

  @override
  String get threadDeleteFailed => 'Не вдалося видалити коментар.';

  @override
  String get threadJoinNeeded =>
      'Коментувати тут можуть лише учасники групи обговорення. Приєднайтеся до групи в Telegram, щоб писати.';

  @override
  String get threadRestricted =>
      'Адміни групи заборонили вам надсилати повідомлення.';

  @override
  String threadSlowMode(String time) {
    return 'Діє повільний режим. Ви зможете написати через $time.';
  }

  @override
  String get threadSending => 'Надсилається';

  @override
  String get threadNotSent => 'Не надіслано';

  @override
  String get threadDeletedMessage => 'Видалене повідомлення';

  @override
  String get threadLoadOlder => 'Завантажити старіші коментарі';

  @override
  String get threadUnreadDivider => 'Непрочитані коментарі';

  @override
  String get threadDiscussionStarted => 'Початок обговорення';

  @override
  String get postDayToday => 'Сьогодні';

  @override
  String get postDayYesterday => 'Вчора';

  @override
  String get listDatePattern => 'dd MMM';

  @override
  String get postDayPattern => 'd MMMM';

  @override
  String get postDayYearPattern => 'd MMMM y';

  @override
  String get linkViewChannel => 'Відкрити канал';

  @override
  String get linkViewGroup => 'Переглянути групу';

  @override
  String get linkViewMessage => 'До повідомлення';

  @override
  String get linkSendMessage => 'Надіслати повідомлення';

  @override
  String get linkOpenBot => 'Відкрити бота';

  @override
  String get linkViewBackground => 'Переглянути шпалери';

  @override
  String get linkViewTheme => 'Переглянути тему';

  @override
  String get linkViewStickers => 'Переглянути набір';

  @override
  String get linkJoinVideoChat => 'Увійти як слухач';

  @override
  String get linkViewStory => 'Переглянути історію';

  @override
  String get linkBoost => 'Зарядити';

  @override
  String get linkViewChatFolder => 'Переглянути папку';

  @override
  String get linkOpenApp => 'Запустити';

  @override
  String get mediaLocationOpens => 'Геопозиція, відкривається на карті';

  @override
  String get mediaVenueOpens => 'Місце, відкривається на карті';

  @override
  String get mediaNoMapApp =>
      'На цьому телефоні немає застосунку, що відкриває карту.';

  @override
  String mediaChecklistDone(int done, int total) {
    return 'Виконано $done з $total';
  }

  @override
  String get postNoAppForFile =>
      'На цьому телефоні немає застосунку, що відкриває цей файл.';

  @override
  String get postSaveToDownloads => 'Зберегти в Завантаження';

  @override
  String get postSaveToMusic => 'Зберегти до Музики';

  @override
  String postSavedToGallery(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count збережено до галереї.',
      many: '$count збережено до галереї.',
      few: '$count збережено до галереї.',
      one: 'Збережено до галереї.',
    );
    return '$_temp0';
  }

  @override
  String postSavedToDownloads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлу збережено в Завантаженнях.',
      many: '$count файлів збережено в Завантаженнях.',
      few: '$count файли збережено в Завантаженнях.',
      one: '$count файл збережено в Завантаженнях.',
    );
    return '$_temp0';
  }

  @override
  String postSavedToMusic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count аудіо збережено до Музики.',
      many: '$count аудіо збережено до Музики.',
      few: '$count аудіо збережено до Музики.',
      one: 'Аудіо збережено до Музики.',
    );
    return '$_temp0';
  }

  @override
  String get postReport => 'Поскаржитися';

  @override
  String get postReportHint => 'Коментар...';

  @override
  String get postReportSend => 'Надіслати скаргу';

  @override
  String get postReportSent =>
      'Дякуємо! Вашу скаргу розгляне команда Telegram.';

  @override
  String get postReportFailed => 'Не вдалося надіслати скаргу.';

  @override
  String get postPinned => 'Прикріплено';

  @override
  String get mediaCancelDownload => 'Скасувати завантаження';

  @override
  String mediaLoadedOf(String loaded, String total) {
    return '$loaded / $total';
  }

  @override
  String get mediaCoverSpoiler => 'Спойлер. Торкніться, щоб показати';

  @override
  String get mediaCoverSensitive => 'Вміст 18+. Торкніться, щоб показати';

  @override
  String get mediaSensitiveLabel => '18+';

  @override
  String get mediaSensitiveQuestion =>
      'Це медіа може містити матеріали делікатного характеру, призначені лише для дорослих. Ви все ще хочете його переглянути?';

  @override
  String get mediaSensitiveView => 'Переглянути';

  @override
  String get quoteExpand => 'Показати всю цитату';

  @override
  String get quoteCollapse => 'Згорнути цитату';

  @override
  String postDayJumpToStart(String day) {
    return '$day. Перейти до початку дня';
  }

  @override
  String get calendarTitle => 'Календар';

  @override
  String calendarDayWithMedia(String day) {
    return '$day, із зображенням';
  }

  @override
  String postDayJumpToDate(String day) {
    return '$day. Перейти до дати';
  }

  @override
  String get postCopyText => 'Копіювати текст';

  @override
  String get postProtected =>
      'Копіювати та пересилати вміст каналу не дозволено.';

  @override
  String get postSaveToSavedMessages => 'Зберегти до Збереженого';

  @override
  String get postMinimize => 'Згорнути';

  @override
  String get postAutoplaySettings =>
      'Налаштування автовідтворення та завантаження';

  @override
  String postMinimizedSemantics(String channel, String words, String time) {
    return 'Згорнутий допис каналу $channel: $words, $time';
  }

  @override
  String postChannelInfoOf(String name) {
    return 'Профіль каналу $name';
  }

  @override
  String get postHiddenAccount => 'прихованого акаунта';

  @override
  String postForwardedFrom(String name) {
    return 'Переслано від $name';
  }

  @override
  String postForwardedFromOpen(String name) {
    return 'Переслано від $name. Відкрити оригінал';
  }

  @override
  String postInReplyTo(String name) {
    return 'У відповідь $name';
  }

  @override
  String postInReplyToOpen(String name) {
    return 'У відповідь $name. Перейти до цього допису';
  }

  @override
  String get postEdited => 'змінено';

  @override
  String postCommentCount(int count, String shown) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shown коментаря',
      many: '$shown коментарів',
      few: '$shown коментарі',
      one: '$shown коментар',
    );
    return '$_temp0';
  }

  @override
  String get postCommentsUnread => 'Нові коментарі';

  @override
  String get postLeaveComment => 'Коментувати';

  @override
  String get postReactionsLoadFailed => 'Не вдалося завантажити реакції.';

  @override
  String get postReactionsNotAllowed => 'У цьому каналі реакції вимкнено.';

  @override
  String get postDownloadFailed =>
      'Не вдалося завантажити. Натисніть, щоб повторити.';

  @override
  String get postDownloading => 'Завантаження…';

  @override
  String get postTapToDownload => 'Натисніть, щоб завантажити';

  @override
  String postFileTapToDownload(String size) {
    return '$size · натисніть, щоб завантажити';
  }

  @override
  String get postOnThisDevice => 'На цьому пристрої';

  @override
  String get postOpenWith => 'Відкрити в…';

  @override
  String get postPhotoOpensFullScreen => 'Фото, відкривається на весь екран';

  @override
  String get postPlay => 'Відтворити';

  @override
  String get sharedMediaNoChannels => 'Каналів поки немає.';

  @override
  String get sharedMediaLoadFailed => 'Не вдалося завантажити медіа.';

  @override
  String get sharedMediaEmpty => 'Тут поки нічого немає.';

  @override
  String sharedMediaGifTile(String day) {
    return 'GIF, $day';
  }

  @override
  String sharedMediaVideoTile(String duration, String day) {
    return 'Відео $duration, $day';
  }

  @override
  String sharedMediaPhotoTile(String day) {
    return 'Фото, $day';
  }

  @override
  String sharedMediaPostTile(String day) {
    return 'Допис, $day';
  }

  @override
  String sharedMediaNoAppCanOpen(String link) {
    return 'Жоден застосунок не може відкрити $link';
  }

  @override
  String get channelInfoTitle => 'Профіль каналу';

  @override
  String get channelInfoQrCode => 'QR-код';

  @override
  String get channelInfoLinkCopied => 'Посилання скопійовано';

  @override
  String channelInfoSubscribers(int count, String shown) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shown підписника',
      many: '$shown підписників',
      few: '$shown підписники',
      one: '$shown підписник',
    );
    return '$_temp0';
  }

  @override
  String get channelInfoChannel => 'Канал';

  @override
  String get channelInfoLoadFailed => 'Не вдалося завантажити дані каналу.';

  @override
  String get channelInfoSimilarChannels => 'Схожі канали';

  @override
  String get homeTabFeeds => 'Стрічки';

  @override
  String get homeTabAllChannels => 'Усі канали';

  @override
  String get homeSearchPosts => 'Шукати дописи';

  @override
  String get homeSearchHint => 'Пошук в усіх каналах';

  @override
  String get homeSearchChannelNotInList =>
      'Цього каналу немає у вашому списку.';

  @override
  String get homeMarkAllAsRead => 'Позначити всі прочитаними';

  @override
  String get homeNothingToMarkRead => 'Усе вже прочитано.';

  @override
  String homeChannelsMarkedRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count каналу позначено прочитаними.',
      many: '$count каналів позначено прочитаними.',
      few: '$count канали позначено прочитаними.',
      one: '$count канал позначено прочитаним.',
    );
    return '$_temp0';
  }

  @override
  String get homeFolderCreateFeed => 'Створити стрічку з папки';

  @override
  String get homeRulesHintTitle => 'Сповіщення ще не налаштовано';

  @override
  String get homeRulesHintDismiss => 'Приховати';

  @override
  String get homeRulesHintBody =>
      'Цей застосунок не дублює сповіщення Telegram. Правило стрічки стежить у її каналах за вибраними вами словами, сповіщає вас і може прочитати допис вголос.';

  @override
  String get homeRulesHintAction => 'Налаштувати правила';

  @override
  String homeUnreadBadge(int count) {
    return 'Непрочитаних: $count';
  }

  @override
  String get homeWaitingForNetwork => 'Очікування мережі…';

  @override
  String get homeConnecting => 'Зʼєднання…';

  @override
  String get homeConnectingToProxy => 'Зʼєднання з проксі…';

  @override
  String get homeUpdating => 'Оновлення…';

  @override
  String get feedsNewFeed => 'Нова стрічка';

  @override
  String get feedsRenameFeed => 'Перейменувати стрічку';

  @override
  String get feedsNameLabel => 'Назва';

  @override
  String get feedsCreate => 'Створити';

  @override
  String get feedsEmptyFeed => 'Порожня стрічка';

  @override
  String get feedsEmptyFeedSubtitle => 'Назвіть її, потім виберіть канали';

  @override
  String get feedsFromFolder => 'З папки';

  @override
  String feedsChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count каналу',
      many: '$count каналів',
      few: '$count канали',
      one: '$count канал',
    );
    return '$_temp0';
  }

  @override
  String feedsChannelsWithNews(int fresh, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count каналу',
      many: '$count каналів',
      few: '$count каналів',
      one: '$count каналу',
    );
    return 'Нове в $fresh з $_temp0';
  }

  @override
  String feedsCreatedFromFolder(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count каналу',
      many: '$count каналами',
      few: '$count каналами',
      one: '$count каналом',
    );
    return 'Стрічку «$name» створено з $_temp0.';
  }

  @override
  String feedsNothingToMarkRead(String name) {
    return 'У стрічці «$name» усе вже прочитано.';
  }

  @override
  String feedsMarkedRead(String name) {
    return 'Стрічку «$name» позначено прочитаною.';
  }

  @override
  String feedsDeleteTitle(String name) {
    return 'Видалити стрічку «$name»?';
  }

  @override
  String feedsDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Буде видалено стрічку разом із $count правила і збереженими позиціями читання.',
      many:
          'Буде видалено стрічку разом із $count правилами і збереженими позиціями читання.',
      few:
          'Буде видалено стрічку разом із $count правилами і збереженими позиціями читання.',
      one:
          'Буде видалено стрічку разом із $count правилом і збереженими позиціями читання.',
      zero: 'Буде видалено стрічку та збережені позиції читання.',
    );
    return '$_temp0 Підписки на канали в Telegram залишаться.';
  }

  @override
  String get feedsCountersRefreshFailed => 'Не вдалося оновити лічильники.';

  @override
  String get feedsEmptyTitle => 'Стрічок поки немає';

  @override
  String get feedsEmptyMessage =>
      'Стрічка — це кілька каналів, які ви читаєте як один потік дописів. Правила стрічки сповіщають вас про важливі для вас дописи; без них застосунок мовчить.';

  @override
  String get feedsEmptyAction => 'Створити стрічку';

  @override
  String get feedsEmptySecondary =>
      'Стрічку також можна створити з будь-якої вашої папки Telegram або через пункт «Додати до стрічки» в меню будь-якого каналу.';

  @override
  String get feedsEditChannels => 'Змінити канали';

  @override
  String get channelsInfo => 'Профіль каналу';

  @override
  String get channelsAddToFeed => 'Додати до стрічки';

  @override
  String get channelsAlreadyInFeed => 'Уже в цій стрічці';

  @override
  String channelsAddedToFeed(String channel, String feed) {
    return '$channel додано до стрічки «$feed».';
  }

  @override
  String channelsAlbumPhotos(int count) {
    return '$count фото';
  }

  @override
  String channelsAlbumVideos(int count) {
    return '$count відео';
  }

  @override
  String channelsAlbumFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлу',
      many: '$count файлів',
      few: '$count файли',
      one: '$count файл',
    );
    return '$_temp0';
  }

  @override
  String channelsAlbumMusic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count музичного файлу',
      many: '$count музичних файлів',
      few: '$count музичні файли',
      one: '$count музичний файл',
    );
    return '$_temp0';
  }

  @override
  String channelsAlbumMedia(int count) {
    return '$count медіа';
  }

  @override
  String get channelsVerified => 'Підтверджено';

  @override
  String get channelsMarkAsUnread => 'Позначити як непрочитане';

  @override
  String get channelsMarkedUnread => 'Позначено як непрочитане';

  @override
  String get channelsMarkUnreadFailed =>
      'Не вдалося позначити канал як непрочитаний.';

  @override
  String get channelsArchive => 'Архів';

  @override
  String get channelsArchiveSubtitle => 'Канали, які ви архівували в Telegram';

  @override
  String get channelsArchiveEmpty => 'Немає архівованих каналів.';

  @override
  String get channelsArchiveOpenFailed => 'Не вдалося відкрити архів.';

  @override
  String get channelsEmptyAll =>
      'Каналів поки немає. Підпишіться на канали в Telegram, і вони зʼявляться тут.';

  @override
  String get channelsEmptyFolder => 'У цій папці немає каналів.';

  @override
  String get channelsEmpty => 'Тут немає каналів.';

  @override
  String get channelsLoadFailed => 'Не вдалося завантажити канали.';

  @override
  String get channelsRefreshFailed => 'Не вдалося оновити канали.';

  @override
  String channelsNoMatch(String query) {
    return 'Немає каналів за запитом «$query».';
  }

  @override
  String get channelsSearchHint => 'Пошук каналів';

  @override
  String get logOutTitle => 'Вийти з акаунта?';

  @override
  String get logOutMessage =>
      'Ваші стрічки, правила, налаштування та ключ API для ШІ буде видалено з цього пристрою, а синхронізацію з Google Drive вимкнено. Якщо синхронізація була ввімкнена, копія залишиться у вашому Google Drive.';

  @override
  String get logOutAction => 'Вийти';

  @override
  String get bannerStop => 'Зупинити';

  @override
  String get bannerStopAndClearQueue => 'Зупинити й очистити чергу';

  @override
  String get bannerPaused =>
      'Сповіщення призупинено. Правила не надсилають сповіщень і нічого не читають вголос.';

  @override
  String get bannerResume => 'Відновити';

  @override
  String get bannerReadingAloud => 'Читання вголос';

  @override
  String bannerReadingAloudChannel(String channel) {
    return 'Читання вголос: $channel';
  }

  @override
  String bannerReadingQueue(String line, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count допису',
      many: '$count дописів',
      few: '$count дописи',
      one: '$count допис',
    );
    return '$line. У черзі ще $_temp0.';
  }

  @override
  String get bannerPauseNotifications => 'Призупинити сповіщення';

  @override
  String get bannerResumeNotifications => 'Відновити сповіщення';

  @override
  String get errorRateLimited =>
      'Telegram обмежив кількість запитів від цього акаунта. Зачекайте хвилину й спробуйте ще раз.';

  @override
  String get errorPhoneNumberInvalid => 'Некоректний номер телефону.';

  @override
  String get errorPhoneNumberBanned =>
      'Цей номер телефону заблоковано в Telegram.';

  @override
  String get errorPhoneNumberFlood =>
      'Для цього номера сьогодні запитано забагато кодів. Спробуйте завтра.';

  @override
  String get errorPhoneNumberOccupied =>
      'Цей номер уже привʼязаний до іншого акаунта.';

  @override
  String get errorCodeInvalid => 'Неправильний код.';

  @override
  String get errorCodeExpired => 'Термін дії коду минув. Запросіть новий.';

  @override
  String get errorPasswordInvalid => 'Неправильний пароль.';

  @override
  String get errorPasswordRecoveryUnavailable =>
      'Для цього акаунта не вказано ел. пошту для відновлення, тому скинути пароль тут не можна.';

  @override
  String get errorApiIdInvalid =>
      'Ця збірка не має дійсних api_id/api_hash для Telegram (див. README).';

  @override
  String get errorChannelUnknown => 'Telegram більше не знаходить цей канал.';

  @override
  String get errorChannelPrivate =>
      'Цей канал тепер приватний, або акаунт вийшов із нього.';

  @override
  String get errorPostGone => 'Цього допису більше не існує.';

  @override
  String get errorWriteForbidden => 'У цьому каналі акаунту заборонено писати.';

  @override
  String get errorBannedInChannel => 'Акаунт заблоковано в цьому каналі.';

  @override
  String get errorReactionInvalid => 'У цьому каналі така реакція недоступна.';

  @override
  String get errorConnectionClosed =>
      'Зʼєднання з Telegram розірвано. Спробуйте ще раз.';

  @override
  String get feedEditorFallbackTitle => 'Стрічка';

  @override
  String get feedEditorRenameTitle => 'Перейменувати стрічку';

  @override
  String get feedEditorNameLabel => 'Назва';

  @override
  String get feedEditorTabChannels => 'Канали';

  @override
  String get feedEditorTabSharedMedia => 'Медіа';

  @override
  String get feedEditorAddChannel => 'Додати канал';

  @override
  String get feedEditorNewRule => 'Нове правило';

  @override
  String get feedEditorRemoveChannel => 'Вилучити';

  @override
  String feedEditorRemoveChannelTitle(String channel) {
    return 'Вилучити $channel зі стрічки?';
  }

  @override
  String feedEditorQuotedRuleName(String name) {
    return '«$name»';
  }

  @override
  String feedEditorRemoveChannelOneRule(String names) {
    return 'Правило $names стежить лише за цим каналом і буде видалене разом із ним.';
  }

  @override
  String feedEditorRemoveChannelRules(String names) {
    return 'Правила $names стежать лише за цим каналом і будуть видалені разом із ним.';
  }

  @override
  String feedEditorChannelRemoved(String channel) {
    return '$channel вилучено зі стрічки';
  }

  @override
  String get feedEditorNoChannelsTitle => 'Каналів ще немає';

  @override
  String get feedEditorNoChannelsMessage =>
      'Додайте канали, на які підписаний ваш акаунт Telegram. Застосунок ніколи не підписується на канали за вас.';

  @override
  String get feedEditorChannelLeft =>
      'Ви покинули канал у Telegram; історія лишається доступною';

  @override
  String get feedEditorSearchJoinedChannels => 'Пошук серед ваших каналів';

  @override
  String get feedEditorHideChannelsInFeeds =>
      'Приховати канали, які вже є в стрічках';

  @override
  String get feedEditorAllChannelsInFeed =>
      'Усі канали, на які ви підписані, уже є в цій стрічці.';

  @override
  String feedEditorRestInOtherFeeds(String option) {
    return 'Решта є в інших стрічках. Зніміть позначку «$option», щоб побачити їх.';
  }

  @override
  String feedEditorNoChannelMatches(String query) {
    return 'Немає каналів за запитом «$query».';
  }

  @override
  String get feedEditorTickChannels => 'Позначте канали, які хочете додати';

  @override
  String feedEditorChannelsTicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Позначено $count каналу',
      many: 'Позначено $count каналів',
      few: 'Позначено $count канали',
      one: 'Позначено $count канал',
    );
    return '$_temp0';
  }

  @override
  String get filterTileTitle => 'Показувати';

  @override
  String get filterSheetTitle => 'Показувати в цій стрічці';

  @override
  String get filterPosts => 'Дописи';

  @override
  String get filterPostsAll => 'Усі';

  @override
  String get filterPostsWithMedia => 'З медіа';

  @override
  String get filterPostsTextOnly => 'Лише текст';

  @override
  String get filterMediaTypes => 'Типи медіа';

  @override
  String get filterMediaTypesNote =>
      'Не вибирайте жодного, щоб дозволити всі типи.';

  @override
  String get filterKindPhotos => 'фото';

  @override
  String get filterKindVideos => 'відео';

  @override
  String get filterKindGifs => 'GIF';

  @override
  String get filterKindAudio => 'аудіо';

  @override
  String get filterKindVoice => 'голосові повідомлення';

  @override
  String get filterKindFiles => 'файли';

  @override
  String get filterKindOther => 'інше (опитування, наліпки, …)';

  @override
  String get filterVideoLength => 'Тривалість відео';

  @override
  String get filterVideoAnyLength => 'Будь-яка';

  @override
  String filterFromSeconds(int seconds) {
    return 'Від $seconds с';
  }

  @override
  String filterFromMinutes(int minutes) {
    return 'Від $minutes хв';
  }

  @override
  String get filterTextPosts => 'Текстові дописи';

  @override
  String get filterTextAnyLength => 'Будь-які';

  @override
  String filterFromCharacters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Від $count символу',
      many: 'Від $count символів',
      few: 'Від $count символів',
      one: 'Від $count символу',
    );
    return '$_temp0';
  }

  @override
  String get filterTextContent => 'Текст допису';

  @override
  String get filterTextContentNote =>
      'Показуються лише дописи, слова яких відповідають умові, як у правилі. Слово з позначкою «Не містить» приховує дописи, у яких воно є.';

  @override
  String get filterWholePost => 'Показувати допис повністю';

  @override
  String get filterWholePostNote =>
      'Допис із кількома фото чи відео показується повністю, з підписом, щойно хоча б одне з них проходить фільтр. Якщо вимкнено, показуються лише частини, що проходять фільтр.';

  @override
  String get filterShowMinimized => 'Показувати згорнутими';

  @override
  String get filterShowMinimizedNote =>
      'Дописи, які стрічка відсіює, лишаються в ній, кожен одним рядком, і відкриваються дотиком. Вони все одно вважаються прихованими.';

  @override
  String get filterHiddenCountAsRead =>
      'Дописи, які ця стрічка приховує, вважаються прочитаними, і правила не сповіщають про них, якщо їх не показує інша стрічка з тим самим каналом.';

  @override
  String get filterShowEverything => 'Показувати все';

  @override
  String get filterDescribeEverything => 'Усе';

  @override
  String get filterDescribeWithMedia => 'з медіа';

  @override
  String get filterDescribeTextOnly => 'лише текст';

  @override
  String filterDescribeVideosFromSeconds(int seconds) {
    return 'відео від $seconds с';
  }

  @override
  String filterDescribeVideosFromMinutes(int minutes) {
    return 'відео від $minutes хв';
  }

  @override
  String filterDescribeTextFrom(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'текст від $count символу',
      many: 'текст від $count символів',
      few: 'текст від $count символів',
      one: 'текст від $count символу',
    );
    return '$_temp0';
  }

  @override
  String filterDescribeText(String condition) {
    return 'текст: $condition';
  }

  @override
  String get filterDescribeMatchingParts => 'лише відповідні частини';

  @override
  String get filterDescribeRestMinimized => 'решта згорнута';

  @override
  String get loginTelegramRefused => 'Telegram відхилив запит.';

  @override
  String get loginSomethingWentWrong => 'Щось пішло не так. Спробуйте ще раз.';

  @override
  String get loginShowPassword => 'Показати';

  @override
  String get loginHidePassword => 'Приховати';

  @override
  String get loginNewCodeSent => 'Новий код надіслано.';

  @override
  String get loginPhoneTitle => 'Увійти в Telegram';

  @override
  String loginPhoneExplanation(String appName) {
    return '$appName читає канали, на які підписаний ваш акаунт Telegram. Введіть номер телефону цього акаунта в міжнародному форматі.';
  }

  @override
  String get loginPhoneNumber => 'Номер телефону';

  @override
  String get loginSendCode => 'Надіслати код';

  @override
  String get loginWithQrInstead => 'Увійти за QR-кодом';

  @override
  String get loginCodeTitle => 'Введіть код';

  @override
  String loginCodeExplanation(String phoneNumber) {
    return 'Telegram надіслав код на номер $phoneNumber (в SMS або на інший пристрій, де ви вже увійшли).';
  }

  @override
  String get loginCode => 'Код';

  @override
  String get loginResendCode => 'Надіслати код ще раз';

  @override
  String get loginChangeNumber => 'Змінити номер';

  @override
  String get loginEmailTitle => 'Ваша ел. пошта';

  @override
  String get loginEmailExplanation =>
      'Telegram просить для цього акаунта адресу ел. пошти. На неї надходитимуть коди щоразу, як ви входите з нового пристрою.';

  @override
  String get loginEmail => 'Адреса ел. пошти';

  @override
  String get loginEmailCodeTitle => 'Перевірте ел. пошту';

  @override
  String loginEmailCodeExplanation(String email) {
    return 'Telegram надіслав код на $email. Не забудьте перевірити теку зі спамом.';
  }

  @override
  String get loginUnsupportedExplanation =>
      'Telegram вимагає придбати Premium, перш ніж дозволить вхід із цим номером, а цей застосунок цього не вміє. Спершу увійдіть в офіційному застосунку Telegram або скористайтеся іншим номером.';

  @override
  String get loginPasswordTitle => 'Двоетапна перевірка';

  @override
  String get loginPasswordExplanation =>
      'Ваш акаунт захищений хмарним паролем.';

  @override
  String loginPasswordExplanationWithHint(String hint) {
    return 'Ваш акаунт захищений хмарним паролем. Підказка: $hint';
  }

  @override
  String get loginPassword => 'Пароль';

  @override
  String get loginPasswordForgotten =>
      'Забули пароль? Хмарний пароль можна скинути лише в офіційному застосунку Telegram: Налаштування > Приватність і безпека.';

  @override
  String get loginNewAccountTitle => 'Новий акаунт';

  @override
  String get loginNewAccountExplanation =>
      'З цим номером ще немає акаунта Telegram. Вкажіть імʼя, щоб створити його.';

  @override
  String get loginFirstName => 'Імʼя';

  @override
  String get loginCreateAccount => 'Створити акаунт';

  @override
  String get loginQrTitle => 'Вхід за QR-кодом';

  @override
  String get loginQrExplanation =>
      'У Telegram на телефоні відкрийте Налаштування > Пристрої > Додати пристрій і відскануйте цей код. Він оновлюється автоматично.';

  @override
  String get loginQrBackFailed => 'Не вдалося повернутися до номера телефону.';

  @override
  String get loginWithPhoneInstead => 'Увійти за номером телефону';

  @override
  String loginUseOtherAccount(String account) {
    return 'Повернутися до акаунта $account';
  }

  @override
  String get conditionErrorStoredUnreadable =>
      'Збережену умову не вдалося прочитати; напишіть її заново.';

  @override
  String get conditionErrorTooNested =>
      'Умова надто складна для конструктора; редагуйте її як текст.';

  @override
  String get conditionErrorUnreadable => 'Цю умову не вдається прочитати.';

  @override
  String get conditionErrorExpectedTerm => 'На місці курсора має бути слово.';

  @override
  String get conditionErrorExpectedBracket =>
      'На місці курсора бракує дужки «)».';

  @override
  String conditionErrorUnexpected(String symbol) {
    return 'Зайвий символ «$symbol» на місці курсора.';
  }

  @override
  String get conditionErrorUnterminatedQuote =>
      'На місці курсора бракує закривних лапок.';

  @override
  String get conditionErrorDanglingEscape =>
      'На місці курсора після «\\» бракує символу.';

  @override
  String get conditionErrorEmptyTerm => 'На місці курсора порожні лапки.';

  @override
  String conditionErrorKeyword(String word) {
    return 'На місці курсора «$word» — ключове слово; щоб шукати саме це слово, візьміть його в лапки.';
  }

  @override
  String get conditionModeBuilder => 'Конструктор';

  @override
  String get conditionModeText => 'Текст';

  @override
  String get conditionTextHelper =>
      'Слова або \"фрази\" з AND, OR, NOT і дужками.';

  @override
  String get conditionSyntaxTooltip => 'Синтаксис';

  @override
  String get conditionSyntaxTitle => 'Як записати умову';

  @override
  String get conditionSyntaxWord => 'це слово будь-де в тексті';

  @override
  String get conditionSyntaxPhrase => 'ці слова поруч, саме в такому порядку';

  @override
  String get conditionSyntaxAnd => 'мають бути обидва';

  @override
  String get conditionSyntaxOr => 'достатньо одного з них';

  @override
  String get conditionSyntaxNot => 'у дописі цього слова не має бути';

  @override
  String get conditionSyntaxBrackets => 'дужки групують частини';

  @override
  String get conditionSyntaxSubstring =>
      'також усередині довших слів, як-от «rates»';

  @override
  String get conditionSyntaxCase =>
      'саме таке написання, з урахуванням великих літер';

  @override
  String get conditionAddTerm => 'Додати слово';

  @override
  String get conditionOr => 'АБО';

  @override
  String get conditionAnd => 'І';

  @override
  String get conditionAndAnotherWord => 'І ще слово';

  @override
  String get conditionOrAlternative => 'АБО інший варіант';

  @override
  String get conditionTermHint => 'слово або фраза';

  @override
  String get conditionTermHintNegated => 'слово, якого не має бути';

  @override
  String get conditionMustNotContain => 'Не містить';

  @override
  String get conditionWholeWord => 'Ціле слово';

  @override
  String get conditionMatchCase => 'Враховувати регістр';

  @override
  String get ruleDiscardTitle => 'Відхилити зміни?';

  @override
  String get ruleDiscardMessage => 'Зміни в цьому правилі не збережено.';

  @override
  String get ruleErrorNoName => 'Вкажіть назву правила.';

  @override
  String get ruleErrorNoFeed =>
      'Правило належить до стрічки: спершу створіть її.';

  @override
  String get scheduleErrorNoDays =>
      'Виберіть хоча б один день, інакше правило ніколи не сповіщатиме.';

  @override
  String get ruleNotifyAskTitle => 'Дозволити застосунку надсилати сповіщення?';

  @override
  String get ruleNotifyAskMessage =>
      'Це правило сповіщає про дописи, які йому відповідають, і для цього потрібен дозвіл Android. Без нього правило все одно працюватиме, але мовчки.';

  @override
  String get ruleDndAskTitle =>
      'Показувати термінові дописи в режимі «Не турбувати»?';

  @override
  String get ruleDndAskMessage =>
      'Термінові правила можуть сповіщати навіть у режимі «Не турбувати», але Android має дозволити це застосунку. Відкрити налаштування зараз? Правило працюватиме в будь-якому разі.';

  @override
  String ruleDeleteTitle(String name) {
    return 'Видалити «$name»?';
  }

  @override
  String ruleDryRunScopeChannels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'з $count каналу',
      many: 'з $count каналів',
      few: 'з $count каналів',
      one: 'з $count каналу',
    );
    return '$_temp0';
  }

  @override
  String ruleDryRunScopeOfTotal(int total, int limit) {
    return 'із $total (перевіряються перші $limit)';
  }

  @override
  String ruleDryRunScopeFailed(int count) {
    return '(не вдалося прочитати: $count)';
  }

  @override
  String ruleDryRunChecked(String scope) {
    return 'Перевірено останні дописи $scope.';
  }

  @override
  String ruleDryRunAiNone(int checked, int passed, int scanned) {
    String _temp0 = intl.Intl.pluralLogic(
      checked,
      locale: localeName,
      other:
          'ШІ не підтвердив жодного з $checked найновішого допису, який перевірив ($passed з останніх $scanned пройшли фільтр ключових слів).',
      many:
          'ШІ не підтвердив жодного з $checked найновіших дописів, які перевірив ($passed з останніх $scanned пройшли фільтр ключових слів).',
      few:
          'ШІ не підтвердив жодного з $checked найновіших дописів, які перевірив ($passed з останніх $scanned пройшли фільтр ключових слів).',
      one:
          'ШІ не підтвердив жодного з $checked найновішого допису, який перевірив ($passed з останніх $scanned пройшли фільтр ключових слів).',
    );
    return '$_temp0';
  }

  @override
  String ruleDryRunAiMatched(int matched, int checked) {
    String _temp0 = intl.Intl.pluralLogic(
      checked,
      locale: localeName,
      other:
          'ШІ підтвердив $matched з $checked найновішого допису, який перевірив:',
      many:
          'ШІ підтвердив $matched з $checked найновіших дописів, які перевірив:',
      few:
          'ШІ підтвердив $matched з $checked найновіших дописів, які перевірив:',
      one:
          'ШІ підтвердив $matched з $checked найновішого допису, який перевірив:',
    );
    return '$_temp0';
  }

  @override
  String ruleDryRunAiFailed(String message) {
    return 'Перевірка ШІ не вдалася: $message';
  }

  @override
  String ruleDryRunNoMatch(int scanned) {
    String _temp0 = intl.Intl.pluralLogic(
      scanned,
      locale: localeName,
      other: 'Серед $scanned останнього допису збігів немає.',
      many: 'Серед $scanned останніх дописів збігів немає.',
      few: 'Серед $scanned останніх дописів збігів немає.',
      one: 'Серед $scanned останнього допису збігів немає.',
    );
    return '$_temp0';
  }

  @override
  String ruleDryRunMatches(int matched, int scanned) {
    return 'Збіги серед останніх дописів: $matched з $scanned';
  }

  @override
  String get ruleNew => 'Нове правило';

  @override
  String get ruleEditTitle => 'Правило';

  @override
  String get ruleNameLabel => 'Назва';

  @override
  String get ruleEnabledTitle => 'Увімкнено';

  @override
  String get ruleEnabledSubtitle =>
      'Вимкнене правило зберігається, але не сповіщає';

  @override
  String get ruleFeedLabel => 'Стрічка';

  @override
  String get ruleChannelsLabel => 'Канали';

  @override
  String get ruleEveryChannelOfFeed => 'Усі канали стрічки';

  @override
  String get ruleConditionTitle => 'Умова';

  @override
  String get ruleNoConditionNote =>
      'Умови немає: сповіщення надходитиме про кожен новий допис із каналів цього правила. Додайте слова, щоб отримувати сповіщення лише про деякі з них.';

  @override
  String get semanticNoKeywordsNote =>
      'Ключових слів немає: кожен новий допис із каналів цього правила надсилається ШІ. Додайте слова, щоб надсилати лише дописи, які їх містять.';

  @override
  String get semanticAfterKeywordsNote =>
      'ШІ перевіряє лише дописи, що пройшли фільтр цих ключових слів.';

  @override
  String get ruleDryRunTesting => 'Перевірка…';

  @override
  String get ruleDryRunButton => 'Перевірити на останніх дописах';

  @override
  String get ruleNotificationTitle => 'Сповіщення';

  @override
  String get rulePrioritySilent => 'Тихий';

  @override
  String get rulePriorityNormal => 'Звичайний';

  @override
  String get rulePriorityUrgent => 'Терміновий';

  @override
  String get rulePrioritySilentInfo =>
      'Лише в панелі сповіщень, без звуку й вібрації.';

  @override
  String get rulePriorityNormalInfo =>
      'Спливає на екрані, зі звуком і вібрацією, налаштованими в розділі «Сповіщення та звуки».';

  @override
  String get rulePriorityUrgentInfo =>
      'Спливає на екрані й сповіщає навіть у режимі «Не турбувати», якщо Android це дозволяє.';

  @override
  String get ruleReadAloud => 'Читати допис вголос';

  @override
  String get scheduleSwitch => 'Лише в певний час';

  @override
  String get scheduleMon => 'пн';

  @override
  String get scheduleTue => 'вт';

  @override
  String get scheduleWed => 'ср';

  @override
  String get scheduleThu => 'чт';

  @override
  String get scheduleFri => 'пт';

  @override
  String get scheduleSat => 'сб';

  @override
  String get scheduleSun => 'нд';

  @override
  String scheduleFrom(String time) {
    return 'З $time';
  }

  @override
  String scheduleTo(String time) {
    return 'До $time';
  }

  @override
  String get scheduleNextDay => '(наступного дня)';

  @override
  String get semanticAlsoAsk => 'Також питати ШІ';

  @override
  String get semanticAlsoAskSubtitle =>
      'Модель, підключена в Налаштуваннях, вирішує, чи йдеться в дописі про те, що ви описали.';

  @override
  String get semanticPromptLabel => 'Про що має бути допис';

  @override
  String get semanticPromptHint => 'Рішення центробанків щодо облікової ставки';

  @override
  String get semanticNotConfigured =>
      'Підключення до ШІ ще не налаштовано (Налаштування, Правила зі ШІ). Доти це правило пропускається.';

  @override
  String get rulesNoFeedsTitle => 'Стрічок ще немає';

  @override
  String get rulesNoFeedsMessage =>
      'Кожне правило належить до стрічки й стежить за її каналами. Спершу створіть стрічку, а потім додайте до неї правила.';

  @override
  String get rulesGoToFeeds => 'Перейти до стрічок';

  @override
  String get semanticSkippedTitle => 'Правила зі ШІ пропускаються';

  @override
  String semanticSkippedSubtitle(String message, String time) {
    return '$message (остання спроба о $time)';
  }

  @override
  String get ruleScopeChannelLeft => 'Канал, якого вже немає в стрічці';

  @override
  String get rulesEmptyTitle => 'Правил ще немає';

  @override
  String get rulesEmptyNoFeeds =>
      'Правила належать до стрічок. Спершу створіть стрічку, а потім додайте до неї правила.';

  @override
  String get rulesEmptyFeed =>
      'Правило стежить за каналами цієї стрічки або за одним із них і сповіщає вас, за бажання читаючи допис вголос. Вкажіть слова для пошуку або залиште умову порожньою, щоб отримувати сповіщення про кожен допис стрічки.';

  @override
  String get rulesEmptyAll =>
      'У кожної стрічки свої правила: правило стежить за каналами стрічки або за одним із них і сповіщає вас, за бажання читаючи допис вголос.';

  @override
  String get ruleScopeEveryChannel => 'Усі канали';

  @override
  String get ruleTileUrgent => 'терміновий';

  @override
  String get ruleTileSilent => 'тихий';

  @override
  String get ruleTileReadAloud => 'читання вголос';

  @override
  String get ruleTileEveryPost => 'кожен допис';

  @override
  String get ruleTileInvalidCondition => '(помилка в умові)';

  @override
  String get ruleSemanticsUrgent => 'Термінове правило';

  @override
  String get ruleSemanticsSilent => 'Тихе правило';

  @override
  String get ruleSemanticsNormal => 'Звичайне правило';

  @override
  String semanticPreview(String prompt) {
    return 'ШІ: $prompt';
  }

  @override
  String semanticPreviewWithKeywords(String prompt, String keywords) {
    return 'ШІ: $prompt · лише якщо $keywords';
  }

  @override
  String get ruleBatteryBanner =>
      'Android може зупинити стеження у фоні, і тоді правила замовкнуть. Дозвольте застосунку ігнорувати оптимізацію батареї, щоб вони працювали далі.';

  @override
  String get semanticProblemNotSetUp =>
      'Підключення до ШІ не налаштовано в Налаштуваннях.';

  @override
  String semanticProblemUnreachable(String error) {
    return 'Не вдалося звʼязатися із сервером ШІ: $error';
  }

  @override
  String semanticProblemHttpStatus(int status, String error) {
    return 'Сервер ШІ відповів кодом $status: $error';
  }

  @override
  String get semanticProblemUnexpectedAnswer =>
      'Сервер ШІ надіслав неочікувану відповідь.';

  @override
  String get semanticProblemEmptyAnswer =>
      'Модель повернула порожню відповідь.';

  @override
  String get readAloudTitle => 'Читання вголос';

  @override
  String get readAloudPreview => 'Прослухати';

  @override
  String get readAloudPreviewText =>
      'Новий допис у каналі «Приклад». Так звучатимуть дописи.';

  @override
  String readAloudSpeed(String speed) {
    return 'Швидкість  ·  $speed×';
  }

  @override
  String readAloudSpeedSemantics(String speed) {
    return 'Швидкість $speed';
  }

  @override
  String readAloudPitch(String pitch) {
    return 'Тон  ·  $pitch';
  }

  @override
  String readAloudPitchSemantics(String pitch) {
    return 'Тон $pitch';
  }

  @override
  String get readAloudMaxLength => 'Максимальна довжина';

  @override
  String readAloudMaxLengthSubtitle(int maxChars) {
    String _temp0 = intl.Intl.pluralLogic(
      maxChars,
      locale: localeName,
      other: 'Дописи понад $maxChars символу обриваються словами «і далі»',
      many: 'Дописи понад $maxChars символів обриваються словами «і далі»',
      few: 'Дописи понад $maxChars символи обриваються словами «і далі»',
      one: 'Дописи понад $maxChars символ обриваються словами «і далі»',
    );
    return '$_temp0';
  }

  @override
  String get readAloudDefaultLanguage => 'Типова мова';

  @override
  String get readAloudDefaultLanguageSubtitle =>
      'Для дописів, мову яких не вдалося визначити';

  @override
  String get readAloudVoices => 'Голоси';

  @override
  String get readAloudNoVoices => 'Синтезатор мовлення не надав жодного голосу';

  @override
  String get readAloudNoVoicesSubtitle =>
      'Для всіх мов використовується типовий голос системи';

  @override
  String get readAloudUseDefaultVoice => 'Використовувати типовий голос';

  @override
  String get readAloudAddLanguage => 'Додати мову';

  @override
  String get readAloudOtherLanguagesFooter =>
      'Решту мов читає типовий голос телефону для кожної з них.';

  @override
  String get readAloudPhoneDefaultVoice => 'Типовий голос телефону';

  @override
  String get readAloudSearchLanguages => 'Пошук мов';

  @override
  String readAloudVoiceId(String id) {
    return 'Голос $id';
  }

  @override
  String get readAloudVoiceOnline => 'онлайн';

  @override
  String get readAloudVoiceFemale => 'Жіночий';

  @override
  String get readAloudVoiceMale => 'Чоловічий';

  @override
  String get notificationSettingsTitle => 'Сповіщення та звуки';

  @override
  String get notificationSettingsRestartTitle => 'Перезапустити застосунок?';

  @override
  String get notificationSettingsRestartStartsWatching =>
      'Стеження у фоні почнеться після перезапуску застосунку.';

  @override
  String get notificationSettingsRestartStopsWatching =>
      'Постійне сповіщення зникне після перезапуску застосунку.';

  @override
  String get notificationSettingsRestartDueStopsWatching =>
      'Постійне сповіщення зникне після перезапуску застосунку.';

  @override
  String get notificationSettingsRestartNow => 'Перезапустити зараз';

  @override
  String get notificationSettingsBlocked =>
      'Android блокує сповіщення цього застосунку, тож жодне правило не може вас сповістити.';

  @override
  String get notificationSettingsTurnOn => 'Увімкнути';

  @override
  String get notificationSettingsRuleNotifications => 'Сповіщення правил';

  @override
  String get notificationSettingsBadgeCounter => 'Лічильник на значку';

  @override
  String get notificationSettingsCountUnreadPosts =>
      'Рахувати непрочитані дописи';

  @override
  String get notificationSettingsCountFooter =>
      'Лічильники стрічок і вкладок папок показують кількість непрочитаних дописів. Якщо вимкнено, вони показують кількість каналів із непрочитаними дописами.';

  @override
  String get notificationSettingsBackground => 'Робота у фоні';

  @override
  String get notificationSettingsWatchInBackground =>
      'Стежити за каналами у фоні';

  @override
  String get notificationSettingsWatchInBackgroundSubtitle =>
      'Правила працюють, навіть коли застосунок закрито. Якщо вимкнути, постійне сповіщення зникне, а правила сповіщатимуть лише тоді, коли застосунок відкрито. Зміна набуде чинності після перезапуску застосунку.';

  @override
  String get notificationSettingsSystemSettings =>
      'Системні налаштування сповіщень';

  @override
  String notificationSettingsNoSoundPicker(String message) {
    return 'Вибір звуку недоступний: $message';
  }

  @override
  String get notificationSettingsNoSoundPickerOnDevice =>
      'На цьому пристрої немає вибору звуку.';

  @override
  String get notificationSettingsNormalSound => 'Звичайні правила: звук';

  @override
  String get notificationSettingsNormalVibrate => 'Звичайні правила: вібрація';

  @override
  String get notificationSettingsUrgentSound => 'Термінові правила: звук';

  @override
  String get notificationSettingsUrgentVibrate => 'Термінові правила: вібрація';

  @override
  String get notificationSettingsSystemDefaultSound => 'Типовий звук системи';

  @override
  String get notificationSettingsChosenSound => 'Вибраний звук';

  @override
  String get notificationSettingsUseDefaultSound => 'Використовувати типовий';

  @override
  String get notificationSettingsSilentRulesFooter =>
      'Тихі правила залишаються беззвучними.';

  @override
  String get privacyTitle => 'Приватність і безпека';

  @override
  String get privacySecurity => 'Безпека';

  @override
  String get privacyAppLockFooter =>
      'Після перерви застосунок запитує PIN-код або відбиток пальця чи обличчя, налаштовані на телефоні. Без цього будь-хто з розблокованим телефоном у руках може читати ваші канали.';

  @override
  String get appLockTitle => 'Код блокування';

  @override
  String appLockLocked(String appName) {
    return '$appName заблоковано';
  }

  @override
  String appLockUnlockReason(String appName) {
    return 'Розблокувати $appName';
  }

  @override
  String get appLockBiometricsUnavailable =>
      'Перевірка телефоном недоступна, введіть PIN-код.';

  @override
  String get appLockWrongPin => 'Неправильний PIN-код';

  @override
  String appLockTooManyTries(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds секунди',
      many: '$seconds секунд',
      few: '$seconds секунди',
      one: '$seconds секунду',
    );
    return 'Забагато спроб. Повторіть спробу через $_temp0.';
  }

  @override
  String get appLockShowContent => 'Дозволити знімки екрана';

  @override
  String get appLockShowContentSubtitle =>
      'Коли вимкнено, у перемикачі застосунків видно порожню картку, а знімки екрана заборонено, доки діє блокування';

  @override
  String get appLockPin => 'PIN-код';

  @override
  String get appLockUnlock => 'Розблокувати';

  @override
  String get appLockUseBiometrics => 'Розблокувати відбитком або обличчям';

  @override
  String get appLockRemoveTitle => 'Видалити код блокування?';

  @override
  String get appLockRemoveMessage =>
      'Тоді будь-хто з розблокованим телефоном у руках зможе читати ваші канали.';

  @override
  String get appLockTooShort => 'Щонайменше чотири цифри';

  @override
  String get appLockMismatch => 'PIN-коди не збігаються';

  @override
  String get appLockPinReplaced => 'PIN-код змінено';

  @override
  String get appLockPinSet => 'PIN-код встановлено, блокування увімкнено';

  @override
  String get appLockTimeoutAtOnce => 'Одразу';

  @override
  String get appLockTimeoutMinute => 'Через 1 хвилину';

  @override
  String get appLockTimeoutFiveMinutes => 'Через 5 хвилин';

  @override
  String get appLockTimeoutHour => 'Через 1 годину';

  @override
  String get appLockEnterPinToChange =>
      'Введіть PIN-код, щоб змінити налаштування блокування';

  @override
  String get appLockIntroWithPin =>
      'Застосунок запитує цей PIN-код після перерви. Новий PIN-код замінить поточний.';

  @override
  String get appLockIntroNoPin =>
      'PIN-код не дасть читати ваші канали тому, хто тримає ваш розблокований телефон.';

  @override
  String get appLockNewPin => 'Новий PIN-код';

  @override
  String get appLockPinAgain => 'Повторіть PIN-код';

  @override
  String get appLockReplacePin => 'Змінити PIN-код';

  @override
  String get appLockSetPin => 'Встановити PIN-код';

  @override
  String get appLockRemove => 'Видалити код блокування';

  @override
  String get appLockAskAgain => 'Запитувати знову';

  @override
  String get appLockBiometrics => 'Відбиток пальця або обличчя';

  @override
  String get appLockBiometricsSubtitle =>
      'Пропонується першим, коли застосунок заблоковано; PIN-код теж завжди працює';

  @override
  String languageName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'af': 'Африкаанс',
      'am': 'Амхарська',
      'ar': 'Арабська',
      'as': 'Асамська',
      'az': 'Азербайджанська',
      'be': 'Білоруська',
      'bg': 'Болгарська',
      'bn': 'Бенгальська',
      'brx': 'Бодо',
      'bs': 'Боснійська',
      'ca': 'Каталонська',
      'cmn': 'Мандаринська',
      'cs': 'Чеська',
      'cy': 'Валлійська',
      'da': 'Данська',
      'de': 'Німецька',
      'doi': 'Догрі',
      'el': 'Грецька',
      'en': 'Англійська',
      'es': 'Іспанська',
      'et': 'Естонська',
      'eu': 'Баскська',
      'fa': 'Перська',
      'fi': 'Фінська',
      'fil': 'Філіппінська',
      'fr': 'Французька',
      'ga': 'Ірландська',
      'gl': 'Галісійська',
      'gu': 'Гуджараті',
      'he': 'Іврит',
      'hi': 'Гінді',
      'hr': 'Хорватська',
      'hu': 'Угорська',
      'hy': 'Вірменська',
      'id': 'Індонезійська',
      'is': 'Ісландська',
      'it': 'Італійська',
      'ja': 'Японська',
      'jv': 'Яванська',
      'ka': 'Грузинська',
      'kk': 'Казахська',
      'km': 'Кхмерська',
      'kn': 'Каннада',
      'ko': 'Корейська',
      'kok': 'Конкані',
      'ks': 'Кашмірська',
      'ky': 'Киргизька',
      'lo': 'Лаоська',
      'lt': 'Литовська',
      'lv': 'Латвійська',
      'mai': 'Майтхілі',
      'mk': 'Македонська',
      'ml': 'Малаялам',
      'mn': 'Монгольська',
      'mni': 'Маніпурі',
      'mr': 'Маратхі',
      'ms': 'Малайська',
      'my': 'Бірманська',
      'nb': 'Норвезька',
      'ne': 'Непальська',
      'nl': 'Нідерландська',
      'no': 'Норвезька',
      'or': 'Орія',
      'pa': 'Панджабі',
      'pl': 'Польська',
      'pt': 'Португальська',
      'ro': 'Румунська',
      'ru': 'Російська',
      'sa': 'Санскрит',
      'sat': 'Санталі',
      'sd': 'Сіндхі',
      'si': 'Сингальська',
      'sk': 'Словацька',
      'sl': 'Словенська',
      'sq': 'Албанська',
      'sr': 'Сербська',
      'su': 'Сунданська',
      'sv': 'Шведська',
      'sw': 'Суахілі',
      'ta': 'Тамільська',
      'te': 'Телугу',
      'th': 'Тайська',
      'tr': 'Турецька',
      'uk': 'Українська',
      'ur': 'Урду',
      'uz': 'Узбецька',
      'vi': 'Вʼєтнамська',
      'yue': 'Кантонська',
      'zh': 'Китайська',
      'zu': 'Зулу',
      'other': '?',
    });
    return '$_temp0';
  }

  @override
  String get settingsLogOut => 'Вийти';

  @override
  String get accountsTitle => 'Акаунти';

  @override
  String get settingsSavedMessages => 'Збережене';

  @override
  String get chatSettingsTitle => 'Налаштування чатів';

  @override
  String get settingsPrivacyAndSecurity => 'Приватність і безпека';

  @override
  String get settingsNotificationsAndSounds => 'Сповіщення та звуки';

  @override
  String get dataStorageTitle => 'Дані та сховище';

  @override
  String get settingsReadAloud => 'Читання вголос';

  @override
  String get aiSettingsTitle => 'Правила зі ШІ';

  @override
  String get syncTitle => 'Синхронізація з Google Drive';

  @override
  String get settingsSyncSignedOut => 'Потрібен вхід';

  @override
  String get settingsAbout => 'Про застосунок';

  @override
  String settingsAboutApp(String appName) {
    return 'Про $appName';
  }

  @override
  String get settingsLicenses => 'Ліцензії відкритого коду';

  @override
  String settingsAppForAndroid(String appName) {
    return '$appName для Android';
  }

  @override
  String settingsAppVersion(String appName, String version) {
    return '$appName для Android $version';
  }

  @override
  String get settingsAboutText =>
      'Вільне програмне забезпечення за ліцензією GNU GPL v3. Застосунок читає канали, на які ви підписані. З пристрою нічого не надсилається, крім трафіку Telegram і, якщо ви створите правила зі ШІ, дописів, які ці правила перевіряють: вони надсилаються на вибрану вами адресу API.';

  @override
  String get settingsAccountUnavailable => 'Акаунт недоступний';

  @override
  String get settingsReloadProfile => 'Оновити профіль';

  @override
  String accountsNumbered(int id) {
    return 'Акаунт $id';
  }

  @override
  String get accountsLimitReached =>
      'Застосунок підтримує не більше чотирьох акаунтів.';

  @override
  String accountsRemoveTitle(String name) {
    return 'Видалити $name?';
  }

  @override
  String get accountsRemoveText =>
      'Його сеанс, стрічки, правила й кешовані дописи буде видалено з цього пристрою. Сам акаунт Telegram залишиться без змін.';

  @override
  String get accountsLastCannotBeRemoved =>
      'Останній акаунт не можна видалити; натомість вийдіть із нього.';

  @override
  String get accountsIntro =>
      'Кожен акаунт має на цьому пристрої власний сеанс, стрічки й правила. Під час перемикання стеження зупиняється й запускається знову вже для іншого акаунта.';

  @override
  String get accountsInUse => 'Використовується';

  @override
  String get accountsTapToSwitch => 'Натисніть, щоб перемкнутися';

  @override
  String get accountsRemoveTooltip => 'Видалити з цього пристрою';

  @override
  String get accountsAdd => 'Додати акаунт';

  @override
  String get accountsAddLimit => 'Не більше чотирьох акаунтів';

  @override
  String get accountsAddSubtitle =>
      'Вхід в інший акаунт і перемикання на нього';

  @override
  String get aiSettingsTestOk => 'Працює: модель відповіла правильно.';

  @override
  String get aiSettingsTestUnexpected =>
      'Сервер відповів, але не так, як очікувалося. Спробуйте потужнішу модель.';

  @override
  String get aiSettingsIntro =>
      'Правила зі ШІ описують вашими словами, про що має бути допис. Щоб їх перевірити, застосунок надсилає текст дописів-кандидатів на адресу API, вказану нижче. Поки ви не створите таке правило, нічого не надсилається.';

  @override
  String get aiSettingsEndpoint => 'Адреса API';

  @override
  String get aiSettingsEndpointHelper =>
      'Будь-який API, сумісний з OpenAI: OpenAI, OpenRouter, локальний Ollama (…/v1), …';

  @override
  String get aiSettingsHttpWarning =>
      'http:// не шифрується: дописи й ключ передаються відкритим текстом. Використовуйте його лише для сервера у вашій власній мережі.';

  @override
  String get aiSettingsModel => 'Модель';

  @override
  String get aiSettingsApiKey => 'Ключ API';

  @override
  String get aiSettingsApiKeyHelper =>
      'Зберігається у сховищі ключів Android. Для локального сервера залиште порожнім.';

  @override
  String get aiSettingsHideKey => 'Приховати ключ';

  @override
  String get aiSettingsShowKey => 'Показати ключ';

  @override
  String get aiSettingsSaveAndTest => 'Зберегти й перевірити';

  @override
  String get chatSettingsTextSize => 'Розмір тексту в дописах';

  @override
  String get chatSettingsTextSizePreview =>
      'Текст дописів матиме такий розмір.';

  @override
  String get chatSettingsQuickReaction => 'Швидка реакція';

  @override
  String get chatSettingsQuickReactionInfo =>
      'Подвійний дотик залишає її на дописі.';

  @override
  String get postReactionsAll => 'Усі реакції';

  @override
  String get chatSettingsTheme => 'Тема';

  @override
  String get chatSettingsThemeSystem => 'Системна';

  @override
  String get chatSettingsThemeLight => 'Світла';

  @override
  String get chatSettingsThemeDark => 'Темна';

  @override
  String get chatSettingsThemeFooter =>
      '«Системна» стежить за перемикачем темної теми на телефоні.';

  @override
  String get dataStorageResetTitle => 'Скинути налаштування автозавантаження?';

  @override
  String get dataStorageResetText =>
      'Для мобільної мережі знову буде помірне споживання, для Wi-Fi — високе, для роумінгу — низьке.';

  @override
  String get dataStorageDiskAndNetwork => 'Диск та використання мережі';

  @override
  String get dataStorageStorageUsage => 'Використання сховища';

  @override
  String get dataStorageAutoDownload => 'Автозавантаження медіа';

  @override
  String get dataStorageReset => 'Скинути налаштування автозавантаження';

  @override
  String get dataStorageAutoplay => 'Автовідтворення медіа';

  @override
  String get dataStorageGifs => 'GIF';

  @override
  String get dataStorageVideos => 'Відео';

  @override
  String get dataStorageAutoplayFooter =>
      'Відео, яке автоматично завантажується через поточне зʼєднання, відтворюється в дописі без звуку; натисніть, щоб відкрити його зі звуком.';

  @override
  String get dataStorageDataUsage => 'Споживання трафіку';

  @override
  String get dataStoragePresetCustom => 'Інше';

  @override
  String get dataStorageMediaTypes => 'Типи медіа';

  @override
  String get dataStoragePhotos => 'Фото';

  @override
  String get dataStorageEveryPhoto => 'Усі фото';

  @override
  String dataStorageUpTo(String size) {
    return 'До $size';
  }

  @override
  String get dataStorageTypesFooter =>
      'GIF і відеоповідомлення належать до відео, музика й голосові повідомлення — до файлів. Відео в межах ліміту також відтворюється автоматично, якщо для нього увімкнено автовідтворення в розділі «Дані та сховище».';

  @override
  String get dataStorageMaxVideoSize => 'Максимальний розмір відео';

  @override
  String get dataStorageMaxFileSize => 'Максимальний розмір файлу';

  @override
  String get dataStoragePreload => 'Підвантажувати більші відео';

  @override
  String dataStoragePreloadFooter(String size) {
    return 'Перші секунди відео понад $size підвантажуються заздалегідь, щоб такі відео запускалися без затримки.';
  }

  @override
  String get dataStorageAutoDownloadMedia => 'Автозавантаження медіа';

  @override
  String dataStorageClearTitle(String size) {
    return 'Очистити $size кешу?';
  }

  @override
  String get dataStorageClearText =>
      'Зображення, відео та файли знову завантажаться з Telegram, коли ви їх відкриєте.';

  @override
  String get dataStorageStatsFailed =>
      'Telegram не повідомив, скільки даних зберігає.';

  @override
  String get dataStorageTelegramCache => 'Кеш Telegram';

  @override
  String get dataStorageCachedFiles => 'Кешовані файли';

  @override
  String dataStorageFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлу',
      many: '$count файлів',
      few: '$count файли',
      one: '$count файл',
    );
    return '$_temp0';
  }

  @override
  String get dataStorageDatabase => 'База даних';

  @override
  String get dataStorageClearing => 'Очищення…';

  @override
  String dataStorageClearCache(String size) {
    return 'Очистити кеш ($size)';
  }

  @override
  String get dataStorageClearFooter =>
      'Зображення, відео та файли знову завантажаться з Telegram, коли ви їх відкриєте. Ваші стрічки, правила й позиції читання залишаться.';

  @override
  String syncAtTime(String time) {
    return '$time';
  }

  @override
  String syncYesterdayAt(String time) {
    return 'вчора, $time';
  }

  @override
  String syncDateAtTime(String date, String time) {
    return '$date, $time';
  }

  @override
  String get syncUnavailable => 'Недоступно в цій збірці';

  @override
  String syncProblem(String error) {
    return 'Проблема: $error';
  }

  @override
  String syncOnAccount(String account) {
    return 'Увімкнено, $account';
  }

  @override
  String syncOnAccountLastSynced(String account, String when) {
    return 'Увімкнено, $account · остання синхронізація — $when';
  }

  @override
  String get syncIntro =>
      'Синхронізує ваші стрічки з їхніми каналами, правила й налаштування на всіх ваших пристроях через прихований файл застосунку у вашому власному Google Drive. Власного сервера в нас немає. Позиції читання, ключ API для ШІ та ваш сеанс Telegram залишаються на кожному пристрої окремо.';

  @override
  String get syncNoClientIdBuild =>
      'Цю збірку створено без ідентифікатора клієнта Google, тому синхронізацію не можна увімкнути.';

  @override
  String get syncSignIn => 'Увійти через Google і синхронізувати';

  @override
  String get syncSyncing => 'Синхронізація…';

  @override
  String get syncNotSyncedYet => 'Ще не синхронізовано';

  @override
  String syncLastSynced(String when) {
    return 'Остання синхронізація — $when';
  }

  @override
  String get syncNow => 'Синхронізувати зараз';

  @override
  String get syncTurnOff => 'Вимкнути на цьому пристрої';

  @override
  String get syncSignedOutError =>
      'Ви вийшли з акаунта Google. Увійдіть знову, щоб синхронізація тривала.';

  @override
  String get syncNoClientIdError =>
      'У цій збірці немає ідентифікатора клієнта Google.';

  @override
  String get syncSignInCancelled => 'Вхід скасовано.';

  @override
  String syncSignInFailed(String detail) {
    return 'Не вдалося увійти через Google: $detail';
  }

  @override
  String get syncNotSignedIn => 'Ви не ввійшли в Google Drive.';

  @override
  String syncDriveUnreachable(String detail) {
    return 'Не вдається зʼєднатися з Google Drive: $detail';
  }

  @override
  String syncDriveRefused(String request, String status, String detail) {
    String _temp0 = intl.Intl.selectLogic(request, {
      'find': 'пошуку файлу синхронізації',
      'read': 'читанні файлу синхронізації',
      'create': 'створенні файлу синхронізації',
      'other': 'оновленні файлу синхронізації',
    });
    return 'Google Drive відмовив у $_temp0 ($status)$detail';
  }

  @override
  String viewerCounter(int index, int total) {
    return '$index із $total';
  }

  @override
  String get viewerSaveToSavedMessages => 'Зберегти до Збереженого';

  @override
  String get viewerSaveToGallery => 'Зберегти до галереї';

  @override
  String get viewerVideoSavedToGallery => 'Відео збережено до галереї';

  @override
  String get viewerPictureSavedToGallery => 'Фото збережено до галереї';

  @override
  String viewerSaveFailed(String error) {
    return 'Не вдалося зберегти: $error';
  }

  @override
  String get viewerShareNeedsDownload =>
      'Щоб поділитися відео, спершу завантажте його.';

  @override
  String get viewerShareFileMissing =>
      'Не вдалося поділитися: файл не завантажився';

  @override
  String viewerShareFailed(String error) {
    return 'Не вдалося поділитися: $error';
  }

  @override
  String get pipOpen => 'Картинка в картинці';

  @override
  String get pipFloatingPlayer => 'Плаваючий відеоплеєр';

  @override
  String get pipBackToFullScreen => 'На повний екран';

  @override
  String get playerPlay => 'Відтворити';

  @override
  String get playerPause => 'Пауза';

  @override
  String get playerSpeed => 'Швидкість';

  @override
  String get audioStop => 'Зупинити';

  @override
  String get videoSoundOn => 'Увімкнути звук';

  @override
  String get videoSoundOff => 'Вимкнути звук';

  @override
  String videoSeekSeconds(int seconds) {
    return '$seconds с';
  }

  @override
  String videoCannotPlay(String error) {
    return 'Не вдалося відтворити відео: $error';
  }

  @override
  String get videoDownload => 'Завантажити';

  @override
  String videoDownloadWithSize(String size) {
    return 'Завантажити ($size)';
  }

  @override
  String get videoCancelDownload => 'Скасувати завантаження';

  @override
  String get videoDownloadFailed => 'Помилка, спробуйте ще раз';

  @override
  String get autoDownloadRowMobile => 'При використанні мобільної мережі';

  @override
  String get autoDownloadRowWifi => 'При використанні Wi-Fi';

  @override
  String get autoDownloadRowRoaming => 'У роумінгу';

  @override
  String get autoDownloadTitleMobile => 'Через мобільну мережу';

  @override
  String get autoDownloadTitleWifi => 'Через Wi-Fi';

  @override
  String get autoDownloadTitleRoaming => 'У роумінгу';

  @override
  String get autoDownloadPresetLow => 'Низьке';

  @override
  String get autoDownloadPresetMedium => 'Помірне';

  @override
  String get autoDownloadPresetHigh => 'Високе';

  @override
  String get autoDownloadSummaryDisabled => 'Вимкнено';

  @override
  String get autoDownloadSummaryNothing => 'Нічого';

  @override
  String get autoDownloadSummaryPhotos => 'Фото';

  @override
  String autoDownloadSummaryVideos(String limit) {
    return 'Відео ($limit)';
  }

  @override
  String autoDownloadSummaryFiles(String limit) {
    return 'Файли ($limit)';
  }

  @override
  String appStartFailed(String error) {
    return 'Не вдалося запустити ядро: $error';
  }

  @override
  String get languageTitle => 'Мова';

  @override
  String get languageSystem => 'Як у системі';

  @override
  String get languageFooter =>
      '«Як у системі» вибирає мову телефону, якщо застосунок нею перекладено, а інакше — англійську.';

  @override
  String ttsIntro(String channel) {
    return 'Новий допис у каналі $channel.';
  }

  @override
  String get ttsLink => 'посилання';

  @override
  String get ttsMore => '… і далі';

  @override
  String get serviceChannelName => 'Стеження за каналами';

  @override
  String get serviceChannelDescription =>
      'Тримає зʼєднання з Telegram для правил із ключовими словами';

  @override
  String get serviceStarting => 'Запуск…';

  @override
  String get servicePause => 'Призупинити';

  @override
  String get serviceResume => 'Відновити';

  @override
  String get servicePaused => 'Призупинено: правила не перевіряються';

  @override
  String serviceWatching(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Стеження за $count каналу',
      many: 'Стеження за $count каналами',
      few: 'Стеження за $count каналами',
      one: 'Стеження за $count каналом',
    );
    return '$_temp0';
  }

  @override
  String get notifyNewPost => 'Новий допис';

  @override
  String notifyNewPosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count нового допису',
      many: '$count нових дописів',
      few: '$count нові дописи',
      one: '$count новий допис',
    );
    return '$_temp0';
  }

  @override
  String get notifyListen => 'Слухати';

  @override
  String get notifyStop => 'Зупинити';

  @override
  String get notifyChannelSilent => 'Тихі дописи';

  @override
  String get notifyChannelSilentDescription =>
      'Правила з тихим пріоритетом: без звуку й без спливаючих сповіщень';

  @override
  String get notifyChannelNormal => 'Дописи';

  @override
  String get notifyChannelNormalDescription =>
      'Правила зі звичайним пріоритетом';

  @override
  String get notifyChannelNormalInApp => 'Дописи, коли застосунок відкрито';

  @override
  String get notifyChannelNormalInAppDescription =>
      'Правила зі звичайним пріоритетом, коли застосунок відкрито, без спливаючих сповіщень';

  @override
  String get notifyChannelUrgent => 'Термінові дописи';

  @override
  String get notifyChannelUrgentDescription =>
      'Правила з терміновим пріоритетом';

  @override
  String get notifyChannelUrgentInApp =>
      'Термінові дописи, коли застосунок відкрито';

  @override
  String get notifyChannelUrgentInAppDescription =>
      'Правила з терміновим пріоритетом, коли застосунок відкрито, без спливаючих сповіщень';

  @override
  String notifyChannelBypassesDnd(String description) {
    return '$description; діють попри режим «Не турбувати»';
  }

  @override
  String get mediaPoll => 'Опитування';

  @override
  String get mediaLocation => 'Місце';

  @override
  String get mediaVenue => 'Місце';

  @override
  String get mediaContact => 'Контакт';

  @override
  String get mediaDice => 'Кубик';

  @override
  String get mediaGame => 'Гра';

  @override
  String get mediaInvoice => 'Рахунок';

  @override
  String get mediaGiveaway => 'Розіграш';

  @override
  String get mediaStory => 'Історія';

  @override
  String get mediaChecklist => 'Список задач';

  @override
  String get mediaAlbum => 'Альбом';

  @override
  String get mediaPaidMedia => 'Платне медіа';

  @override
  String get mediaUnsupported => 'Непідтримуваний допис';

  @override
  String servicePinned(String channel) {
    return '$channel прикріплює допис';
  }

  @override
  String servicePinnedOpen(String channel) {
    return '$channel прикріплює допис. Відкрити прикріплений допис';
  }

  @override
  String serviceTitleChanged(String title) {
    return 'Канал перейменовано на $title';
  }

  @override
  String get servicePhotoChanged => 'Фото каналу змінено';

  @override
  String get servicePhotoRemoved => 'Фото каналу вилучено';

  @override
  String get serviceChannelCreated => 'Канал створено';

  @override
  String get serviceLiveStarted => 'Почалася трансляція';

  @override
  String serviceLiveEnded(String length) {
    return 'Трансляцію завершено ($length)';
  }

  @override
  String serviceLiveScheduled(String date) {
    return 'Трансляцію заплановано на $date';
  }

  @override
  String get serviceOther => 'Службове повідомлення';

  @override
  String serviceOfChannel(String channel, String words) {
    return '$channel: $words';
  }

  @override
  String get problemSyncNewerVersion =>
      'Файл синхронізації записала новіша версія застосунку. Оновіть застосунок на цьому пристрої.';

  @override
  String problemSyncUnreadable(String error) {
    return 'Не вдається прочитати файл синхронізації: $error';
  }
}
