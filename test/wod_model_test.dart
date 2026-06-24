import 'package:flutter_test/flutter_test.dart';
import 'package:fit_flow/models/wod_entry.dart';

void main() {
  // ── WodExercise ─────────────────────────────────────────────────────────────

  group('WodExercise', () {
    test('fromMap parses all fields', () {
      final ex = WodExercise.fromMap({
        'name': 'Back Squat',
        'sets': '5',
        'reps': '3',
        'weight': '100 kg',
        'notes': 'Keep chest up',
      });

      expect(ex.name, 'Back Squat');
      expect(ex.sets, '5');
      expect(ex.reps, '3');
      expect(ex.weight, '100 kg');
      expect(ex.notes, 'Keep chest up');
    });

    test('fromMap uses defaults for missing keys', () {
      final ex = WodExercise.fromMap({'name': 'Pull-up'});

      expect(ex.sets, '');
      expect(ex.reps, '');
      expect(ex.weight, '');
      expect(ex.notes, '');
    });

    test('toMap round-trips correctly', () {
      const ex = WodExercise(
        name: 'Deadlift',
        sets: '3',
        reps: '5',
        weight: '120 kg',
        notes: 'Flat back',
      );

      final map = ex.toMap();
      final restored = WodExercise.fromMap(map);

      expect(restored.name, ex.name);
      expect(restored.sets, ex.sets);
      expect(restored.reps, ex.reps);
      expect(restored.weight, ex.weight);
      expect(restored.notes, ex.notes);
    });

    test('shortLabel shows sets×reps and weight', () {
      const ex = WodExercise(name: 'Squat', sets: '3', reps: '5', weight: '80 kg');
      expect(ex.shortLabel, '3×5 80 kg');
    });

    test('shortLabel omits empty fields', () {
      const ex = WodExercise(name: 'Run', sets: '', reps: '', weight: '');
      expect(ex.shortLabel, '');
    });

    test('shortLabel shows only weight when sets/reps absent', () {
      const ex = WodExercise(name: 'KB Swing', sets: '', reps: '', weight: '24 kg');
      expect(ex.shortLabel, '24 kg');
    });
  });

  // ── WodScale ─────────────────────────────────────────────────────────────────

  group('WodScale', () {
    test('fromMap parses label and description', () {
      final scale = WodScale.fromMap({
        'label': 'Rx',
        'description': 'As prescribed',
        'exercises': <dynamic>[],
      });

      expect(scale.label, 'Rx');
      expect(scale.description, 'As prescribed');
      expect(scale.exercises, isEmpty);
    });

    test('fromMap parses nested exercises', () {
      final scale = WodScale.fromMap({
        'label': 'Intermediate',
        'description': '',
        'exercises': [
          {'name': 'Box Jump', 'sets': '', 'reps': '10', 'weight': '', 'notes': ''},
        ],
      });

      expect(scale.exercises, hasLength(1));
      expect(scale.exercises.first.name, 'Box Jump');
      expect(scale.exercises.first.reps, '10');
    });

    test('fromMap defaults to empty exercises when key absent', () {
      final scale = WodScale.fromMap({'label': 'Scaled'});
      expect(scale.exercises, isEmpty);
      expect(scale.description, '');
    });

    test('toMap round-trips correctly', () {
      const scale = WodScale(
        label: 'Rx+',
        description: 'Extra weight',
        exercises: [WodExercise(name: 'Muscle-up', sets: '3', reps: '5')],
      );

      final map = scale.toMap();
      final restored = WodScale.fromMap(map);

      expect(restored.label, scale.label);
      expect(restored.description, scale.description);
      expect(restored.exercises, hasLength(1));
      expect(restored.exercises.first.name, 'Muscle-up');
    });
  });

  // ── WodPart ──────────────────────────────────────────────────────────────────

  group('WodPart', () {
    test('fromMap parses title, format, measure, timeCap, description', () {
      final part = WodPart.fromMap({
        'title': 'Strength',
        'format': 'For Time',
        'measure': 'Pounds',
        'timeCap': '20 min',
        'description': 'Complete as fast as possible',
        'exercises': <dynamic>[],
        'scales': <dynamic>[],
      });

      expect(part.title, 'Strength');
      expect(part.format, 'For Time');
      expect(part.measure, 'Pounds');
      expect(part.timeCap, '20 min');
      expect(part.description, 'Complete as fast as possible');
      expect(part.exercises, isEmpty);
      expect(part.scales, isEmpty);
    });

    test('fromMap parses top-level exercises', () {
      final part = WodPart.fromMap({
        'title': 'Metcon',
        'exercises': [
          {'name': 'Thruster', 'sets': '', 'reps': '21', 'weight': '43 kg', 'notes': ''},
        ],
        'scales': <dynamic>[],
      });

      expect(part.exercises, hasLength(1));
      expect(part.exercises.first.name, 'Thruster');
    });

    // ── Regression: scales were not rendered (bug fixed in a236461) ────────────

    test('fromMap parses scales list', () {
      final part = WodPart.fromMap({
        'title': 'WOD',
        'exercises': <dynamic>[],
        'scales': [
          {
            'label': 'Rx',
            'description': 'As prescribed',
            'exercises': [
              {'name': 'Clean', 'sets': '', 'reps': '5', 'weight': '60 kg', 'notes': ''},
            ],
          },
          {
            'label': 'Intermediate',
            'description': 'Reduce load',
            'exercises': [
              {'name': 'Clean', 'sets': '', 'reps': '5', 'weight': '40 kg', 'notes': ''},
            ],
          },
        ],
      });

      expect(part.scales, hasLength(2));
      expect(part.scales[0].label, 'Rx');
      expect(part.scales[0].exercises.first.weight, '60 kg');
      expect(part.scales[1].label, 'Intermediate');
      expect(part.scales[1].exercises.first.weight, '40 kg');
    });

    test('part with only scales (no top-level exercises) preserves data', () {
      // This mirrors the real-world scenario that caused the whiteboard bug:
      // content stored exclusively in scales, exercises list empty.
      final part = WodPart.fromMap({
        'title': 'AMRAP 12',
        'format': 'AMRAP',
        'measure': 'Rounds + Reps',
        'exercises': <dynamic>[],
        'scales': [
          {
            'label': 'Rx',
            'description': '5 Pull-ups\n10 Push-ups\n15 Air Squats',
            'exercises': <dynamic>[],
          },
          {
            'label': 'Scaled',
            'description': '5 Ring Rows\n10 Knee Push-ups\n15 Air Squats',
            'exercises': <dynamic>[],
          },
        ],
      });

      expect(part.exercises, isEmpty,
          reason: 'Top-level exercises should be empty');
      expect(part.scales, hasLength(2),
          reason: 'Scales must survive deserialization');
      expect(part.scales[0].description, contains('Pull-ups'));
      expect(part.scales[1].description, contains('Ring Rows'));
      expect(part.measure, 'Rounds + Reps');
    });

    test('toMap round-trips scales correctly', () {
      const part = WodPart(
        title: 'Strength',
        format: 'For Time',
        measure: 'Kilograms',
        timeCap: '15 min',
        description: '',
        exercises: [],
        scales: [
          WodScale(
            label: 'Rx',
            description: 'Heavy',
            exercises: [WodExercise(name: 'Snatch', reps: '3')],
          ),
        ],
      );

      final map = part.toMap();
      final restored = WodPart.fromMap(map);

      expect(restored.title, part.title);
      expect(restored.measure, part.measure);
      expect(restored.scales, hasLength(1));
      expect(restored.scales.first.label, 'Rx');
      expect(restored.scales.first.exercises.first.name, 'Snatch');
    });

    test('fromMap defaults to empty lists when keys absent', () {
      final part = WodPart.fromMap({'title': 'Minimal'});

      expect(part.exercises, isEmpty);
      expect(part.scales, isEmpty);
      expect(part.format, '');
      expect(part.measure, '');
      expect(part.timeCap, '');
      expect(part.description, '');
    });
  });
}
