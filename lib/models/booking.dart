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
    this.dropInPrice = 0.0,
    this.gymId = '',
    this.usedPlanId = '',
    this.classStartTime,
    this.classEndTime,
    this.classTypeId = '',
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

  /// Drop-in fee charged at booking time, snapshotted so revenue reporting is
  /// not affected by later edits to the class's `dropInPrice`. 0 for
  /// non-drop-in bookings (and legacy drop-ins created before this field).
  final double dropInPrice;
  final String gymId;
  /// The planId of the subscription that was consumed for this booking.
  /// Used to isolate per-offer check-in counters when a member holds
  /// multiple simultaneous offers.
  final String usedPlanId;
  /// Start/end times of the class — stored on the booking so overlap checks
  /// can be done without fetching every booked class document.
  final DateTime? classStartTime;
  final DateTime? classEndTime;
  /// ClassType ID of the booked class. Empty when the class has no type set.
  final String classTypeId;

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
      dropInPrice: ((data['dropInPrice'] ?? 0) as num).toDouble(),
      gymId: (data['gymId'] ?? '') as String,
      usedPlanId: (data['usedPlanId'] ?? '') as String,
      classStartTime: (data['classStartTime'] as Timestamp?)?.toDate(),
      classEndTime: (data['classEndTime'] as Timestamp?)?.toDate(),
      classTypeId: (data['classTypeId'] ?? '') as String,
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
      'dropInPrice': dropInPrice,
      'gymId': gymId,
      'usedPlanId': usedPlanId,
      if (classStartTime != null)
        'classStartTime': Timestamp.fromDate(classStartTime!),
      if (classEndTime != null)
        'classEndTime': Timestamp.fromDate(classEndTime!),
      'classTypeId': classTypeId,
    };
  }
}
