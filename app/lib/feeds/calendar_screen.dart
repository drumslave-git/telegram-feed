import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';
import 'media_view.dart';

/// The calendar of a timeline, as the official app's: the months under one another with
/// the newest at the bottom, and in every day that has a photo or a video a small round
/// picture of it behind the day's number. A tap on a day closes the screen with that day;
/// the days to come cannot be picked.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.gateway,
    required this.chatIds,
    this.around,
    this.now,
  });

  final TelegramGateway gateway;

  /// The channels of the timeline: a feed's calendar shows the newest picture of a day
  /// among all of them.
  final List<int> chatIds;

  /// The day the calendar opens at; today when null.
  final DateTime? around;

  /// The clock, for tests.
  final DateTime? now;

  /// Telegram itself is younger than this.
  static final first = DateTime(2013, 8);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final DateTime _today = () {
    final n = widget.now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();

  /// Months on the list: index 0 is this month, every next one a month earlier.
  late final int _months =
      (_today.year - CalendarScreen.first.year) * 12 +
      _today.month -
      CalendarScreen.first.month +
      1;

  DateTime _monthAt(int index) => DateTime(_today.year, _today.month - index);

  int _indexOf(DateTime day) =>
      ((_today.year - day.year) * 12 + _today.month - day.month).clamp(
        0,
        _months - 1,
      );

  /// The picture of a day, by the day.
  final _pictures = <DateTime, Post>{};

  /// Where the next page of a channel's calendar starts; absent before the first page.
  final _next = <int, int>{};

  /// Channels whose calendar has been read to its end.
  final _done = <int>{};

  bool _loading = false;

  /// The oldest month the list has built: the pages are read down to it.
  late DateTime _wanted = _monthAt(_indexOf(widget.around ?? _today) + 1);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  static DateTime _dayOf(Post p) {
    final at = DateTime.fromMillisecondsSinceEpoch(p.date * 1000);
    return DateTime(at.year, at.month, at.day);
  }

  /// Reads pages until every channel is read down to [_wanted] or to its end, four
  /// channels at a time.
  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      while (mounted) {
        final behind = [
          for (final id in widget.chatIds)
            if (!_done.contains(id) &&
                (_readTo[id] == null || _readTo[id]!.isAfter(_wanted)))
              id,
        ];
        if (behind.isEmpty) break;
        await Future.wait(behind.take(4).map(_loadPage));
        if (!mounted) return;
        setState(() {}); // the pictures of these pages
      }
    } finally {
      _loading = false;
    }
  }

  /// The oldest day read of each channel.
  final _readTo = <int, DateTime>{};

  Future<void> _loadPage(int chatId) async {
    List<Post> days;
    try {
      days = await widget.gateway.mediaCalendar(
        chatId,
        fromMessageId: _next[chatId] ?? 0,
      );
    } on TelegramException {
      // The calendar works without pictures.
      _done.add(chatId);
      return;
    }
    var news = false;
    for (final post in days) {
      final day = _dayOf(post);
      final known = _readTo[chatId];
      if (known == null || day.isBefore(known)) {
        _readTo[chatId] = day;
        news = true;
      }
      final have = _pictures[day];
      if (have == null || post.date > have.date) _pictures[day] = post;
    }
    // A page that tells no older day is the end, whatever Telegram repeats in it.
    if (days.isEmpty || !news) {
      _done.add(chatId);
    } else {
      _next[chatId] = days.last.messageId;
    }
  }

  void _want(DateTime month) {
    if (!month.isBefore(_wanted)) return;
    _wanted = month;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final material = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final around = widget.around ?? _today;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.calendarTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Text(
                        material.narrowWeekdays[(material.firstDayOfWeekIndex +
                                i) %
                            7],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ScrollablePositionedList.builder(
              reverse: true,
              itemCount: _months,
              initialScrollIndex: _indexOf(around),
              // This month stands at the bottom; an older one opens a little above it.
              initialAlignment: _indexOf(around) == 0 ? 0 : 0.2,
              padding: EdgeInsets.only(
                bottom: 8 + MediaQuery.paddingOf(context).bottom,
              ),
              itemBuilder: (context, index) {
                final month = _monthAt(index);
                _want(month);
                return _Month(
                  month: month,
                  today: _today,
                  firstWeekday: material.firstDayOfWeekIndex,
                  pictures: _pictures,
                  gateway: widget.gateway,
                  onPick: (day) => Navigator.of(context).pop(day),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({
    required this.month,
    required this.today,
    required this.firstWeekday,
    required this.pictures,
    required this.gateway,
    required this.onPick,
  });

  final DateTime month;
  final DateTime today;

  /// The weekday a week starts with, 0 for Sunday, as [MaterialLocalizations] tells it.
  final int firstWeekday;
  final Map<DateTime, Post> pictures;
  final TelegramGateway gateway;
  final void Function(DateTime day) onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.localeName == 'en' ? 'en_US' : l10n.localeName;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    // Empty cells before the first day: DateTime counts Monday as 1 and Sunday as 7.
    final lead = (month.weekday % 7 - firstWeekday + 7) % 7;
    final weeks = ((lead + days) / 7).ceil();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(
            toBeginningOfSentenceCase(
              DateFormat('LLLL y', locale).format(month),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (var week = 0; week < weeks; week++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: () {
                    final number = week * 7 + i - lead + 1;
                    if (number < 1 || number > days) {
                      return const SizedBox(height: _Day.height);
                    }
                    final day = DateTime(month.year, month.month, number);
                    return _Day(
                      day: day,
                      label: DateFormat.yMMMMd(locale).format(day),
                      picture: pictures[day],
                      enabled: !day.isAfter(today),
                      gateway: gateway,
                      onPick: onPick,
                    );
                  }(),
                ),
            ],
          ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.label,
    required this.picture,
    required this.enabled,
    required this.gateway,
    required this.onPick,
  });

  static const height = 52.0;
  static const _circle = 44.0;

  final DateTime day;

  /// The whole date, for screen readers.
  final String label;
  final Post? picture;
  final bool enabled;
  final TelegramGateway gateway;
  final void Function(DateTime day) onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = picture?.media;
    final file = switch (media) {
      // The cell is small: the thumbnail is enough.
      PhotoMedia(:final sizes) => sizes.isEmpty ? null : sizes.first,
      VideoMedia(:final thumbnail) => thumbnail,
      _ => null,
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: file == null ? label : context.l10n.calendarDayWithMedia(label),
      excludeSemantics: true,
      child: InkResponse(
        onTap: enabled ? () => onPick(day) : null,
        radius: _circle / 2 + 4,
        child: SizedBox(
          height: height,
          child: Center(
            child: SizedBox(
              width: _circle,
              height: _circle,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (file != null)
                    IgnorePointer(
                      child: ClipOval(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PhotoView(
                              file: file,
                              gateway: gateway,
                              fill: true,
                              radius: 0,
                            ),
                            // The number stays readable on a bright picture.
                            const ColoredBox(color: Color(0x59000000)),
                          ],
                        ),
                      ),
                    ),
                  Center(
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: file != null
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: file != null
                            ? Colors.white
                            : enabled
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
