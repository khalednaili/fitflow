import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/booking.dart';
import '../models/personal_record.dart';

/// Data computed by [ProgressService] for display on the Progress Dashboard.
class ProgressData {
  const ProgressData({
    required this.currentStreakWeeks,
    required this.weeklyAttendance,
    required this.prsByExercise,
    required this.totalCheckIns,
  });

  /// Number of consecutive weeks (ending this week) with at least one check-in.
  final int currentStreakWeeks;

  /// Last 8 ISO-weeks of check-in counts, oldest first.
  final List<WeeklyCount> weeklyAttendance;

  /// PRs grouped by exercise name, each list sorted by date ascending.
  final Map<String, List<PersonalRecord>> prsByExercise;

  /// Total check-ins across all time.
  final int totalCheckIns;
}

class WeeklyCount {
  const WeeklyCount({required this.label, required this.count});
  final String label; // e.g. "W12"
  final int count;
}

class ProgressService {
  ProgressService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Stream all checked-in bookings for [userId].
  Stream<List<Booking>> _streamCheckedIn(String userId) {
    return _db
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .where('checkedIn', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map(Booking.fromSnapshot).toList());
  }

  /// Stream all PRs for [userId].
  Stream<List<PersonalRecord>> _streamPRs(String userId) {
    return _db
        .collection('personalRecords')
        .where('userId', isEqualTo: userId)
        .orderBy('achievedAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(PersonalRecord.fromSnapshot).toList());
  }

  Stream<ProgressData> streamProgress(String userId) {
    return _streamCheckedIn(userId).asyncMap((bookings) async {
      final prs =
          await _streamPRs(userId).first.timeout(const Duration(seconds: 10));
      return _compute(bookings, prs);
    });
  }

  ProgressData _compute(
      List<Booking> bookings, List<PersonalRecord> prs) {
    // ── Weekly attendance ────────────────────────────────────────────────────
    final now = DateTime.now();
    // ISO week number helper
    int isoWeek(DateTime d) {
      final thursday =
          d.subtract(Duration(days: d.weekday - 4)); // Thursday of same week
      final firstThursday = DateTime(thursday.year, 1, 1);
      final diff = thursday.difference(firstThursday).inDays;
      return ((diff + firstThursday.weekday - 1) ~/ 7) + 1;
    }

    String weekKey(DateTime d) => '${d.year}-${isoWeek(d).toString().padLeft(2, '0')}';

    final countsByWeek = <String, int>{};
    for (final b in bookings) {
      if (b.checkedInAt != null) {
        final key = weekKey(b.checkedInAt!);
        countsByWeek[key] = (countsByWeek[key] ?? 0) + 1;
      }
    }

    // Build last 8 weeks list
    final last8 = <WeeklyCount>[];
    for (var i = 7; i >= 0; i--) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + 7 * i));
      final key = weekKey(weekStart);
      last8.add(WeeklyCount(
        label: 'W${isoWeek(weekStart)}',
        count: countsByWeek[key] ?? 0,
      ));
    }

    // ── Streak ───────────────────────────────────────────────────────────────
    var streak = 0;
    for (var i = 0; i < 8; i++) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + 7 * i));
      final key = weekKey(weekStart);
      if ((countsByWeek[key] ?? 0) > 0) {
        streak++;
      } else {
        break;
      }
    }

    // ── PRs grouped ──────────────────────────────────────────────────────────
    final prsByExercise = <String, List<PersonalRecord>>{};
    for (final pr in prs) {
      prsByExercise.putIfAbsent(pr.exerciseName, () => []).add(pr);
    }
    // Sort each list by date ascending (already ordered from query)

    return ProgressData(
      currentStreakWeeks: streak,
      weeklyAttendance: last8,
      prsByExercise: prsByExercise,
      totalCheckIns: bookings.length,
    );
  }
}

/// Parses the numeric value from a PR value string.
/// Handles: "100kg", "50 reps", "3:45" (returns total seconds), "85.5"
double? parsePrValue(String raw) {
  final s = raw.trim();
  // Time format mm:ss or h:mm:ss
  final timeMatch = RegExp(r'^(\d+):(\d{2})(?::(\d{2}))?$').firstMatch(s);
  if (timeMatch != null) {
    final a = int.parse(timeMatch.group(1)!);
    final b = int.parse(timeMatch.group(2)!);
    final c = timeMatch.group(3) != null ? int.parse(timeMatch.group(3)!) : 0;
    return timeMatch.group(3) != null
        ? (a * 3600 + b * 60 + c).toDouble() // h:mm:ss
        : (a * 60 + b).toDouble(); // mm:ss
  }
  final numMatch = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(s);
  if (numMatch != null) return double.tryParse(numMatch.group(1)!);
  return null;
}
