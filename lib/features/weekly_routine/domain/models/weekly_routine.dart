import 'dart:convert';

/// A study window inside one working day.
///
/// The point of naming windows separately from days is that two of them --
/// the commutes -- are time the user is spending anyway, while the evening
/// one competes with rest. Keeping them apart lets the routine say which is
/// which instead of presenting four hours of "study time" that do not exist.
class RoutineWindow {
  final String label;
  final String time;
  final String activity;
  final String note;

  const RoutineWindow({
    required this.label,
    required this.time,
    required this.activity,
    this.note = '',
  });

  Map<String, Object?> toJson() => {
    'label': label,
    'time': time,
    'activity': activity,
    'note': note,
  };

  static RoutineWindow fromJson(Map<String, Object?> json) => RoutineWindow(
    label: (json['label'] ?? '').toString(),
    time: (json['time'] ?? '').toString(),
    activity: (json['activity'] ?? '').toString(),
    note: (json['note'] ?? '').toString(),
  );
}

class RoutineDay {
  final String day;
  final String focus;
  final String note;
  final bool isOffDay;

  const RoutineDay({
    required this.day,
    required this.focus,
    this.note = '',
    this.isOffDay = false,
  });

  Map<String, Object?> toJson() => {
    'day': day,
    'focus': focus,
    'note': note,
    'is_off_day': isOffDay,
  };

  static RoutineDay fromJson(Map<String, Object?> json) => RoutineDay(
    day: (json['day'] ?? '').toString(),
    focus: (json['focus'] ?? '').toString(),
    note: (json['note'] ?? '').toString(),
    isOffDay: json['is_off_day'] == true,
  );
}

class WeeklyRoutine {
  final String title;

  /// One line on why the routine is shaped this way. It survives edits, so
  /// the user can see whether a change broke the original reasoning.
  final String principle;

  final List<RoutineWindow> windows;
  final List<RoutineDay> days;
  final DateTime updatedAt;

  /// What the user last asked for, kept so the screen can show what produced
  /// this version.
  final String? lastCommand;

  const WeeklyRoutine({
    required this.title,
    required this.principle,
    required this.windows,
    required this.days,
    required this.updatedAt,
    this.lastCommand,
  });

  WeeklyRoutine copyWith({DateTime? updatedAt, String? lastCommand}) =>
      WeeklyRoutine(
        title: title,
        principle: principle,
        windows: windows,
        days: days,
        updatedAt: updatedAt ?? this.updatedAt,
        lastCommand: lastCommand ?? this.lastCommand,
      );

  Map<String, Object?> toJson() => {
    'title': title,
    'principle': principle,
    'windows': windows.map((w) => w.toJson()).toList(),
    'days': days.map((d) => d.toJson()).toList(),
    'updated_at': updatedAt.toIso8601String(),
    'last_command': lastCommand,
  };

  String encode() => jsonEncode(toJson());

  static WeeklyRoutine fromJson(Map<String, Object?> json) {
    final rawWindows = json['windows'];
    final rawDays = json['days'];
    return WeeklyRoutine(
      title: (json['title'] ?? 'সাপ্তাহিক পড়ার ছক').toString(),
      principle: (json['principle'] ?? '').toString(),
      windows: rawWindows is List
          ? rawWindows
                .whereType<Map>()
                .map((w) => RoutineWindow.fromJson(w.cast<String, Object?>()))
                .toList()
          : const [],
      days: rawDays is List
          ? rawDays
                .whereType<Map>()
                .map((d) => RoutineDay.fromJson(d.cast<String, Object?>()))
                .toList()
          : const [],
      updatedAt:
          DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
      lastCommand: json['last_command']?.toString(),
    );
  }

  /// Returns null rather than throwing: a stored routine that cannot be read
  /// should fall back to the default, not break the screen.
  static WeeklyRoutine? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  /// The starting point, used until the user or the model replaces it.
  ///
  /// Shaped around a 9-6 office day: the two commutes are treated as the
  /// cheap windows because that time is already being spent, and the evening
  /// is deliberately held to one task.
  static WeeklyRoutine get defaultRoutine => WeeklyRoutine(
    title: 'সাপ্তাহিক পড়ার ছক',
    principle: 'যাতায়াতের দুটো জানালা প্রায় বিনামূল্যে — ওই সময় এমনিতেই যাচ্ছে। রাতের জানালা ছোট আর একটাই কাজের, কারণ অফিস শেষে তার বেশি টেকে না।',
    windows: const [
      RoutineWindow(
        label: 'জানালা ১ · যাতায়াত',
        time: '০৮:০০–০৯:০০',
        activity: 'ফোনে ২০–৩০টা MCQ',
        note: 'আজকের Daily Exam-এর বিষয় ধরে। বই লাগে না, জ্যামে বসেই হয়।',
      ),
      RoutineWindow(
        label: 'জানালা ২ · ফেরা',
        time: '১৮:০০–১৯:০০',
        activity: 'ভুলের খাতা ও due রিভিশন',
        note: 'নতুন কিছু নয় — আজ যা ভুল হয়েছে আর Spaced Repetition-এ যা due।',
      ),
      RoutineWindow(
        label: 'জানালা ৩ · একটাই কাজ',
        time: '২০:৩০–২১:৩০',
        activity: 'একটা দুর্বল টপিক',
        note: 'ক্লান্তি ৭-এর উপরে থাকলে বাদ — তখন ১০ মিনিট কার্ড দেখে ঘুম।',
      ),
    ],
    days: const [
      RoutineDay(day: 'শনি', focus: 'বাংলা ব্যাকরণ'),
      RoutineDay(day: 'রবি', focus: 'গণিত'),
      RoutineDay(day: 'সোম', focus: 'বাংলাদেশ বিষয়াবলি'),
      RoutineDay(day: 'মঙ্গল', focus: 'English'),
      RoutineDay(day: 'বুধ', focus: 'সাধারণ জ্ঞান ও আন্তর্জাতিক'),
      RoutineDay(
        day: 'বৃহস্পতি',
        focus: 'Model Test + ভুল বিশ্লেষণ',
        note: '২–৩ ঘণ্টা',
        isOffDay: true,
      ),
      RoutineDay(
        day: 'শুক্র',
        focus: 'সপ্তাহের দুর্বল জায়গা গভীরভাবে',
        note: 'পরিবারের জন্যও সময় রাখা',
        isOffDay: true,
      ),
    ],
    updatedAt: DateTime(2026, 10, 27),
  );
}
