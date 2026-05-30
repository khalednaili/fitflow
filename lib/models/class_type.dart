import 'package:cloud_firestore/cloud_firestore.dart';

class ClassType {
  const ClassType({
    required this.id,
    required this.name,
    this.colorValue,
    this.gymId = '',
  });

  final String id;
  final String name;
  final int? colorValue;
  final String gymId;

  factory ClassType.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final parsedColorValue = data['colorValue'];
    return ClassType(
      id: snapshot.id,
      name: (data['name'] ?? '') as String,
      colorValue: parsedColorValue is int
          ? parsedColorValue
          : (parsedColorValue is num ? parsedColorValue.toInt() : null),
      gymId: (data['gymId'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'colorValue': colorValue,
        'gymId': gymId,
      };
}
