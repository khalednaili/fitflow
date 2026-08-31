/// Common exercise names offered when a member logs a personal record.
/// Members may also enter a custom exercise name.
const List<String> kPredefinedExercises = [
  // ── Squats ────────────────────────────────────────────────────────────
  'Back Squat',
  'Front Squat',
  'Overhead Squat',

  // ── Deadlifts ─────────────────────────────────────────────────────────
  'Deadlift',
  'Sumo Deadlift',
  'Romanian Deadlift',
  'Trap Bar Deadlift',

  // ── Presses ───────────────────────────────────────────────────────────
  'Bench Press',
  'Incline Bench Press',
  'Overhead Press',
  'Push Press',
  'Push Jerk',
  'Split Jerk',

  // ── Olympic lifts ─────────────────────────────────────────────────────
  'Clean',
  'Power Clean',
  'Hang Clean',
  'Clean & Jerk',
  'Snatch',
  'Power Snatch',
  'Hang Snatch',
  'Snatch Balance',

  // ── Pulls & gymnastics ────────────────────────────────────────────────
  'Strict Pull-up',
  'Kipping Pull-up',
  'Chest-to-Bar Pull-up',
  'Muscle-up',
  'Handstand Push-up',
  'Toes-to-Bar',
  'Bent-over Row',

  // ── Other ─────────────────────────────────────────────────────────────
  'Thruster',
  'Hip Thrust',
  'Farmer\'s Carry',
];

/// Returns the exercises from [kPredefinedExercises] whose name contains
/// [query] (case-insensitive). Returns the full list when [query] is blank.
List<String> searchExercises(String query, {List<String>? source}) {
  final exercises = source ?? kPredefinedExercises;
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return List.unmodifiable(exercises);
  return exercises
      .where((e) => e.toLowerCase().contains(trimmed))
      .toList(growable: false);
}

