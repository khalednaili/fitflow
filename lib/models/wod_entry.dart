import 'package:cloud_firestore/cloud_firestore.dart';

class WodExercise {
  const WodExercise({
    required this.name,
    this.sets = '',
    this.reps = '',
    this.weight = '',
    this.notes = '',
  });

  final String name;
  final String sets;
  final String reps;
  final String weight;
  final String notes;

  factory WodExercise.fromMap(Map<String, dynamic> m) => WodExercise(
        name: (m['name'] ?? '') as String,
        sets: (m['sets'] ?? '') as String,
        reps: (m['reps'] ?? '') as String,
        weight: (m['weight'] ?? '') as String,
        notes: (m['notes'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'sets': sets,
        'reps': reps,
        'weight': weight,
        'notes': notes,
      };

  String get shortLabel {
    final parts = <String>[];
    if (sets.isNotEmpty && reps.isNotEmpty) parts.add('$sets×$reps');
    if (weight.isNotEmpty) parts.add(weight);
    return parts.join(' ');
  }
}

class WodScale {
  const WodScale({
    required this.label,
    this.description = '',
    this.exercises = const [],
  });

  final String label;
  final String description;
  final List<WodExercise> exercises;

  factory WodScale.fromMap(Map<String, dynamic> m) => WodScale(
        label: (m['label'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        exercises: ((m['exercises'] as List<dynamic>?) ?? [])
            .map(
                (e) => WodExercise.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'label': label,
        'description': description,
        'exercises': exercises.map((e) => e.toMap()).toList(),
      };
}

// ── WodPart ───────────────────────────────────────────────────────────────────

/// A single section/block within a WOD (e.g. "Part A – Strength").
class WodPart {
  const WodPart({
    required this.title,
    this.format = '',
    this.measure = '',
    this.timeCap = '',
    this.description = '',
    this.exercises = const [],
    this.scales = const [],
  });

  final String title;

  /// Format for this part: AMRAP, For Time, EMOM, etc.
  final String format;
  final String measure;

  /// Optional time cap (e.g. "20 min").
  final String timeCap;

  /// Instructions / description for this part.
  final String description;

  final List<WodExercise> exercises;
  final List<WodScale> scales;

  factory WodPart.fromMap(Map<String, dynamic> m) => WodPart(
        title: (m['title'] ?? '') as String,
        format: (m['format'] ?? '') as String,
        measure: (m['measure'] ?? '') as String,
        timeCap: (m['timeCap'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        exercises: ((m['exercises'] as List<dynamic>?) ?? [])
            .map(
                (e) => WodExercise.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        scales: ((m['scales'] as List<dynamic>?) ?? [])
            .map((s) => WodScale.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'format': format,
        'measure': measure,
        'timeCap': timeCap,
        'description': description,
        'exercises': exercises.map((e) => e.toMap()).toList(),
        'scales': scales.map((s) => s.toMap()).toList(),
      };
}

// ── WodEntry ──────────────────────────────────────────────────────────────────

class WodEntry {
  const WodEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    this.exercises = const [],
    this.createdBy = '',
    this.createdAt,
    this.classTypeId = '',
    this.classTypeName = '',
    this.format = '',
    this.timeCap = '',
    this.memberNote = '',
    this.coachNote = '',
    this.gymId = '',
    this.parts = const [],
  });

  final String id;
  final String title;
  final String description;
  final DateTime date;

  /// Legacy flat exercise list (kept for backward compatibility).
  final List<WodExercise> exercises;
  final String createdBy;
  final DateTime? createdAt;

  /// The class type this workout is assigned to (e.g. WOD, FBB, EMOM).
  final String classTypeId;
  final String classTypeName;

  /// Legacy single format (kept for backward compatibility).
  final String format;

  /// Legacy time cap (kept for backward compatibility).
  final String timeCap;
  final String memberNote;

  /// Private note visible only to coaches and admins.
  final String coachNote;
  final String gymId;

  /// Multi-part structure. When non-empty this is the primary representation.
  final List<WodPart> parts;

  factory WodEntry.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return WodEntry(
      id: snap.id,
      title: (d['title'] ?? '') as String,
      description: (d['description'] ?? '') as String,
      date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      exercises: ((d['exercises'] as List<dynamic>?) ?? [])
          .map((e) => WodExercise.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      createdBy: (d['createdBy'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      classTypeId: (d['classTypeId'] ?? '') as String,
      classTypeName: (d['classTypeName'] ?? '') as String,
      format: (d['format'] ?? '') as String,
      timeCap: (d['timeCap'] ?? '') as String,
      memberNote: (d['memberNote'] ?? '') as String,
      coachNote: (d['coachNote'] ?? '') as String,
      gymId: (d['gymId'] ?? '') as String,
      parts: ((d['parts'] as List<dynamic>?) ?? [])
          .map((p) => WodPart.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'exercises': exercises.map((e) => e.toMap()).toList(),
        'createdBy': createdBy,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'classTypeId': classTypeId,
        'classTypeName': classTypeName,
        'format': format,
        'timeCap': timeCap,
        'memberNote': memberNote,
        'coachNote': coachNote,
        'gymId': gymId,
        'parts': parts.map((p) => p.toMap()).toList(),
      };
}

class WodScore {
  const WodScore({
    required this.id,
    required this.wodId,
    required this.userId,
    required this.score,
    this.notes = '',
    this.loggedAt,
    this.scale = '',
    this.scoreType = 'custom',
    this.feeling = 0,
  });

  final String id;
  final String wodId;
  final String userId;
  final String score;
  final String notes;
  final DateTime? loggedAt;

  /// 'rx' | 'scaled' | 'masters' | ''
  final String scale;

  /// 'time' | 'rounds_reps' | 'reps' | 'weight' | 'custom'
  final String scoreType;

  /// 0 = not set, 1–5 = feeling emoji (💀😓😐💪🔥)
  final int feeling;

  factory WodScore.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return WodScore(
      id: snap.id,
      wodId: (d['wodId'] ?? '') as String,
      userId: (d['userId'] ?? '') as String,
      score: (d['score'] ?? '') as String,
      notes: (d['notes'] ?? '') as String,
      loggedAt: (d['loggedAt'] as Timestamp?)?.toDate(),
      scale: (d['scale'] ?? '') as String,
      scoreType: (d['scoreType'] ?? 'custom') as String,
      feeling: (d['feeling'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'wodId': wodId,
        'userId': userId,
        'score': score,
        'notes': notes,
        'loggedAt': FieldValue.serverTimestamp(),
        'scale': scale,
        'scoreType': scoreType,
        'feeling': feeling,
      };
}
