import 'package:cloud_firestore/cloud_firestore.dart';

/// A single line-item on an invoice (e.g. one membership plan).
class InvoiceItem {
  const InvoiceItem({
    required this.description,
    required this.amount,
    required this.currency,
  });

  final String description;
  final int amount;
  final String currency;

  factory InvoiceItem.fromMap(Map<String, dynamic> map) => InvoiceItem(
        description: (map['description'] ?? '') as String,
        amount: (map['amount'] ?? 0) as int,
        currency: (map['currency'] ?? 'EUR') as String,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'description': description,
        'amount': amount,
        'currency': currency,
      };
}

/// Billing invoice document stored in the `invoices` Firestore collection.
class Invoice {
  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.gymId,
    required this.userId,
    required this.memberName,
    required this.memberEmail,
    this.memberPhone = '',
    required this.subscriptionId,
    required this.planName,
    required this.currency,
    required this.totalAmount,
    required this.amountPaid,
    required this.status,
    required this.issuedAt,
    this.dueDate,
    this.notes = '',
    required this.items,
    required this.payments,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Human-readable invoice number, e.g. "INV-20240529-A3F2".
  final String invoiceNumber;
  final String gymId;
  final String userId;
  final String memberName;
  final String memberEmail;
  final String memberPhone;
  final String subscriptionId;
  final String planName;
  final String currency;
  final int totalAmount;
  final int amountPaid;

  /// 'paid' | 'partial' | 'unpaid'
  final String status;
  final DateTime issuedAt;
  final DateTime? dueDate;
  final String notes;
  final List<InvoiceItem> items;
  final List<InvoicePayment> payments;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get remainingAmount => totalAmount - amountPaid;
  bool get isPaid => status == 'paid';

  factory Invoice.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawItems = (data['items'] as List<dynamic>? ?? [])
        .map((e) => InvoiceItem.fromMap(e as Map<String, dynamic>))
        .toList();
    final rawPayments = (data['payments'] as List<dynamic>? ?? [])
        .map((e) => InvoicePayment.fromMap(e as Map<String, dynamic>))
        .toList();

    return Invoice(
      id: snapshot.id,
      invoiceNumber: (data['invoiceNumber'] ?? '') as String,
      gymId: (data['gymId'] ?? '') as String,
      userId: (data['userId'] ?? '') as String,
      memberName: (data['memberName'] ?? '') as String,
      memberEmail: (data['memberEmail'] ?? '') as String,
      memberPhone: (data['memberPhone'] ?? '') as String,
      subscriptionId: (data['subscriptionId'] ?? '') as String,
      planName: (data['planName'] ?? '') as String,
      currency: (data['currency'] ?? 'EUR') as String,
      totalAmount: (data['totalAmount'] ?? 0) as int,
      amountPaid: (data['amountPaid'] ?? 0) as int,
      status: (data['status'] ?? 'unpaid') as String,
      issuedAt:
          (data['issuedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      notes: (data['notes'] ?? '') as String,
      items: rawItems,
      payments: rawPayments,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt:
          (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'invoiceNumber': invoiceNumber,
        'gymId': gymId,
        'userId': userId,
        'memberName': memberName,
        'memberEmail': memberEmail,
        'memberPhone': memberPhone,
        'subscriptionId': subscriptionId,
        'planName': planName,
        'currency': currency,
        'totalAmount': totalAmount,
        'amountPaid': amountPaid,
        'status': status,
        'issuedAt': Timestamp.fromDate(issuedAt),
        if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate!),
        'notes': notes,
        'items': items.map((i) => i.toMap()).toList(),
        'payments': payments.map((p) => p.toMap()).toList(),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

/// One payment entry within an invoice (mirrors PaymentRecord).
class InvoicePayment {
  const InvoicePayment({
    required this.amount,
    required this.date,
    required this.method,
    this.notes = '',
  });

  final int amount;
  final DateTime date;
  final String method;
  final String notes;

  factory InvoicePayment.fromMap(Map<String, dynamic> map) => InvoicePayment(
        amount: (map['amount'] ?? 0) as int,
        date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        method: (map['method'] ?? 'cash') as String,
        notes: (map['notes'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'amount': amount,
        'date': Timestamp.fromDate(date),
        'method': method,
        'notes': notes,
      };
}

/// Aggregated revenue stats computed from subscription payment history.
class RevenueStats {
  const RevenueStats({
    required this.revenueToday,
    required this.revenueThisMonth,
    required this.revenueLastMonth,
    required this.totalOutstanding,
    required this.newPaymentsThisMonth,
    required this.monthlyTrend,
    required this.revenueByMethod,
    required this.currency,
  });

  final int revenueToday;
  final int revenueThisMonth;
  final int revenueLastMonth;
  final int totalOutstanding;
  final int newPaymentsThisMonth;

  /// Map of "YYYY-MM" → total revenue for that month (last 6 months).
  final Map<String, int> monthlyTrend;

  /// Map of payment method → total amount (e.g. {'cash': 4000, 'card': 2000}).
  final Map<String, int> revenueByMethod;

  final String currency;

  static const empty = RevenueStats(
    revenueToday: 0,
    revenueThisMonth: 0,
    revenueLastMonth: 0,
    totalOutstanding: 0,
    newPaymentsThisMonth: 0,
    monthlyTrend: {},
    revenueByMethod: {},
    currency: '',
  );
}
