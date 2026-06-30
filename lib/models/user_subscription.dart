import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/currency.dart';

// ── ScheduledInstalment ───────────────────────────────────────────────────────

/// One instalment in a multi-part payment plan.
class ScheduledInstalment {
  const ScheduledInstalment({
    required this.id,
    required this.amount,
    required this.dueDate,
    required this.method,
    this.notes = '',
    this.paid = false,
    this.paidAt,
    this.paidBy = '',
  });

  final String id;
  final int amount;
  final DateTime dueDate;
  final String method; // 'cash' | 'card' | 'transfer' | 'cheque'
  final String notes;
  final bool paid;
  final DateTime? paidAt;
  final String paidBy;

  bool get isOverdue =>
      !paid && dueDate.isBefore(DateTime.now());

  ScheduledInstalment copyWith({
    int? amount,
    DateTime? dueDate,
    String? method,
    String? notes,
    bool? paid,
    DateTime? paidAt,
    String? paidBy,
  }) =>
      ScheduledInstalment(
        id: id,
        amount: amount ?? this.amount,
        dueDate: dueDate ?? this.dueDate,
        method: method ?? this.method,
        notes: notes ?? this.notes,
        paid: paid ?? this.paid,
        paidAt: paidAt ?? this.paidAt,
        paidBy: paidBy ?? this.paidBy,
      );

  factory ScheduledInstalment.fromMap(Map<String, dynamic> m) =>
      ScheduledInstalment(
        id: (m['id'] ?? '') as String,
        amount: (m['amount'] as num? ?? 0).toInt(),
        dueDate: (m['dueDate'] as Timestamp).toDate(),
        method: (m['method'] ?? 'cash') as String,
        notes: (m['notes'] ?? '') as String,
        paid: (m['paid'] ?? false) as bool,
        paidAt: (m['paidAt'] as Timestamp?)?.toDate(),
        paidBy: (m['paidBy'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'dueDate': Timestamp.fromDate(dueDate),
        'method': method,
        'notes': notes,
        'paid': paid,
        if (paidAt != null) 'paidAt': Timestamp.fromDate(paidAt!),
        'paidBy': paidBy,
      };
}

// ── UserSubscription ──────────────────────────────────────────────────────────

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
    this.instalmentSchedule = const [],
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
      instalmentSchedule: [],
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
  final List<ScheduledInstalment> instalmentSchedule;

  int get remainingAmount => totalAmount - amountPaid;
  double get paymentPercentage =>
      totalAmount > 0 ? amountPaid / totalAmount : 0;

  /// `'paid'` · `'partial'` · `'unpaid'`
  String get paymentStatus {
    if (totalAmount <= 0 || amountPaid >= totalAmount) return 'paid';
    if (amountPaid > 0) return 'partial';
    return 'unpaid';
  }

  bool get hasPaymentPlan => instalmentSchedule.isNotEmpty;

  int get overdueInstalmentCount =>
      instalmentSchedule.where((i) => i.isOverdue).length;

  factory UserSubscription.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final paymentHistoryData = (data['paymentHistory'] ?? []) as List<dynamic>;
    final paymentHistory = paymentHistoryData
        .map((e) => PaymentRecord.fromMap(e as Map<String, dynamic>))
        .toList();

    final instalmentData =
        (data['instalmentSchedule'] ?? []) as List<dynamic>;
    final instalmentSchedule = instalmentData
        .map((e) =>
            ScheduledInstalment.fromMap(e as Map<String, dynamic>))
        .toList();

    return UserSubscription(
      id: snapshot.id,
      userId: (data['userId'] ?? '') as String,
      planId: (data['planId'] ?? '') as String,
      totalAmount: (data['totalAmount'] as num? ?? 0).toInt(),
      amountPaid: (data['amountPaid'] as num? ?? 0).toInt(),
      currency: (data['currency'] ?? Currency.defaultCode) as String,
      status: (data['status'] ?? 'pending') as String,
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      paymentHistory: paymentHistory,
      gymId: (data['gymId'] ?? '') as String,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      instalmentSchedule: instalmentSchedule,
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
      'instalmentSchedule':
          instalmentSchedule.map((i) => i.toMap()).toList(),
    };
  }
}

// ── PaymentRecord ─────────────────────────────────────────────────────────────

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
