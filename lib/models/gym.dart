import 'package:cloud_firestore/cloud_firestore.dart';

class Gym {
  const Gym({
    required this.id,
    required this.name,
    this.description = '',
    this.address = '',
    this.logoUrl = '',
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
  final String adminUid;
  final String adminEmail;

  /// 'active' | 'suspended'
  final String status;
  final DateTime createdAt;

  /// UID of the super admin who created this gym
  final String createdBy;

  bool get isActive => status == 'active';

  factory Gym.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return Gym(
      id: snapshot.id,
      name: (data['name'] ?? '') as String,
      description: (data['description'] ?? '') as String,
      address: (data['address'] ?? '') as String,
      logoUrl: (data['logoUrl'] ?? '') as String,
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
      adminUid: adminUid ?? this.adminUid,
      adminEmail: adminEmail ?? this.adminEmail,
      status: status ?? this.status,
      createdAt: createdAt,
      createdBy: createdBy,
    );
  }
}
