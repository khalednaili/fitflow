import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/utils/exercise_list.dart';

void main() {
  group('kPredefinedExercises', () {
    test('is not empty', () {
      expect(kPredefinedExercises, isNotEmpty);
    });

    test('has no duplicate entries', () {
      expect(kPredefinedExercises.toSet().length, kPredefinedExercises.length);
    });

    test('has no blank or whitespace-only entries', () {
      for (final exercise in kPredefinedExercises) {
        expect(exercise.trim(), isNotEmpty);
      }
    });

    test('entries have no leading/trailing whitespace', () {
      for (final exercise in kPredefinedExercises) {
        expect(exercise, exercise.trim());
      }
    });

    test('includes core barbell lifts', () {
      expect(
        kPredefinedExercises,
        containsAll(<String>[
          'Back Squat',
          'Front Squat',
          'Deadlift',
          'Bench Press',
          'Overhead Press',
        ]),
      );
    });

    test('includes Olympic lifts', () {
      expect(
        kPredefinedExercises,
        containsAll(<String>[
          'Clean',
          'Power Clean',
          'Clean & Jerk',
          'Snatch',
          'Power Snatch',
        ]),
      );
    });

    test('includes gymnastics/bodyweight movements', () {
      expect(
        kPredefinedExercises,
        containsAll(<String>[
          'Strict Pull-up',
          'Muscle-up',
          'Handstand Push-up',
          'Toes-to-Bar',
        ]),
      );
    });
  });

  group('searchExercises', () {
    test('returns the full list when the query is blank', () {
      expect(searchExercises(''), kPredefinedExercises);
      expect(searchExercises('   '), kPredefinedExercises);
    });

    test('matches case-insensitively', () {
      final results = searchExercises('back squat');
      expect(results, contains('Back Squat'));
    });

    test('matches a substring anywhere in the name', () {
      final results = searchExercises('press');
      expect(
        results,
        containsAll(<String>[
          'Bench Press',
          'Incline Bench Press',
          'Overhead Press',
          'Push Press',
        ]),
      );
      expect(results, isNot(contains('Deadlift')));
    });

    test('returns an empty list when nothing matches', () {
      expect(searchExercises('zzz-not-a-real-exercise'), isEmpty);
    });

    test('supports a custom source list', () {
      final custom = ['Foo Bar', 'Baz'];
      expect(searchExercises('foo', source: custom), ['Foo Bar']);
      expect(searchExercises('', source: custom), custom);
    });
  });
}
