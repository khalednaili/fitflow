import 'package:cloud_firestore/cloud_firestore.dart';

class Booking {
  const Booking({
    required this.id,
    required this.userId,
    required this.classId,
    required this.createdAt,
    this.memberName = '',
    this.guestEmail = '',
    this.checkedIn = false,
    this.checkedInAt,
    this.isDropIn = false,
    this.dropInPaymentStatus = 'pending',
    this.gymId = '',
  });

  final String id;
  final String userId;
  final String classId;
  final DateTime createdAt;
  final String memberName;

  /// Email stored for non-member (guest) drop-ins.
  final String guestEmail;
  final bool checkedIn;
  final DateTime? checkedInAt;
  final bool isDropIn;
  final String dropInPaymentStatus;
  final String gymId;

  bool get isGuest => userId.isEmpty && guestEmail.isNotEmpty;

  factory Booking.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return Booking(
      id: snapshot.id,
      userId: (data['userId'] ?? '') as String,
      classId: (data['classId'] ?? '') as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      memberName: (data['memberName'] ?? '') as String,
      guestEmail: (data['guestEmail'] ?? '') as String,
      checkedIn: (data['checkedIn'] ?? false) as bool,
      checkedInAt: (data['checkedInAt'] as Timestamp?)?.toDate(),
      isDropIn: (data['isDropIn'] ?? false) as bool,
      dropInPaymentStatus: (data['dropInPaymentStatus'] ?? 'pending') as String,
      gymId: (data['gymId'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'userId': userId,
      'classId': classId,
      'createdAt': Timestamp.fromDate(createdAt),
      'memberName': memberName,
      'guestEmail': guestEmail,
      'checkedIn': checkedIn,
      if (checkedInAt != null) 'checkedInAt': Timestamp.fromDate(checkedInAt!),
      'isDropIn': isDropIn,
      'dropInPaymentStatus': dropInPaymentStatus,
      'gymId': gymId,
    };
  }
}
