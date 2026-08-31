import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.roles = const [],
    required this.membershipPlanId,
    required this.subscriptionStatus,
    this.gymId = '',
    this.gymIds = const [],
    this.phoneNumber = '',
    this.photoUrl = '',
    this.gender = '',
    this.dateOfBirth,
    this.fitnessLevel = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.healthNotes = '',
    this.joinDate,
    this.cinNumber = '',
    this.address = '',
    this.adminNote = '',
    this.preferredWeightUnit = 'kg',
  });

  final String id;
  final String email;
  final String displayName;

  /// Primary (highest-priority) role — kept for backward compat.
  final String role;

  /// All roles assigned to this user.
  final List<String> roles;

  final String membershipPlanId;
  final String subscriptionStatus;

  /// The gym currently "active"/selected for this user — drives which gym's
  /// classes/bookings/products/etc. they see. Empty for super_admin accounts.
  final String gymId;

  /// All gyms this member currently belongs to (multi-gym membership).
  /// Falls back to [gymId] when empty for backward compatibility.
  final List<String> gymIds;

  // Personal info
  final String phoneNumber;
  final String photoUrl;
  final String gender;
  final DateTime? dateOfBirth;

  // Fitness profile
  final String fitnessLevel;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String healthNotes;

  // Identity & location
  final String cinNumber;
  final String address;

  // Admin-only fields
  final String adminNote;

  // Metadata
  final DateTime? joinDate;

  /// Default unit ('kg' or 'lbs') used to display/log personal records and
  /// workout percentages. Can be overridden per personal-record entry.
  final String preferredWeightUnit;

  /// All effective roles — falls back to [role] when [roles] is empty.
  List<String> get effectiveRoles =>
      roles.isNotEmpty ? roles : [role.isEmpty ? 'member' : role];

  bool get isSuperAdmin => effectiveRoles.contains('super_admin');
  bool get isAdmin =>
      effectiveRoles.contains('admin') || effectiveRoles.contains('owner');
  bool get isStaff => effectiveRoles.contains('staff');
  bool get isCoach => effectiveRoles.contains('coach');

  /// All gyms the member belongs to (deduped, `gymId` first). Falls back to
  /// [gymId] alone when [gymIds] hasn't been populated yet.
  List<String> get effectiveGymIds {
    final combined = <String>[
      if (gymId.isNotEmpty) gymId,
      ...gymIds.where((g) => g.isNotEmpty),
    ];
    return combined.toSet().toList();
  }

  bool get isMultiGymMember => effectiveGymIds.length > 1;

  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    int age = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month ||
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      age--;
    }
    return age;
  }

  factory AppUser.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawRole = (data['role'] ?? 'member') as String;
    final rawRoles = (data['roles'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    // Backward compat: if no roles array, derive from legacy role field
    final effectiveRoles =
        rawRoles.isNotEmpty ? rawRoles : [rawRole.isEmpty ? 'member' : rawRole];
    // Primary role = highest priority
    final primaryRole = _primaryRole(effectiveRoles);
    return AppUser(
      id: snapshot.id,
      email: (data['email'] ?? '') as String,
      displayName: (data['displayName'] ?? '') as String,
      role: primaryRole,
      roles: effectiveRoles,
      membershipPlanId: (data['membershipPlanId'] ?? '') as String,
      subscriptionStatus: (data['subscriptionStatus'] ?? 'none') as String,
      gymId: (data['gymId'] ?? '') as String,
      gymIds: (data['gymIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      phoneNumber: (data['phoneNumber'] ?? '') as String,
      photoUrl: (data['photoUrl'] ?? '') as String,
      gender: (data['gender'] ?? '') as String,
      dateOfBirth: (data['dateOfBirth'] as Timestamp?)?.toDate(),
      fitnessLevel: (data['fitnessLevel'] ?? '') as String,
      emergencyContactName: (data['emergencyContactName'] ?? '') as String,
      emergencyContactPhone: (data['emergencyContactPhone'] ?? '') as String,
      healthNotes: (data['healthNotes'] ?? '') as String,
      cinNumber: (data['cinNumber'] ?? '') as String,
      address: (data['address'] ?? '') as String,
      adminNote: (data['adminNote'] ?? '') as String,
      joinDate: (data['joinDate'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate(),
      preferredWeightUnit: (data['preferredWeightUnit'] ?? 'kg') as String,
    );
  }

  /// Priority: super_admin > admin > staff > coach > member
  static String _primaryRole(List<String> roles) {
    const priority = [
      'super_admin',
      'admin',
      'owner',
      'staff',
      'coach',
      'member'
    ];
    for (final p in priority) {
      if (roles.contains(p)) return p;
    }
    return roles.isNotEmpty ? roles.first : 'member';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'email': email,
      'displayName': displayName,
      'role': role,
      'roles': effectiveRoles,
      'gymId': gymId,
      'gymIds': effectiveGymIds,
      'membershipPlanId': membershipPlanId,
      'subscriptionStatus': subscriptionStatus,
      'phoneNumber': phoneNumber,
      'photoUrl': photoUrl,
      'gender': gender,
      if (dateOfBirth != null) 'dateOfBirth': Timestamp.fromDate(dateOfBirth!),
      'fitnessLevel': fitnessLevel,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'healthNotes': healthNotes,
      'cinNumber': cinNumber,
      'address': address,
      'adminNote': adminNote,
      'preferredWeightUnit': preferredWeightUnit,
    };
  }
}
