import '../models/gym.dart';
import '../models/gym_usage.dart';

/// A single computed line item for a platform charge (flat fee, or an
/// overage charge above what's included in the base plan).
class ChargeLine {
  const ChargeLine({required this.description, required this.amount});

  final String description;
  final num amount;
}

/// Result of applying [PlatformPricing] to a gym's usage for a billing
/// period: the individual charge lines plus the total.
class PlatformCharge {
  const PlatformCharge({
    required this.lines,
    required this.total,
    required this.currency,
    required this.periodOps,
    required this.overageOps,
    required this.storageBytes,
    required this.overageStorageBytes,
  });

  final List<ChargeLine> lines;
  final num total;
  final String currency;

  final int periodOps;
  final int overageOps;
  final int storageBytes;
  final int overageStorageBytes;
}

/// The platform's own pricing plan: a flat monthly base fee that includes a
/// bundle of Firestore operations and storage, plus metered overage rates
/// beyond that bundle. This is what the super admin charges each gym for
/// running FitFlow — deliberately independent from Firebase's own raw
/// per-operation pricing, since the actual Firebase cost of a gym is
/// typically a few cents to a few dollars/month and isn't, by itself, a
/// viable revenue model.
///
/// All amounts are in [currency] (TND by default, matching [Currency.defaultCode]).
abstract final class PlatformPricing {
  /// Flat amount charged to every active gym per billing period.
  static const num baseFee = 29;

  static const String currency = 'TND';

  /// Firestore writes + deletes included in [baseFee] before overage applies.
  static const int includedOps = 100000;

  /// Combined Firestore + Cloud Storage bytes included in [baseFee].
  static const int includedStorageBytes = 500 * 1024 * 1024; // 500 MB

  /// Charged per 1,000 operations beyond [includedOps].
  static const num overageRatePer1000Ops = 0.5;

  /// Charged per extra GB of storage beyond [includedStorageBytes].
  static const num overageRatePerGb = 2;

  static const int _bytesPerGb = 1024 * 1024 * 1024;

  /// Computes the charge for [usage]'s current billing period (i.e. since
  /// its last invoice — see [GymUsage.opsSinceLastInvoice] — for operations,
  /// and current total for storage, since storage isn't "consumed" the way
  /// operations are).
  static PlatformCharge compute(GymUsage usage) {
    final periodOps = usage.opsSinceLastInvoice.clamp(0, 1 << 62);
    final overageOps = (periodOps - includedOps).clamp(0, 1 << 62);
    final storageBytes = usage.totalStorageBytes;
    final overageStorageBytes =
        (storageBytes - includedStorageBytes).clamp(0, 1 << 62);

    final overageOpsCost =
        (overageOps / 1000.0) * overageRatePer1000Ops;
    final overageStorageCost =
        (overageStorageBytes / _bytesPerGb) * overageRatePerGb;

    final lines = <ChargeLine>[
      const ChargeLine(
        description: 'Monthly platform fee',
        amount: baseFee,
      ),
      if (overageOps > 0)
        ChargeLine(
          description:
              'Extra usage: ${_formatCount(overageOps)} operations '
              'beyond the ${_formatCount(includedOps)} included',
          amount: _round2(overageOpsCost),
        ),
      if (overageStorageBytes > 0)
        ChargeLine(
          description: 'Extra storage: '
              '${(overageStorageBytes / _bytesPerGb).toStringAsFixed(2)} GB '
              'beyond the ${(includedStorageBytes / _bytesPerGb).toStringAsFixed(0)} GB included',
          amount: _round2(overageStorageCost),
        ),
    ];

    final total = lines.fold<num>(0, (sum, l) => sum + l.amount);

    return PlatformCharge(
      lines: lines,
      total: _round2(total),
      currency: currency,
      periodOps: periodOps.toInt(),
      overageOps: overageOps.toInt(),
      storageBytes: storageBytes,
      overageStorageBytes: overageStorageBytes.toInt(),
    );
  }

  static num _round2(num v) => (v * 100).round() / 100;

  static String _formatCount(num n) {
    final s = n.toInt().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// Total estimated platform charge across [gyms] for the current period.
///
/// Suspended gyms are excluded: [compute] always includes the flat
/// [PlatformPricing.baseFee] regardless of usage, so summing over every gym
/// (including suspended ones) would overstate platform revenue with fees for
/// gyms that aren't actively billable.
num computeEstimatedPlatformRevenue(
  List<Gym> gyms,
  Map<String, GymUsage> usageByGym,
) {
  return gyms.where((g) => g.isActive).fold<num>(
        0,
        (total, g) => total +
            PlatformPricing.compute(usageByGym[g.id] ?? GymUsage.empty(g.id))
                .total,
      );
}
