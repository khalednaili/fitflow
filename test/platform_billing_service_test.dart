import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/gym.dart';
import 'package:fit_flow/services/platform_billing_service.dart';
import 'package:fit_flow/utils/platform_pricing.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PlatformBillingService sut;

  final gym = Gym(
    id: 'gym1',
    name: 'Test Gym',
    adminUid: 'admin1',
    adminEmail: 'admin1@example.com',
    status: 'active',
    createdAt: DateTime(2026, 1, 1),
    createdBy: 'super-admin',
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    sut = PlatformBillingService(firestore: db);
  });

  group('generateInvoiceForGym', () {
    test('bills the base fee for a gym with no usage doc yet', () async {
      final invoice = await sut.generateInvoiceForGym(gym);

      expect(invoice.totalAmount, PlatformPricing.baseFee);
      expect(invoice.gymId, 'gym1');
      expect(invoice.invoiceNumber, 'PLAT-0001');
    });

    test('bills the correct amount for usage already present on the gym',
        () async {
      // Simulate usage recorded before the invoice is generated.
      await db.collection('gymUsage').doc('gym1').set({
        'writes': PlatformPricing.includedOps + 5000,
        'deletes': 0,
      });

      final invoice = await sut.generateInvoiceForGym(gym);

      const overageOps = 5000;
      final expectedOverageCost =
          (overageOps / 1000.0) * PlatformPricing.overageRatePer1000Ops;
      final expectedTotal = PlatformPricing.baseFee + expectedOverageCost;

      expect(invoice.totalAmount, closeTo(expectedTotal, 0.01));
    });

    test(
        'a second invoice only bills operations accrued after the first '
        'invoice (no double-billing of lifetime usage)', () async {
      await db.collection('gymUsage').doc('gym1').set({
        'writes': PlatformPricing.includedOps + 10000,
        'deletes': 0,
      });

      final firstInvoice = await sut.generateInvoiceForGym(gym);
      expect(firstInvoice.totalAmount, greaterThan(PlatformPricing.baseFee),
          reason: 'first invoice should bill the 10k-op overage');

      // Only a small amount of *new* usage accrues after the first invoice —
      // well under the included-ops bundle.
      await db.collection('gymUsage').doc('gym1').update({
        'writes': FieldValue.increment(500),
      });

      final secondInvoice = await sut.generateInvoiceForGym(gym);

      expect(secondInvoice.invoiceNumber, 'PLAT-0002');
      // The second invoice must only reflect the 500 new writes (under the
      // included bundle), not the gym's full lifetime write count — i.e. no
      // double-billing of usage already invoiced.
      expect(secondInvoice.totalAmount, PlatformPricing.baseFee);
    });

    test('increments the platform invoice sequence across gyms', () async {
      final otherGym = Gym(
        id: 'gym2',
        name: 'Other Gym',
        adminUid: 'admin2',
        adminEmail: 'admin2@example.com',
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'super-admin',
      );

      final first = await sut.generateInvoiceForGym(gym);
      final second = await sut.generateInvoiceForGym(otherGym);

      expect(first.invoiceNumber, 'PLAT-0001');
      expect(second.invoiceNumber, 'PLAT-0002');
    });
  });

  group('markInvoicePaid', () {
    test('marks the invoice paid and sets amountPaid to the total', () async {
      final invoice = await sut.generateInvoiceForGym(gym);
      await sut.markInvoicePaid(invoice.id);

      final invoices = await sut.streamInvoicesForGym('gym1').first;
      expect(invoices.single.isPaid, isTrue);
      expect(invoices.single.amountPaid, invoice.totalAmount);
    });
  });
}
