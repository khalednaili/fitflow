/// Part of the day a class falls in, used to group the schedule.
enum SchedulePeriod { morning, afternoon, evening }

/// Centralized, timezone-aware time logic for class scheduling.
///
/// Two distinct kinds of comparison:
///
/// * **Instant comparisons** (`isPast`, `isUpcoming`, `hasStarted`) are
///   timezone-AGNOSTIC. They compare absolute instants in UTC, so the result is
///   identical regardless of the device's timezone.
///
/// * **Calendar bucketing** (`isGymToday`, `isInGymWeek`, `isInGymMonth`) is
///   timezone-SENSITIVE. "Today"/"this week"/"this month" are computed in the
///   *gym's* timezone via a fixed UTC [gymOffset], so a member whose device is
///   in another timezone still sees the gym's calendar days rather than their
///   own. Fixed-offset only — DST transitions are not modeled.
///
/// All methods take their reference instant from [nowUtc], which is overridable
/// via the `fixedNow` constructor argument, making every branch deterministically
/// testable.
class GymClock {
  const GymClock({Duration? gymOffset, DateTime? fixedNow})
      : _gymOffset = gymOffset,
        _fixedNow = fixedNow;

  final Duration? _gymOffset;
  final DateTime? _fixedNow;

  /// Current instant in UTC (frozen when `fixedNow` is provided).
  DateTime nowUtc() => (_fixedNow ?? DateTime.now()).toUtc();

  /// The gym's UTC offset. Defaults to the device's current offset, so behavior
  /// is unchanged until a gym timezone is explicitly configured.
  Duration get gymOffset => _gymOffset ?? DateTime.now().timeZoneOffset;

  // ── Instant comparisons (timezone-agnostic) ───────────────────────────────

  /// True once [start] is at or before now.
  bool hasStarted(DateTime start) => !start.toUtc().isAfter(nowUtc());

  /// True once [end] is strictly before now (the class has finished).
  bool isPast(DateTime end) => end.toUtc().isBefore(nowUtc());

  /// True while [start] is at or after now (not yet started).
  bool isUpcoming(DateTime start) => !start.toUtc().isBefore(nowUtc());

  // ── Gym-local calendar (timezone-sensitive) ───────────────────────────────

  /// The gym-local "wall clock" for [instant]: a DateTime whose Y/M/D/H/M read
  /// as the gym's local time. (Returned value is for field access only.)
  DateTime _wall(DateTime instant) => instant.toUtc().add(gymOffset);

  bool isSameGymDay(DateTime a, DateTime b) {
    final wa = _wall(a);
    final wb = _wall(b);
    return wa.year == wb.year && wa.month == wb.month && wa.day == wb.day;
  }

  bool isGymToday(DateTime instant) => isSameGymDay(instant, nowUtc());

  /// The UTC instant of Monday 00:00 (gym-local) for the week containing
  /// [instant] (defaults to now).
  DateTime gymWeekStartUtc([DateTime? instant]) {
    final w = _wall(instant ?? nowUtc());
    // Monday 00:00 in gym-local wall-clock terms…
    final mondayWall = DateTime.utc(w.year, w.month, w.day)
        .subtract(Duration(days: w.weekday - 1));
    // …converted back to a real UTC instant.
    return mondayWall.subtract(gymOffset);
  }

  /// True when [instant] falls in the same gym-local week as [ofWeek] (now).
  bool isInGymWeek(DateTime instant, {DateTime? ofWeek}) {
    final startUtc = gymWeekStartUtc(ofWeek ?? nowUtc());
    final endUtc = startUtc.add(const Duration(days: 7));
    final i = instant.toUtc();
    return !i.isBefore(startUtc) && i.isBefore(endUtc);
  }

  /// True when [instant] falls in the same gym-local month as [ofMonth] (now).
  bool isInGymMonth(DateTime instant, {DateTime? ofMonth}) {
    final wi = _wall(instant);
    final wm = _wall(ofMonth ?? nowUtc());
    return wi.year == wm.year && wi.month == wm.month;
  }

  /// The part of the gym-local day [instant] falls in: morning (<12:00),
  /// afternoon (12:00–16:59) or evening (≥17:00).
  SchedulePeriod gymPeriodOf(DateTime instant) {
    final hour = _wall(instant).hour;
    if (hour < 12) return SchedulePeriod.morning;
    if (hour < 17) return SchedulePeriod.afternoon;
    return SchedulePeriod.evening;
  }
}
