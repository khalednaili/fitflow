import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/gym.dart';
import 'package:fit_flow/models/gym_usage.dart';
import 'package:fit_flow/utils/platform_pricing.dart';

Gym _gym(String id, {String status = 'active'}) => Gym(
      id: id,
      name: 'Gym $id',
      adminUid: 'admin-$id',
      adminEmail: 'admin-$id@example.com',
      status: status,
      createdAt: DateTime(2026, 1, 1),
      createdBy: 'super-admin',
    );

void main() {
  group('PlatformPricing.compute', () {
    test('charges the flat base fee even for a gym with no usage', () {
      final charge = PlatformPricing.compute(GymUsage.empty('gymA'));

      expect(charge.total, PlatformPricing.baseFee);
      expect(charge.lines, hasLength(1));
    });

    test('adds an overage line once included ops are exceeded', () {
      final usage = GymUsage(
        gymId: 'gymA',
        writes: PlatformPricing.includedOps + 2000,
      );

      final charge = PlatformPricing.compute(usage);

      expect(charge.overageOps, 2000);
      expect(charge.total, greaterThan(PlatformPricing.baseFee));
    });
  });

  group('computeEstimatedPlatformRevenue', () {
    test('excludes suspended gyms from the estimated total', () {
      final gyms = [
        _gym('active-gym'),
        _gym('suspended-gym', status: 'suspended'),
      ];

      // Neither gym has a usage doc yet, so both would be billed only the
      // flat base fee if included.
      final total = computeEstimatedPlatformRevenue(gyms, const {});

      expect(total, PlatformPricing.baseFee);
    });

    test('sums usage-based charges across all active gyms', () {
      final gyms = [_gym('gymA'), _gym('gymB')];
      final usageByGym = {
        'gymA': GymUsage(gymId: 'gymA', writes: PlatformPricing.includedOps + 1000),
        'gymB': GymUsage.empty('gymB'),
      };

      final total = computeEstimatedPlatformRevenue(gyms, usageByGym);

      final expected = PlatformPricing.compute(usageByGym['gymA']!).total +
          PlatformPricing.compute(usageByGym['gymB']!).total;
      expect(total, expected);
    });

    test('returns zero when there are no active gyms', () {
      final gyms = [_gym('suspended-only', status: 'suspended')];

      final total = computeEstimatedPlatformRevenue(gyms, const {});

      expect(total, 0);
    });
  });
}
