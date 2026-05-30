import 'package:cloud_firestore/cloud_firestore.dart';

class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.name,
    required this.offerType,
    required this.checkinsPerWeek,
    required this.checkinsPerMonth,
    required this.totalCheckins,
    required this.billingCycle,
    required this.durationValue,
    required this.durationUnit,
    required this.price,
    required this.priceMonthly,
    required this.currency,
    required this.description,
    required this.active,
    required this.stripePriceId,
    this.gymId = '',
  });

  final String id;
  final String name;
  final String offerType;
  final int checkinsPerWeek;
  final int checkinsPerMonth;
  final int totalCheckins;
  final String billingCycle;
  final int durationValue;
  final String durationUnit;
  final int price;
  final int priceMonthly;
  final String currency;
  final String description;
  final bool active;
  final String stripePriceId;
  final String gymId;

  String get checkinSummary {
    if (offerType == 'weekly' || offerType == 'weekly_recurring') {
      return '$checkinsPerWeek check-in(s) per week';
    }

    if (offerType == 'monthly_recurring') {
      return '$checkinsPerMonth check-in(s) per month';
    }

    return '$totalCheckins check-in(s) pack';
  }

  String get offerTypeLabel {
    switch (offerType) {
      case 'limited_sessions':
      case 'pack':
        return 'Limite - seances uniques';
      case 'weekly':
      case 'weekly_recurring':
        return 'Recurrence hebdomadaire';
      case 'monthly_recurring':
        return 'Recurrence mensuelle';
      default:
        return offerType;
    }
  }

  String get billingCycleLabel {
    switch (billingCycle) {
      case 'recurrent':
        return 'Recurrent';
      case 'one_time':
        return 'One-time';
      default:
        return billingCycle;
    }
  }

  String get durationLabel {
    if (durationValue <= 0) {
      return 'No duration';
    }

    final unit = switch (durationUnit) {
      'day' => durationValue == 1 ? 'day' : 'days',
      'week' => durationValue == 1 ? 'week' : 'weeks',
      'month' => durationValue == 1 ? 'month' : 'months',
      'year' => durationValue == 1 ? 'year' : 'years',
      _ => durationUnit,
    };

    return '$durationValue $unit';
  }

  factory MembershipPlan.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final rawOfferType = (data['offerType'] ?? 'weekly') as String;
    final resolvedBillingCycle = (data['billingCycle'] as String?) ??
        ((rawOfferType == 'weekly' ||
                rawOfferType == 'weekly_recurring' ||
                rawOfferType == 'monthly_recurring')
            ? 'recurrent'
            : 'one_time');

    return MembershipPlan(
      id: snapshot.id,
      name: (data['name'] ?? '') as String,
      offerType: rawOfferType,
      checkinsPerWeek: (data['checkinsPerWeek'] ?? 0) as int,
      checkinsPerMonth: (data['checkinsPerMonth'] ?? 0) as int,
      totalCheckins: (data['totalCheckins'] ?? 0) as int,
      billingCycle: resolvedBillingCycle,
      durationValue: (data['durationValue'] ?? 1) as int,
      durationUnit: (data['durationUnit'] ?? 'month') as String,
      price: (data['price'] ?? data['priceMonthly'] ?? 0) as int,
      priceMonthly: (data['priceMonthly'] ?? 0) as int,
      currency: (data['currency'] ?? 'USD') as String,
      description: (data['description'] ?? '') as String,
      active: (data['active'] ?? true) as bool,
      stripePriceId: (data['stripePriceId'] ?? '') as String,
      gymId: (data['gymId'] ?? '') as String,
    );
  }
}
