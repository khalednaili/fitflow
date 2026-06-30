import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/currency.dart';

/// A single line-item on an invoice (e.g. one membership plan).
class InvoiceItem {
  const InvoiceItem({
    required this.description,
    required this.amount,
    required this.currency,
    this.taxRate = 0,
  });

  final String description;
  final int amount;
  final String currency;

  /// Tax percentage (0–100). e.g. 20 = 20 % VAT.
  final int taxRate;

  /// Computed tax amount in the same currency unit as [amount].
  int get taxAmount => (amount * taxRate / 100).round();

  factory InvoiceItem.fromMap(Map<String, dynamic> map) => InvoiceItem(
        description: (map['description'] ?? '') as String,
        amount: (map['amount'] ?? 0) as int,
        currency: (map['currency'] ?? Currency.defaultCode) as String,
        taxRate: (map['taxRate'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'description': description,
        'amount': amount,
        'currency': currency,
        'taxRate': taxRate,
      };
}

/// Possible invoice lifecycle statuses.
///
/// draft → unpaid → sent → partial / paid
///                       ↘ overdue
///                  (any) → void
abstract final class InvoiceStatus {
  static const draft = 'draft';
  static const unpaid = 'unpaid';
  static const sent = 'sent';
  static const partial = 'partial';
  static const paid = 'paid';
  static const overdue = 'overdue';
  static const void_ = 'void';

  /// Returns [status] if it is a known value, otherwise [unpaid].
  static String validated(String status) => const {
        draft,
        unpaid,
        sent,
        partial,
        paid,
        overdue,
        void_,
      }.contains(status)
          ? status
          : unpaid;
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
    this.taxAmount = 0,
    this.discountAmount = 0,
    required this.status,
    required this.issuedAt,
    this.dueDate,
    this.notes = '',
    required this.items,
    required this.payments,
    required this.createdAt,
    required this.updatedAt,
    this.isCreditNote = false,
    this.originalInvoiceId,
  });

  final String id;

  /// Human-readable invoice number, e.g. "INV-0001" or "2026-06-0001".
  final String invoiceNumber;
  final String gymId;
  final String userId;
  final String memberName;
  final String memberEmail;
  final String memberPhone;
  final String subscriptionId;
  final String planName;
  final String currency;

  /// Final billed amount (subtotal + tax − discount), in whole currency units.
  final int totalAmount;
  final int amountPaid;

  /// Total tax collected on this invoice.
  final int taxAmount;

  /// Flat discount applied (subtracted from subtotal before tax? or after? — stored explicitly).
  final int discountAmount;

  /// See [InvoiceStatus] constants.
  final String status;
  final DateTime issuedAt;
  final DateTime? dueDate;
  final String notes;
  final List<InvoiceItem> items;
  final List<InvoicePayment> payments;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True when this invoice is a credit note (negative balance document).
  final bool isCreditNote;

  /// For credit notes: the ID of the invoice being credited.
  final String? originalInvoiceId;

  // ── Computed ─────────────────────────────────────────────────────────────

  int get remainingAmount => totalAmount - amountPaid;

  /// Pre-tax, pre-discount sum of line items.
  int get subtotal => items.fold(0, (s, i) => s + i.amount);

  bool get isPaid => status == InvoiceStatus.paid;
  bool get isVoid => status == InvoiceStatus.void_;
  bool get isDraft => status == InvoiceStatus.draft;

  /// True when dueDate has passed and the invoice is not paid/void.
  bool get isOverdue =>
      dueDate != null &&
      dueDate!.isBefore(DateTime.now()) &&
      status != InvoiceStatus.paid &&
      status != InvoiceStatus.void_ &&
      status != InvoiceStatus.draft;

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
      currency: (data['currency'] ?? Currency.defaultCode) as String,
      totalAmount: (data['totalAmount'] ?? 0) as int,
      amountPaid: (data['amountPaid'] ?? 0) as int,
      taxAmount: (data['taxAmount'] ?? 0) as int,
      discountAmount: (data['discountAmount'] ?? 0) as int,
      status: InvoiceStatus.validated((data['status'] ?? '') as String),
      issuedAt: (data['issuedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      notes: (data['notes'] ?? '') as String,
      items: rawItems,
      payments: rawPayments,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt:
          (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isCreditNote: (data['isCreditNote'] ?? false) as bool,
      originalInvoiceId: data['originalInvoiceId'] as String?,
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
        'taxAmount': taxAmount,
        'discountAmount': discountAmount,
        'status': status,
        'issuedAt': Timestamp.fromDate(issuedAt),
        if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate!),
        'notes': notes,
        'items': items.map((i) => i.toMap()).toList(),
        'payments': payments.map((p) => p.toMap()).toList(),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'isCreditNote': isCreditNote,
        if (originalInvoiceId != null) 'originalInvoiceId': originalInvoiceId,
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

