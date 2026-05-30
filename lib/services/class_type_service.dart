import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/class_type.dart';

class ClassTypeService {
  ClassTypeService({this.gymId = '', FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _firestore;

  /// Streams class types for this gym PLUS any legacy types with no gymId.
  Stream<List<ClassType>> streamClassTypes() {
    return _firestore
        .collection('classTypes')
        .orderBy('name')
        .snapshots()
        .map((snap) {
      final all = snap.docs.map(ClassType.fromSnapshot).toList();
      if (gymId.isEmpty) return all;
      // Show this gym's types + legacy docs that have no gymId
      return all
          .where((t) => t.gymId.isEmpty || t.gymId == gymId)
          .toList();
    });
  }

  Future<void> addClassType({required String name, int? colorValue}) async {
    await _firestore.collection('classTypes').add(<String, dynamic>{
      'name': name.trim(),
      'colorValue': colorValue,
      'gymId': gymId,
      'createdAt': Timestamp.now(),
    });
  }

  Future<void> updateClassType({
    required String id,
    required String name,
    int? colorValue,
  }) async {
    await _firestore.collection('classTypes').doc(id).update(<String, dynamic>{
      'name': name.trim(),
      'colorValue': colorValue,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteClassType(String id) async {
    await _firestore.collection('classTypes').doc(id).delete();
  }
}
