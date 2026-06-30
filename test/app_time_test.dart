import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/utils/app_time.dart';

void main() {
  // A fixed reference instant for deterministic tests.
  // 2026-06-15 12:00 UTC is a Monday.
  final nowUtc = DateTime.utc(2026, 6, 15, 12, 0);

  group('instant comparisons (timezone-agnostic)', () {
    final clock = GymClock(fixedNow: nowUtc);

    test('isPast is true for an instant before now, regardless of tz flag', () {
      expect(clock.isPast(DateTime.utc(2026, 6, 15, 11, 59)), isTrue);
      // Same instant expressed as a local DateTime compares identically.
      expect(clock.isPast(DateTime.utc(2026, 6, 15, 11, 59).toLocal()), isTrue);
    });

    test('isPast is false for an instant after now', () {
      expect(clock.isPast(DateTime.utc(2026, 6, 15, 12, 1)), isFalse);
    });

    test('isUpcoming is inclusive of exactly now', () {
      expect(clock.isUpcoming(nowUtc), isTrue);
      expect(clock.isUpcoming(DateTime.utc(2026, 6, 15, 11, 59)), isFalse);
    });

    test('hasStarted flips at the start instant', () {
      expect(clock.hasStarted(DateTime.utc(2026, 6, 15, 12, 0)), isTrue);
      expect(clock.hasStarted(DateTime.utc(2026, 6, 15, 12, 1)), isFalse);
    });

    test('instant comparison is independent of the gym offset', () {
      final a = GymClock(fixedNow: nowUtc, gymOffset: const Duration(hours: 9));
      final b =
          GymClock(fixedNow: nowUtc, gymOffset: const Duration(hours: -5));
      final start = DateTime.utc(2026, 6, 15, 13, 0);
      expect(a.isUpcoming(start), b.isUpcoming(start));
    });
  });

  group('gym-local calendar bucketing (timezone-sensitive)', () {
    test('isGymToday respects the gym offset across the date line', () {
      // now = 2026-06-15 23:30 UTC.
      final now = DateTime.utc(2026, 6, 15, 23, 30);
      // A class at 2026-06-16 00:30 UTC.
      final classInstant = DateTime.utc(2026, 6, 16, 0, 30);

      // Gym at UTC+2: now is 16th 01:30, class is 16th 02:30 → same gym day.
      final plus2 = GymClock(fixedNow: now, gymOffset: const Duration(hours: 2));
      expect(plus2.isGymToday(classInstant), isTrue);

      // Gym at UTC-2: now is 15th 21:30, class is 15th 22:30 → same gym day too,
      // but a class at 15th 21:00 UTC (15th 19:00 local) is also "today"…
      final minus2 =
          GymClock(fixedNow: now, gymOffset: const Duration(hours: -2));
      expect(minus2.isGymToday(DateTime.utc(2026, 6, 15, 21, 0)), isTrue);
    });

    test('same instant lands in different gym days under different offsets', () {
      final now = DateTime.utc(2026, 6, 15, 12, 0);
      final instant = DateTime.utc(2026, 6, 15, 23, 30); // 23:30 UTC

      // UTC+0: still the 15th.
      expect(
        GymClock(fixedNow: now, gymOffset: Duration.zero).isGymToday(instant),
        isTrue,
      );
      // UTC+1: instant is 16th 00:30 → NOT the 15th.
      expect(
        GymClock(fixedNow: now, gymOffset: const Duration(hours: 1))
            .isGymToday(instant),
        isFalse,
      );
    });

    test('isInGymWeek uses gym-local Monday boundaries (inclusive start)', () {
      // now Monday 2026-06-15 12:00 UTC, gym at UTC+0.
      final clock = GymClock(fixedNow: nowUtc, gymOffset: Duration.zero);
      // Monday 00:00 of this week is included…
      expect(clock.isInGymWeek(DateTime.utc(2026, 6, 15, 0, 0)), isTrue);
      // Sunday 23:59 is the last moment in week…
      expect(clock.isInGymWeek(DateTime.utc(2026, 6, 21, 23, 59)), isTrue);
      // Next Monday 00:00 is excluded.
      expect(clock.isInGymWeek(DateTime.utc(2026, 6, 22, 0, 0)), isFalse);
      // Previous Sunday excluded.
      expect(clock.isInGymWeek(DateTime.utc(2026, 6, 14, 23, 59)), isFalse);
    });

    test('week boundary shifts with the gym offset', () {
      // now Monday 2026-06-15 12:00 UTC.
      // An instant at Monday 2026-06-15 00:30 UTC.
      final instant = DateTime.utc(2026, 6, 15, 0, 30);
      // UTC+0: it's Monday this week → in week.
      expect(
        GymClock(fixedNow: nowUtc, gymOffset: Duration.zero)
            .isInGymWeek(instant),
        isTrue,
      );
      // UTC-2: 00:30 UTC is Sunday 22:30 local → previous week → not in week.
      expect(
        GymClock(fixedNow: nowUtc, gymOffset: const Duration(hours: -2))
            .isInGymWeek(instant),
        isFalse,
      );
    });

    test('gymPeriodOf buckets by gym-local hour', () {
      final clock = GymClock(fixedNow: nowUtc, gymOffset: Duration.zero);
      expect(clock.gymPeriodOf(DateTime.utc(2026, 6, 15, 0, 0)),
          SchedulePeriod.morning);
      expect(clock.gymPeriodOf(DateTime.utc(2026, 6, 15, 11, 59)),
          SchedulePeriod.morning);
      expect(clock.gymPeriodOf(DateTime.utc(2026, 6, 15, 12, 0)),
          SchedulePeriod.afternoon);
      expect(clock.gymPeriodOf(DateTime.utc(2026, 6, 15, 16, 59)),
          SchedulePeriod.afternoon);
      expect(clock.gymPeriodOf(DateTime.utc(2026, 6, 15, 17, 0)),
          SchedulePeriod.evening);
      expect(clock.gymPeriodOf(DateTime.utc(2026, 6, 15, 23, 0)),
          SchedulePeriod.evening);
    });

    test('gymPeriodOf shifts with the gym offset', () {
      // 18:00 UTC is evening at UTC+0…
      final instant = DateTime.utc(2026, 6, 15, 18, 0);
      expect(
        GymClock(fixedNow: nowUtc, gymOffset: Duration.zero)
            .gymPeriodOf(instant),
        SchedulePeriod.evening,
      );
      // …but morning at UTC-12 (06:00 local).
      expect(
        GymClock(fixedNow: nowUtc, gymOffset: const Duration(hours: -12))
            .gymPeriodOf(instant),
        SchedulePeriod.morning,
      );
    });

    test('isInGymMonth respects offset at a month boundary', () {
      // now 2026-07-01 00:30 UTC.
      final now = DateTime.utc(2026, 7, 1, 0, 30);
      final instant = DateTime.utc(2026, 6, 30, 23, 30); // end of June UTC

      // UTC+0: now is July, instant is June → different month.
      expect(
        GymClock(fixedNow: now, gymOffset: Duration.zero)
            .isInGymMonth(instant),
        isFalse,
      );
      // UTC-2: now is June 30 22:30, instant is June 30 21:30 → same (June).
      expect(
        GymClock(fixedNow: now, gymOffset: const Duration(hours: -2))
            .isInGymMonth(instant),
        isTrue,
      );
    });
  });
}
