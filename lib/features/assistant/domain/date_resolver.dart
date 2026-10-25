/// What a message says about *when*.
class WhenHint {
  const WhenHint({this.date, this.hour, this.minute, this.relative});

  /// Calendar day (time part ignored).
  final DateTime? date;
  final int? hour;
  final int? minute;

  /// "in 20 minutes" style offsets from now.
  final Duration? relative;

  bool get hasTime => hour != null;
  bool get isEmpty => date == null && hour == null && relative == null;

  /// Combines into a concrete moment relative to [now]. A bare time that is
  /// already past today means tomorrow.
  DateTime? resolve(DateTime now) {
    if (relative != null) return now.add(relative!);
    final day = date ?? (hour != null ? DateTime(now.year, now.month, now.day) : null);
    if (day == null) return null;
    var at = DateTime(day.year, day.month, day.day, hour ?? 9, minute ?? 0);
    if (date == null && at.isBefore(now)) at = at.add(const Duration(days: 1));
    return at;
  }
}

/// Deterministic English date/time extraction. A 270M model is good at
/// deciding *what* a message asks for, but date arithmetic is where tiny
/// models fail, so dates come from here whenever the text contains them.
abstract final class DateResolver {
  static const _weekdays = {
    'monday': 1,
    'mon': 1,
    'tuesday': 2,
    'tue': 2,
    'tues': 2,
    'wednesday': 3,
    'wed': 3,
    'thursday': 4,
    'thu': 4,
    'thur': 4,
    'thurs': 4,
    'friday': 5,
    'fri': 5,
    'saturday': 6,
    'sat': 6,
    'sunday': 7,
    'sun': 7,
  };

  static const _months = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  static WhenHint fromText(String input, DateTime now) {
    final t = ' ${input.toLowerCase()} ';
    final today = DateTime(now.year, now.month, now.day);

    // Relative offsets: "in 20 min", "in 2 hours", "in 3 days".
    final rel = RegExp(
      r'\bin\s+(\d+|an?|one|two|three|half an?)\s*(minutes?|mins?|hours?|hrs?|h|days?|weeks?)\b',
    ).firstMatch(t);
    if (rel != null) {
      final n = switch (rel.group(1)!) {
        'a' || 'an' || 'one' => 1.0,
        'two' => 2.0,
        'three' => 3.0,
        final s when s.startsWith('half') => 0.5,
        final s => double.parse(s),
      };
      final unit = rel.group(2)!;
      final d = unit.startsWith('m')
          ? Duration(seconds: (n * 60).round())
          : unit.startsWith('h')
          ? Duration(minutes: (n * 60).round())
          : unit.startsWith('d')
          ? Duration(hours: (n * 24).round())
          : Duration(days: (n * 7).round());
      return WhenHint(relative: d);
    }

    DateTime? date;
    if (RegExp(r'\b(today|tonight|this evening|this afternoon|this morning)\b').hasMatch(t)) date = today;
    if (RegExp(r'\btomorrow\b|\btmrw\b|\btmr\b').hasMatch(t)) date = today.add(const Duration(days: 1));
    if (RegExp(r'\bday after tomorrow\b').hasMatch(t)) date = today.add(const Duration(days: 2));

    final wd = RegExp(r'\b(next\s+|this\s+|on\s+)?(' + _weekdays.keys.join('|') + r')\b').firstMatch(t);
    if (date == null && wd != null) {
      final target = _weekdays[wd.group(2)]!;
      var delta = (target - now.weekday) % 7;
      if (delta == 0) delta = 7;
      date = today.add(Duration(days: delta));
    }

    // ISO 2026-11-03, or 3/11/2026 and 3.11. (day first, as most of the world).
    final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(t);
    if (iso != null) {
      date = _valid(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!)) ?? date;
    } else {
      final dmy = RegExp(r'\b(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?\b(?!\s*(?:am|pm))').firstMatch(t);
      if (dmy != null &&
          !RegExp(r'\d{1,2}[.:]\d{2}\s*(am|pm)?\b').hasMatch(dmy.group(0)!.replaceAll('/', '|'))) {
        final d = int.parse(dmy.group(1)!), m = int.parse(dmy.group(2)!);
        var y = dmy.group(3) == null ? now.year : int.parse(dmy.group(3)!);
        if (y < 100) y += 2000;
        final candidate = _valid(y, m, d);
        if (candidate != null) {
          date = dmy.group(3) == null && candidate.isBefore(today) ? _valid(y + 1, m, d) : candidate;
        }
      }
    }

