import 'package:cloud_firestore/cloud_firestore.dart';

class UserSubscription {
  const UserSubscription({
    required this.id,
    required this.userId,
    required this.planId,
    required this.totalAmount,
    required this.amountPaid,
    required this.currency,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.paymentHistory,
    this.gymId = '',
    this.updatedAt,
  });

  factory UserSubscription.empty() {
    return const UserSubscription(
      id: '',
      userId: '',
      planId: '',
      totalAmount: 0,
      amountPaid: 0,
      currency: '',
      status: '',
      startDate: null,
      endDate: null,
      paymentHistory: [],
      gymId: '',
      updatedAt: null,
    );
  }

  final String id;
  final String userId;
  final String planId;
  final int totalAmount;
  final int amountPaid;
  final String currency;
  final String status; // 'active', 'pending', 'cancelled'
  final DateTime? startDate;
  final DateTime? endDate;
  final List<PaymentRecord> paymentHistory;
  final String gymId;
  final DateTime? updatedAt;

  int get remainingAmount => totalAmount - amountPaid;
  double get paymentPercentage =>
      totalAmount > 0 ? amountPaid / totalAmount : 0;

  factory UserSubscription.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final paymentHistoryData = (data['paymentHistory'] ?? []) as List<dynamic>;
    final paymentHistory = paymentHistoryData
        .map((e) => PaymentRecord.fromMap(e as Map<String, dynamic>))
        .toList();

    return UserSubscription(
      id: snapshot.id,
      userId: (data['userId'] ?? '') as String,
      planId: (data['planId'] ?? '') as String,
      totalAmount: (data['totalAmount'] as num? ?? 0).toInt(),
      amountPaid: (data['amountPaid'] as num? ?? 0).toInt(),
      currency: (data['currency'] ?? 'EUR') as String,
      status: (data['status'] ?? 'pending') as String,
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      paymentHistory: paymentHistory,
      gymId: (data['gymId'] ?? '') as String,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'userId': userId,
      'planId': planId,
      'totalAmount': totalAmount,
      'amountPaid': amountPaid,
      'currency': currency,
      'status': status,
      'startDate': startDate,
      'endDate': endDate,
      'paymentHistory': paymentHistory.map((p) => p.toMap()).toList(),
      'gymId': gymId,
      'updatedAt': updatedAt,
    };
  }
}

class PaymentRecord {
  const PaymentRecord({
    required this.amount,
    required this.date,
    required this.method,
    required this.notes,
  });

  final int amount;
  final DateTime date;
  final String method; // 'cash', 'card', 'transfer', etc.
  final String notes;

  factory PaymentRecord.fromMap(Map<String, dynamic> map) {
    return PaymentRecord(
      amount: (map['amount'] as num? ?? 0).toInt(),
      date: (map['date'] as Timestamp).toDate(),
      method: (map['method'] ?? 'cash') as String,
      notes: (map['notes'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'amount': amount,
      'date': date,
      'method': method,
      'notes': notes,
    };
  }
}
