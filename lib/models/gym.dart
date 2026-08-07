import 'package:cloud_firestore/cloud_firestore.dart';

class Gym {
  const Gym({
    required this.id,
    required this.name,
    this.description = '',
    this.address = '',
    this.logoUrl = '',
    this.latitude,
    this.longitude,
    required this.adminUid,
    required this.adminEmail,
    required this.status,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String name;
  final String description;
  final String address;
  final String logoUrl;

  /// Gym's geographic coordinates, set by staff when placing it on the map.
  /// Null when the gym hasn't been located yet.
  final double? latitude;
  final double? longitude;

  final String adminUid;
  final String adminEmail;

  /// 'active' | 'suspended'
  final String status;
  final DateTime createdAt;

  /// UID of the super admin who created this gym
  final String createdBy;

  bool get isActive => status == 'active';

  /// Whether this gym has been placed on the map.
  bool get hasLocation => latitude != null && longitude != null;

  factory Gym.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return Gym(
      id: snapshot.id,
      name: (data['name'] ?? '') as String,
      description: (data['description'] ?? '') as String,
      address: (data['address'] ?? '') as String,
      logoUrl: (data['logoUrl'] ?? '') as String,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      adminUid: (data['adminUid'] ?? '') as String,
      adminEmail: (data['adminEmail'] ?? '') as String,
      status: (data['status'] ?? 'active') as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: (data['createdBy'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'description': description,
        'address': address,
        'logoUrl': logoUrl,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'adminUid': adminUid,
        'adminEmail': adminEmail,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdBy': createdBy,
      };

  Gym copyWith({
    String? name,
    String? description,
    String? address,
    String? logoUrl,
    double? latitude,
    double? longitude,
    String? adminUid,
    String? adminEmail,
    String? status,
  }) {
    return Gym(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      address: address ?? this.address,
      logoUrl: logoUrl ?? this.logoUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      adminUid: adminUid ?? this.adminUid,
      adminEmail: adminEmail ?? this.adminEmail,
      status: status ?? this.status,
      createdAt: createdAt,
      createdBy: createdBy,
    );
  }
}
