/// When a rule is active: weekdays plus a daily window in local time, which may wrap
/// past midnight (ARCHITECTURE.md section 6.1).
final class Schedule {
  const Schedule({
    required this.weekdays,
    required this.from,
    required this.to,
  });

  /// ISO weekdays, 1 = Monday … 7 = Sunday. The weekday of the moment the window *starts*.
  final Set<int> weekdays;

  /// Minutes since midnight, 0..1439. `from == to` means the whole day.
  final int from;
  final int to;

  static const allWeek = {1, 2, 3, 4, 5, 6, 7};

  /// `"HH:mm"` to minutes.
  static int parseTime(String hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (m == null) throw FormatException('time must be HH:mm', hhmm);
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) throw FormatException('time out of range', hhmm);
    return h * 60 + min;
  }

  static String formatTime(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  bool get wrapsMidnight => to < from;

  bool isActive(DateTime local) {
    final now = local.hour * 60 + local.minute;
    if (from == to) return weekdays.contains(local.weekday);
    if (!wrapsMidnight) {
      return now >= from && now < to && weekdays.contains(local.weekday);
    }
    // Window started today (after `from`) or yesterday (before `to`).
    if (now >= from) return weekdays.contains(local.weekday);
    if (now < to) {
      final startDay = local.weekday == 1 ? 7 : local.weekday - 1;
      return weekdays.contains(startDay);
    }
    return false;
  }

  Map<String, Object?> toJson() => {
    'weekdays': weekdays.toList()..sort(),
    'from': formatTime(from),
    'to': formatTime(to),
  };

  static Schedule fromJson(Map<Object?, Object?> json) => Schedule(
    weekdays: (json['weekdays'] as List).cast<int>().toSet(),
    from: parseTime(json['from'] as String),
    to: parseTime(json['to'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is Schedule &&
      other.from == from &&
      other.to == to &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);
  @override
  int get hashCode => Object.hash(from, to, Object.hashAllUnordered(weekdays));
}