    // "March 3", "3 March", "3rd of march".
    final md =
        RegExp(r'\b(' + _months.keys.join('|') + r')\s+(\d{1,2})(?:st|nd|rd|th)?\b(?![:.]\d)')
            .firstMatch(t) ??
        RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(' + _months.keys.join('|') + r')\b').firstMatch(t);
    if (md != null) {
      final a = md.group(1)!, b = md.group(2)!;
      final month = _months[a] ?? _months[b]!;
      final day = int.parse(_months.containsKey(a) ? b : a);
      var candidate = _valid(now.year, month, day);
      if (candidate != null && candidate.isBefore(today)) candidate = _valid(now.year + 1, month, day);
      date = candidate ?? date;
    }

    // Times: "at 5", "5pm", "5:30 pm", "17:30", "noon", "midnight".
    int? hour, minute;
    final hm = RegExp(r'\b(\d{1,2})[:.](\d{2})\s*(am|pm|a\.m\.|p\.m\.)?').firstMatch(t);
    final h = RegExp(r'\b(?:at\s+)?(\d{1,2})\s*(am|pm|a\.m\.|p\.m\.)').firstMatch(t);
    final at = RegExp(r'\bat\s+(\d{1,2})\b(?![:./\d])').firstMatch(t);
    if (hm != null && int.parse(hm.group(1)!) < 24 && int.parse(hm.group(2)!) < 60) {
      hour = int.parse(hm.group(1)!);
      minute = int.parse(hm.group(2)!);
      hour = _meridiem(hour, hm.group(3));
    } else if (h != null) {
      hour = _meridiem(int.parse(h.group(1)!), h.group(2));
      minute = 0;
    } else if (at != null) {
      hour = int.parse(at.group(1)!);
      minute = 0;
      // "at 5" with no am/pm: assume the afternoon for 1–7, like people mean.
      if (hour >= 1 && hour <= 7) hour += 12;
    } else if (t.contains(' noon')) {
      hour = 12;
      minute = 0;
    } else if (t.contains(' midnight')) {
      hour = 0;
      minute = 0;
    } else if (t.contains('tonight') || t.contains('this evening')) {
      hour = 20;
      minute = 0;
    } else if (t.contains('this afternoon')) {
      hour = 15;
      minute = 0;
    } else if (t.contains('this morning')) {
      hour = 9;
      minute = 0;
    }
    if (hour != null && hour > 23) hour = null;
    return WhenHint(date: date, hour: hour, minute: minute);
  }

  /// Parses the model's "YYYY-MM-DD" / "HH:MM" fields.
  static WhenHint fromModel(String? date, String? time) {
    DateTime? d;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date?.trim() ?? '');
    if (iso != null) d = _valid(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    int? hour, minute;
    final hm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time?.trim() ?? '');
    if (hm != null && int.parse(hm.group(1)!) < 24 && int.parse(hm.group(2)!) < 60) {
      hour = int.parse(hm.group(1)!);
      minute = int.parse(hm.group(2)!);
    }
    return WhenHint(date: d, hour: hour, minute: minute);
  }

  /// Text wins over the model field by field.
  static WhenHint merge(WhenHint fromText, WhenHint fromModel) => fromText.relative != null
      ? fromText
      : WhenHint(
          date: fromText.date ?? fromModel.date,
          hour: fromText.hour ?? fromModel.hour,
          minute: fromText.hour != null ? fromText.minute : fromModel.minute,
        );

  static int _meridiem(int hour, String? m) {
    if (m == null) return hour;
    final pm = m.startsWith('p');
    if (pm && hour < 12) return hour + 12;
    if (!pm && hour == 12) return 0;
    return hour;
  }

  static DateTime? _valid(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    return dt.month == m && dt.day == d ? dt : null;
  }
}
