import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../models/membership_plan.dart';
import '../models/user_subscription.dart';

class SubscriptionService {
  SubscriptionService({
    this.gymId = '',
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _firestore;

  Query<Map<String, dynamic>> get _plansQuery {
    // Always fetch all plans so legacy docs without gymId stay visible.
    return _firestore.collection('membership_plans');
  }

  bool _matchesGymId(String scopedGymId) {
    return gymId.isEmpty || scopedGymId.isEmpty || scopedGymId == gymId;
  }

  Query<Map<String, dynamic>> get _subscriptionsQuery {
    Query<Map<String, dynamic>> query = _firestore.collection('subscriptions');
    if (gymId.isNotEmpty) {
      query = query.where('gymId', isEqualTo: gymId);
    }
    return query;
  }

  Query<Map<String, dynamic>> get _userSubscriptionsQuery =>
      _firestore.collection('user_subscriptions');

  Stream<List<MembershipPlan>> streamPlans() {
    return _plansQuery.snapshots().map((query) {
      final plans = query.docs
          .map((doc) => MembershipPlan.fromSnapshot(doc))
          .where((plan) => _matchesGymId(plan.gymId) && plan.active)
          .toList();

      plans.sort((a, b) => a.price.compareTo(b.price));
      return List<MembershipPlan>.unmodifiable(plans);
    });
  }

  Stream<List<MembershipPlan>> streamAllOffers() {
    return _plansQuery.snapshots().map((query) {
      final list = query.docs
          .map((doc) => MembershipPlan.fromSnapshot(doc))
          .where((plan) => _matchesGymId(plan.gymId))
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return List<MembershipPlan>.unmodifiable(list);
    });
  }

  /// One-time fetch of all offers — avoids opening a persistent listener.
  Future<List<MembershipPlan>> fetchAllOffers() async {
    final snap = await _plansQuery.get();
    final list = snap.docs
        .map((doc) => MembershipPlan.fromSnapshot(doc))
        .where((plan) => _matchesGymId(plan.gymId))
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return List<MembershipPlan>.unmodifiable(list);
  }

  Future<void> createCheckinOffer({
    required String name,
    required String description,
    required String offerType,
    required int checkinsPerWeek,
    required int checkinsPerMonth,
    required int totalCheckins,
    required String billingCycle,
    required int durationValue,
    required String durationUnit,
    required int price,
    required String currency,
  }) async {
    await _firestore.collection('membership_plans').add(<String, dynamic>{
      'gymId': gymId,
      'name': name,
      'description': description,
      'offerType': offerType,
      'checkinsPerWeek': checkinsPerWeek,
      'checkinsPerMonth': checkinsPerMonth,
      'totalCheckins': totalCheckins,
      'billingCycle': billingCycle,
      'durationValue': durationValue,
      'durationUnit': durationUnit,
      'price': price,
      // Keep backward compatibility with existing members screen label.
      'priceMonthly': price,
      'currency': currency,
      'active': true,
      'stripePriceId': '',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> setOfferActive({
    required String planId,
    required bool active,
  }) async {
    await _firestore
        .collection('membership_plans')
        .doc(planId)
        .update(<String, dynamic>{
      'active': active,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> updateOffer({
    required String planId,
    required String name,
    required String description,
    required String offerType,
    required int checkinsPerWeek,
    required int checkinsPerMonth,
    required int totalCheckins,
    required String billingCycle,
    required int durationValue,
    required String durationUnit,
    required int price,
    required String currency,
  }) async {
    await _firestore
        .collection('membership_plans')
        .doc(planId)
        .update(<String, dynamic>{
      'name': name,
      'description': description,
      'offerType': offerType,
      'checkinsPerWeek': checkinsPerWeek,
      'checkinsPerMonth': checkinsPerMonth,
      'totalCheckins': totalCheckins,
      'billingCycle': billingCycle,
      'durationValue': durationValue,
      'durationUnit': durationUnit,
      'price': price,
      'priceMonthly': price,
      'currency': currency,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteOffer({required String planId}) async {
    await _firestore.collection('membership_plans').doc(planId).delete();
  }

  Future<void> duplicateOffer({required MembershipPlan source}) async {
    await _firestore.collection('membership_plans').add(<String, dynamic>{
      'gymId': gymId,
      'name': '${source.name} (copy)',
      'description': source.description,
      'offerType': source.offerType,
      'checkinsPerWeek': source.checkinsPerWeek,
      'checkinsPerMonth': source.checkinsPerMonth,
      'totalCheckins': source.totalCheckins,
      'billingCycle': source.billingCycle,
      'durationValue': source.durationValue,
      'durationUnit': source.durationUnit,
      'price': source.price,
      'priceMonthly': source.price,
      'currency': source.currency,
      'active': false,
      'stripePriceId': '',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
  }

  Stream<Map<String, dynamic>?> streamCurrentSubscription(String userId) {
    return _subscriptionsQuery
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: <String>['active', 'trialing', 'past_due'])
        .limit(1)
        .snapshots()
        .map((query) => query.docs.isEmpty ? null : query.docs.first.data());
  }

  Future<String> createStripeCheckoutSession({
    required String userId,
    required String email,
    required String planId,
  }) async {
    throw Exception(
      'Checkout via Cloud Functions is disabled in this project.',
    );
  }

  Future<void> cancelStripeSubscription({required String userId}) async {
    throw Exception(
      'Subscription cancellation via Cloud Functions is disabled in this project.',
    );
  }

  // Payment tracking methods

  Stream<List<UserSubscription>> streamAllUserSubscriptions() {
    return _userSubscriptionsQuery.snapshots().map((query) {
      final list = query.docs
          .map((doc) => UserSubscription.fromSnapshot(doc))
          .where((subscription) => _matchesGymId(subscription.gymId))
          .toList();
      list.sort((a, b) {
        final aUpdated = a.updatedAt ?? a.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bUpdated = b.updatedAt ?? b.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bUpdated.compareTo(aUpdated);
      });
      return List<UserSubscription>.unmodifiable(list);
    });
  }

  Stream<List<UserSubscription>> streamUserSubscriptions(String userId) {
    return streamAllUserSubscriptions().map((subscriptions) {
      final filtered = subscriptions.where((subscription) {
        // Legacy documents may not have userId field but used doc id patterns.
        return subscription.userId == userId ||
            subscription.id == userId ||
            subscription.id.startsWith('${userId}_');
      }).toList(growable: false);

      filtered.sort((a, b) {
        final aUpdated = a.endDate ?? DateTime(2100);
        final bUpdated = b.endDate ?? DateTime(2100);
        return bUpdated.compareTo(aUpdated);
      });

      return filtered;
    });
  }

  /// One-time fetch of subscriptions for a specific user — avoids a persistent listener.
  Future<List<UserSubscription>> fetchUserSubscriptions(String userId) async {
    final snap = await _userSubscriptionsQuery
        .where('userId', isEqualTo: userId)
        .get();
    final list = snap.docs
        .map((doc) => UserSubscription.fromSnapshot(doc))
        .where((s) => _matchesGymId(s.gymId))
        .toList(growable: false);
    list.sort((a, b) {
      final aUpdated = a.endDate ?? DateTime(2100);
      final bUpdated = b.endDate ?? DateTime(2100);
      return bUpdated.compareTo(aUpdated);
    });
    return list;
  }

  Stream<UserSubscription?> streamUserSubscription(String userId) {
    return streamUserSubscriptions(userId).map((subscriptions) {
      if (subscriptions.isEmpty) {
        return null;
      }
      return subscriptions.first;
    });
  }

  Future<void> createUserSubscription({
    required String userId,
    required String planId,
    required int totalAmount,
    required String currency,
    int initialAmountPaid = 0,
    String initialPaymentMethod = 'cash',
    String initialPaymentNotes = '',
    DateTime? initialPaymentDate,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final docId = '${userId}_$planId';
    final now = DateTime.now();
    final safeInitialAmountPaid = initialAmountPaid.clamp(0, totalAmount);
    final paymentHistory = safeInitialAmountPaid > 0
        ? <Map<String, dynamic>>[
            <String, dynamic>{
              'amount': safeInitialAmountPaid,
              'date': Timestamp.fromDate(initialPaymentDate ?? now),
              'method': initialPaymentMethod,
              'notes': initialPaymentNotes,
            },
          ]
        : <Map<String, dynamic>>[];

    await _firestore
        .collection('user_subscriptions')
        .doc(docId)
        .set(<String, dynamic>{
      'gymId': gymId,
      'userId': userId,
      'planId': planId,
      'totalAmount': totalAmount,
      'amountPaid': safeInitialAmountPaid,
      'currency': currency,
      'status': 'active',
      'startDate': Timestamp.fromDate(startDate ?? now),
      'endDate': endDate == null ? null : Timestamp.fromDate(endDate),
      'paymentHistory': paymentHistory,
      'updatedAt': Timestamp.now(),
    });
  }

  /// Atomically creates the subscription document AND updates the member's
  /// user doc in a single [WriteBatch].
  ///
  /// Throws if the member already has an **active** subscription for this plan.
  Future<void> assignOfferAtomic({
    required String userId,
    required String planId,
    required int totalAmount,
    required String currency,
    required DateTime startDate,
    required DateTime endDate,
    int initialAmountPaid = 0,
    String initialPaymentMethod = 'cash',
    String initialPaymentNotes = '',
    DateTime? initialPaymentDate,
  }) async {
    final docId = '${userId}_$planId';
    final now = DateTime.now();

    // ── Duplicate-offer guard ─────────────────────────────────────────────
    final existingSnap = await _firestore
        .collection('user_subscriptions')
        .doc(docId)
        .get();
    if (existingSnap.exists) {
      final existingStatus =
          (existingSnap.data()?['status'] ?? '') as String;
      if (existingStatus == 'active') {
        throw Exception(
            'This member already has an active subscription for this offer.');
      }
    }

    final safeInitialAmountPaid = initialAmountPaid.clamp(0, totalAmount);
    final paymentHistory = safeInitialAmountPaid > 0
        ? <Map<String, dynamic>>[
            <String, dynamic>{
              'amount': safeInitialAmountPaid,
              'date': Timestamp.fromDate(initialPaymentDate ?? now),
              'method': initialPaymentMethod,
              'notes': initialPaymentNotes,
            },
          ]
        : <Map<String, dynamic>>[];

    // ── Atomic batch: subscription doc + user doc ─────────────────────────
    final batch = _firestore.batch();

    batch.set(
      _firestore.collection('user_subscriptions').doc(docId),
      <String, dynamic>{
        'gymId': gymId,
        'userId': userId,
        'planId': planId,
        'totalAmount': totalAmount,
        'amountPaid': safeInitialAmountPaid,
        'currency': currency,
        'status': 'active',
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'paymentHistory': paymentHistory,
        'updatedAt': Timestamp.now(),
      },
    );

    batch.update(
      _firestore.collection('users').doc(userId),
      <String, dynamic>{
        'membershipPlanId': planId,
        'subscriptionStatus': 'active',
        'offerStartAt': Timestamp.fromDate(startDate),
        'offerEndAt': Timestamp.fromDate(endDate),
        'updatedAt': Timestamp.now(),
      },
    );

    await batch.commit();
  }

  Future<void> recordPayment({
    required String subscriptionId,
    required int amount,
    required String method,
    required String notes,
  }) async {
    final subRef = _firestore
        .collection('user_subscriptions')
        .doc(subscriptionId);

    await _firestore.runTransaction((tx) async {
      final subSnapshot = await tx.get(subRef);

      if (!subSnapshot.exists) {
        throw Exception('User subscription not found');
      }

      final data = subSnapshot.data() ?? <String, dynamic>{};
      final currentAmountPaid = (data['amountPaid'] as num? ?? 0).toInt();
      final totalAmount = (data['totalAmount'] as num? ?? 0).toInt();
      final paymentHistoryData =
          (data['paymentHistory'] ?? []) as List<dynamic>;
      final remainingAmount = totalAmount - currentAmountPaid;

      if (amount <= 0) {
        throw Exception('Payment amount must be greater than zero.');
      }
      if (remainingAmount <= 0) {
        throw Exception('This offer is already fully paid.');
      }
      if (amount > remainingAmount) {
        throw Exception('Payment exceeds the remaining amount.');
      }

      final paymentRecord = <String, dynamic>{
        'amount': amount,
        'date': Timestamp.now(),
        'method': method,
        'notes': notes,
      };

      tx.update(subRef, <String, dynamic>{
        'amountPaid': currentAmountPaid + amount,
        'paymentHistory': [...paymentHistoryData, paymentRecord],
        'updatedAt': Timestamp.now(),
      });
    });
  }

  Future<void> updateSubscriptionStatus({
    required String subscriptionId,
    required String status,
  }) async {
    await _firestore
        .collection('user_subscriptions')
        .doc(subscriptionId)
        .update(<String, dynamic>{
      'status': status,
      'updatedAt': Timestamp.now(),
    });
  }

  /// Changes the start date of a subscription.
  Future<void> changeStartDate({
    required String subscriptionId,
    required DateTime newStartDate,
  }) async {
    await _firestore
        .collection('user_subscriptions')
        .doc(subscriptionId)
        .update(<String, dynamic>{
      'startDate': Timestamp.fromDate(newStartDate),
      'updatedAt': Timestamp.now(),
    });
  }

  /// Removes a subscription entirely and resets the member's status to 'none'.
  Future<void> unassignOffer({
    required String subscriptionId,
    required String userId,
  }) async {
    final batch = _firestore.batch();

    batch.delete(
      _firestore.collection('user_subscriptions').doc(subscriptionId),
    );
    batch.update(
      _firestore.collection('users').doc(userId),
      <String, dynamic>{
        'subscriptionStatus': 'none',
        'updatedAt': Timestamp.now(),
      },
    );

    await batch.commit();
  }

  /// Extends (or shortens) the end date of a subscription.
  Future<void> extendOffer({
    required String subscriptionId,
    required DateTime newEndDate,
  }) async {
    await _firestore
        .collection('user_subscriptions')
        .doc(subscriptionId)
        .update(<String, dynamic>{
      'endDate': Timestamp.fromDate(newEndDate),
      'status': 'active',
      'updatedAt': Timestamp.now(),
    });
  }

  Future<MembershipPlan?> getPlanById(String planId) async {
    try {
      final snapshot =
          await _firestore.collection('membership_plans').doc(planId).get();

      if (!snapshot.exists) {
        return null;
      }

      final plan = MembershipPlan.fromSnapshot(snapshot);
      if (!_matchesGymId(plan.gymId)) {
        return null;
      }

      return plan;
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'getPlanById');
      return null;
    }
  }
}
