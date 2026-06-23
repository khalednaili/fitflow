import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/booking.dart';
import '../models/waitlist_entry.dart';
import 'notification_service.dart';

enum BookingResult { booked, waitlisted }

class BookingService {
  BookingService({this.gymId = '', FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificationService = NotificationService(
          gymId: gymId,
          firestore: firestore,
        );

  final String gymId;
  final FirebaseFirestore _firestore;
  final NotificationService _notificationService;

  Query<Map<String, dynamic>> get _bookingsQuery {
    Query<Map<String, dynamic>> query = _firestore.collection('bookings');
    if (gymId.isNotEmpty) {
      query = query.where('gymId', isEqualTo: gymId);
    }
    return query;
  }

  Query<Map<String, dynamic>> get _waitlistsQuery {
    Query<Map<String, dynamic>> query = _firestore.collection('waitlists');
    if (gymId.isNotEmpty) {
      query = query.where('gymId', isEqualTo: gymId);
    }
    return query;
  }

  Query<Map<String, dynamic>> get _attendanceQuery {
    Query<Map<String, dynamic>> query = _firestore.collection('attendance');
    if (gymId.isNotEmpty) {
      query = query.where('gymId', isEqualTo: gymId);
    }
    return query;
  }

  Query<Map<String, dynamic>> get _lateCancellationsQuery {
    Query<Map<String, dynamic>> query =
        _firestore.collection('late_cancellations');
    if (gymId.isNotEmpty) {
      query = query.where('gymId', isEqualTo: gymId);
    }
    return query;
  }

  Stream<List<Booking>> streamBookingsForUser(String userId) {
    return _bookingsQuery.where('userId', isEqualTo: userId).snapshots().map(
      (query) {
        final list =
            query.docs.map((doc) => Booking.fromSnapshot(doc)).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      },
    );
  }

  Stream<List<Booking>> streamBookingsForClass(String classId) {
    return _bookingsQuery
        .where('classId', isEqualTo: classId)
        .snapshots()
        .map((query) {
      final bookings = query.docs
          .map((doc) => Booking.fromSnapshot(doc))
          .toList(growable: false);
      bookings.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return bookings;
    });
  }

  Stream<Set<String>> streamBookedClassIds(String userId) {
    return streamBookingsForUser(userId).map(
      (bookings) => bookings.map((booking) => booking.classId).toSet(),
    );
  }

  Stream<Set<String>> streamWaitlistedClassIds(String userId) {
    return _waitlistsQuery.where('userId', isEqualTo: userId).snapshots().map(
          (query) => query.docs
              .map((doc) => (doc.data()['classId'] ?? '') as String)
              .where((classId) => classId.isNotEmpty)
              .toSet(),
        );
  }

  Stream<Set<String>> streamCheckedInUserIds(String classId) {
    return _attendanceQuery
        .where('classId', isEqualTo: classId)
        .snapshots()
        .map(
          (query) => query.docs
              .map((doc) => (doc.data()['userId'] ?? '') as String)
              .where((userId) => userId.isNotEmpty)
              .toSet(),
        );
  }

  // ── Booking rules ──────────────────────────────────────────────────────────

  /// Returns the maximum number of class bookings a member may have per day.
  /// 0 means unlimited.
  Future<int> getMaxBookingsPerDay() async {
    final rules = await _getBookingRules();
    return (rules['maxBookingsPerDay'] ?? 0) as int;
  }

  Future<void> setMaxBookingsPerDay(int max) async {
    await _firestore.collection('settings').doc('bookingRules').set(
      <String, dynamic>{
        'maxBookingsPerDay': max,
        'gymId': gymId,
      },
      SetOptions(merge: true),
    );
  }

  /// Returns the late-cancellation penalty threshold in minutes.
  /// 0 means the rule is disabled.
  /// If a member cancels within this many minutes before the class starts,
  /// the cancellation is counted as a used session.
  Future<int> getLateCancellationMinutes() async {
    final rules = await _getBookingRules();
    return (rules['lateCancellationMinutes'] ?? 0) as int;
  }

  Future<void> setLateCancellationMinutes(int minutes) async {
    await _firestore.collection('settings').doc('bookingRules').set(
      <String, dynamic>{
        'lateCancellationMinutes': minutes,
        'gymId': gymId,
      },
      SetOptions(merge: true),
    );
  }

  /// Returns the minimum advance booking time in minutes.
  /// 0 means the rule is disabled (members can book any time).
  /// If set to e.g. 60, members cannot book a class that starts in less than
  /// 60 minutes from now.
  Future<int> getMinAdvanceBookingMinutes() async {
    final rules = await _getBookingRules();
    return (rules['minAdvanceBookingMinutes'] ?? 0) as int;
  }

  Future<void> setMinAdvanceBookingMinutes(int minutes) async {
    await _firestore.collection('settings').doc('bookingRules').set(
      <String, dynamic>{
        'minAdvanceBookingMinutes': minutes,
        'gymId': gymId,
      },
      SetOptions(merge: true),
    );
  }

  /// When true, a member cannot book a class whose time slot overlaps with
  /// an existing booking. Defaults to false (overlap allowed).
  Future<bool> getPreventOverlappingBookings() async {
    final rules = await _getBookingRules();
    return (rules['preventOverlappingBookings'] ?? false) as bool;
  }

  Future<void> setPreventOverlappingBookings(bool value) async {
    await _firestore.collection('settings').doc('bookingRules').set(
      <String, dynamic>{
        'preventOverlappingBookings': value,
        'gymId': gymId,
      },
      SetOptions(merge: true),
    );
    _rulesCache = null; // invalidate cache
  }

  /// When true, a member cannot book more than one class of the same type
  /// (classTypeId) on the same calendar day. Defaults to false.
  Future<bool> getPreventSameClassTypePerDay() async {
    final rules = await _getBookingRules();
    return (rules['preventSameClassTypePerDay'] ?? false) as bool;
  }

  Future<void> setPreventSameClassTypePerDay(bool value) async {
    await _firestore.collection('settings').doc('bookingRules').set(
      <String, dynamic>{
        'preventSameClassTypePerDay': value,
        'gymId': gymId,
      },
      SetOptions(merge: true),
    );
    _rulesCache = null;
  }

  Future<bool> getHideClassesWithoutSubscription() async {
    final rules = await _getBookingRules();
    return (rules['hideClassesWithoutSubscription'] ?? false) as bool;
  }

  Future<void> setHideClassesWithoutSubscription(bool value) async {
    await _firestore.collection('settings').doc('bookingRules').set(
      <String, dynamic>{
        'hideClassesWithoutSubscription': value,
        'gymId': gymId,
      },
      SetOptions(merge: true),
    );
    _rulesCache = null;
  }

  /// Stream all late-cancellation penalty records for a user.
  Stream<List<Map<String, dynamic>>> streamLateCancellationsForUser(
      String userId) {
    return _lateCancellationsQuery
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
          .toList();
      list.sort((a, b) {
        final aTs =
            (a['cancelledAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bTs =
            (b['cancelledAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return bTs.compareTo(aTs);
      });
      return list;
    });
  }

  // ── Booking rules cache (5-min TTL) ───────────────────────────────────────
  Map<String, dynamic>? _rulesCache;
  DateTime? _rulesCachedAt;

  // ── Membership plan cache (10-min TTL) ────────────────────────────────────
  final Map<String, Map<String, dynamic>> _planCache = {};
  final Map<String, DateTime> _planCachedAt = {};

  Future<Map<String, dynamic>?> _getPlan(String planId) async {
    final now = DateTime.now();
    final cached = _planCachedAt[planId];
    if (cached != null &&
        now.difference(cached).inMinutes < 10 &&
        _planCache.containsKey(planId)) {
      return _planCache[planId];
    }
    final doc =
        await _firestore.collection('membership_plans').doc(planId).get();
    if (!doc.exists) return null;
    _planCache[planId] = doc.data()!;
    _planCachedAt[planId] = now;
    return _planCache[planId];
  }

  Future<Map<String, dynamic>> _getBookingRules() async {
    final now = DateTime.now();
    if (_rulesCache != null &&
        _rulesCachedAt != null &&
        now.difference(_rulesCachedAt!).inMinutes < 5) {
      return _rulesCache!;
    }
    final doc =
        await _firestore.collection('settings').doc('bookingRules').get();
    _rulesCache = doc.data() ?? {};
    _rulesCachedAt = now;
    return _rulesCache!;
  }

  // ── Book a class ───────────────────────────────────────────────────────────

  Future<BookingResult> bookClass({
    required String userId,
    required String classId,
    bool isDropIn = false,
    String dropInPaymentStatus = 'pending',
    bool bypassDailyLimit = false,
  }) async {
    final classRef = _firestore.collection('classes').doc(classId);
    final userRef = _firestore.collection('users').doc(userId);

    // ── Phase 1: parallel fetch everything needed for validation ────────────
    // Subscriptions and waitlist are queried directly (bypassing gymId prefix)
    // to avoid missing composite-index errors; the (userId,classId) and
    // single-field userId auto-indexes cover these targeted lookups.
    final results = await Future.wait([
      classRef.get(), // [0] class
      userRef.get(), // [1] user
      _firestore // [2] user subscriptions – bypass gymId filter
          .collection('user_subscriptions')
          .where('userId', isEqualTo: userId)
          .limit(50)
          .get(),
      _bookingsQuery // [3] all user bookings (duplicate + limit check)
          .where('userId', isEqualTo: userId)
          .get(),
      _firestore // [4] waitlist check – bypass gymId, uses (userId,classId) index
          .collection('waitlists')
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: classId)
          .limit(1)
          .get(),
      _getBookingRules(), // [5] config (cached)
    ]);

    final classSnapshot = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final userSnapshot = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    final userSubscriptionsQuery =
        results[2] as QuerySnapshot<Map<String, dynamic>>;
    final allBookingsSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final existingWaitlistQuery =
        results[4] as QuerySnapshot<Map<String, dynamic>>;
    final rules = results[5] as Map<String, dynamic>;

    if (!classSnapshot.exists) {
      throw Exception('This class does not exist anymore.');
    }

    final classData = classSnapshot.data()!;
    final userData = userSnapshot.data() ?? <String, dynamic>{};
    final rawDisplayName = (userData['displayName'] ?? '') as String;
    final rawEmail = (userData['email'] ?? '') as String;
    final memberName = rawDisplayName.trim().isNotEmpty
        ? rawDisplayName.trim()
        : rawEmail.trim();
    final requiredOfferPlanIds =
        ((classData['requiredOfferPlanIds'] as List<dynamic>? ?? <dynamic>[])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false));
    final legacyRequiredOfferPlanId =
        (classData['requiredOfferPlanId'] ?? '') as String;
    final effectiveRequiredOfferPlanIds = requiredOfferPlanIds.isNotEmpty
        ? requiredOfferPlanIds
        : (legacyRequiredOfferPlanId.trim().isEmpty
            ? const <String>[]
            : <String>[legacyRequiredOfferPlanId.trim()]);
    final classStartTime =
        (classData['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
    final classEndTime =
        (classData['endTime'] as Timestamp?)?.toDate() ??
            classStartTime.add(const Duration(hours: 1));
    final classTypeId = (classData['classTypeId'] ?? '') as String;

    bool hasAnyValidAssignedOffer = false;
    for (final doc in userSubscriptionsQuery.docs) {
      final data = doc.data();
      final status = (data['status'] ?? 'pending') as String;
      if (status == 'cancelled' || status == 'paused') {
        continue;
      }

      final offerStart = (data['startDate'] as Timestamp?)?.toDate();
      final offerEnd = (data['endDate'] as Timestamp?)?.toDate();
      final withinStart =
          offerStart == null || !classStartTime.isBefore(offerStart);
      final withinEnd = offerEnd == null || !classStartTime.isAfter(offerEnd);

      if (withinStart && withinEnd) {
        hasAnyValidAssignedOffer = true;
        break;
      }
    }

    if (!isDropIn && !hasAnyValidAssignedOffer) {
      // Fallback to legacy single-offer fields for backward compatibility.
      final legacyMemberPlanId = (userData['membershipPlanId'] ?? '') as String;
      final legacyStatus = (userData['subscriptionStatus'] ?? 'none') as String;
      final legacyOfferStart =
          (userData['offerStartAt'] as Timestamp?)?.toDate();
      final legacyOfferEnd = (userData['offerEndAt'] as Timestamp?)?.toDate();

      final hasLegacyPlan = legacyMemberPlanId.isNotEmpty;
      final hasLegacyDates = legacyOfferStart != null && legacyOfferEnd != null;
      final legacyIsActive =
          legacyStatus == 'active' || legacyStatus == 'pending';
      final legacyWithinStart = legacyOfferStart == null ||
          !classStartTime.isBefore(legacyOfferStart);
      final legacyWithinEnd =
          legacyOfferEnd == null || !classStartTime.isAfter(legacyOfferEnd);

      if (!(hasLegacyPlan &&
          hasLegacyDates &&
          legacyIsActive &&
          legacyWithinStart &&
          legacyWithinEnd)) {
        throw Exception('You need an active assigned offer to book classes.');
      }
    }

    if (!isDropIn && effectiveRequiredOfferPlanIds.isNotEmpty) {
      var hasValidAssignedOffer = false;
      for (final doc in userSubscriptionsQuery.docs) {
        final data = doc.data();
        final status = (data['status'] ?? 'pending') as String;
        final planId = (data['planId'] ?? '') as String;
        if (status == 'cancelled' || status == 'paused') {
          continue;
        }
        if (!effectiveRequiredOfferPlanIds.contains(planId)) {
          continue;
        }

        final offerStart = (data['startDate'] as Timestamp?)?.toDate();
        final offerEnd = (data['endDate'] as Timestamp?)?.toDate();

        final withinStart =
            offerStart == null || !classStartTime.isBefore(offerStart);
        final withinEnd = offerEnd == null || !classStartTime.isAfter(offerEnd);

        if (withinStart && withinEnd) {
          hasValidAssignedOffer = true;
          break;
        }
      }

      if (!hasValidAssignedOffer) {
        // Fallback to legacy single-offer fields for backward compatibility.
        final memberPlanId = (userData['membershipPlanId'] ?? '') as String;
        final legacyStatus =
            (userData['subscriptionStatus'] ?? 'none') as String;

        if (!effectiveRequiredOfferPlanIds.contains(memberPlanId)) {
          throw Exception('This class requires one of specific offers.');
        }

        final offerStart = (userData['offerStartAt'] as Timestamp?)?.toDate();
        final offerEnd = (userData['offerEndAt'] as Timestamp?)?.toDate();
        final hasLegacyDates = offerStart != null && offerEnd != null;
        final legacyIsActive =
            legacyStatus == 'active' || legacyStatus == 'pending';

        if (!hasLegacyDates ||
            !legacyIsActive ||
            classStartTime.isBefore(offerStart) ||
            classStartTime.isAfter(offerEnd)) {
          throw Exception(
              'Your assigned offer is not valid for this class date.');
        }
      }
    }

    // ── Duplicate booking check ───────────────────────────────────────────────
    final alreadyBooked = allBookingsSnap.docs
        .any((doc) => (doc.data()['classId'] ?? '') == classId);
    if (alreadyBooked) {
      throw Exception('You already booked this class.');
    }

    // ── Overlapping time-slot check ───────────────────────────────────────────
    if (!isDropIn &&
        (rules['preventOverlappingBookings'] ?? false) as bool) {
      for (final doc in allBookingsSnap.docs) {
        final data = doc.data();
        final existingStart =
            (data['classStartTime'] as Timestamp?)?.toDate();
        final existingEnd = (data['classEndTime'] as Timestamp?)?.toDate();
        // Skip legacy bookings that don't carry time-slot data.
        if (existingStart == null || existingEnd == null) continue;
        // Two intervals overlap when: newStart < existingEnd && existingStart < newEnd
        if (classStartTime.isBefore(existingEnd) &&
            existingStart.isBefore(classEndTime)) {
          throw Exception(
              'You already have a class booked during this time slot.');
        }
      }
    }

    // ── Same class-type per day check ─────────────────────────────────────────
    if (!isDropIn &&
        classTypeId.isNotEmpty &&
        (rules['preventSameClassTypePerDay'] ?? false) as bool) {
      final classDay = DateTime(
          classStartTime.year, classStartTime.month, classStartTime.day);
      final classDayEnd = classDay.add(const Duration(days: 1));
      for (final doc in allBookingsSnap.docs) {
        final data = doc.data();
        final existingTypeId = (data['classTypeId'] ?? '') as String;
        if (existingTypeId.isEmpty || existingTypeId != classTypeId) continue;
        final bd = (data['bookingDate'] as Timestamp?)?.toDate();
        if (bd == null) continue;
        if (!bd.isBefore(classDay) && bd.isBefore(classDayEnd)) {
          throw Exception(
              'You already have a class of this type booked for today.');
        }
      }
    }

    // ── Minimum advance booking time check (uses cached rules) ────────────
    if (!bypassDailyLimit) {
      final minAdvance = (rules['minAdvanceBookingMinutes'] ?? 0) as int;
      final minutesUntilClass =
          classStartTime.difference(DateTime.now()).inMinutes;

      if (minutesUntilClass < 0) {
        throw Exception('This class has already started.');
      }

      if (minAdvance > 0 && minutesUntilClass > minAdvance) {
        final hours = minAdvance ~/ 60;
        final mins = minAdvance % 60;
        final label = hours >= 24
            ? '${minAdvance ~/ 1440} day(s)'
            : hours > 0
                ? '${hours}h${mins > 0 ? ' ${mins}min' : ''}'
                : '$mins min';
        throw Exception(
            'Booking opens $label before the class. Please check back closer to the start time.');
      }
    }

    // ── Daily booking limit check (uses pre-fetched allBookingsSnap) ────────
    if (!bypassDailyLimit) {
      final maxPerDay = (rules['maxBookingsPerDay'] ?? 0) as int;
      if (maxPerDay > 0) {
        final dayStart = DateTime(
            classStartTime.year, classStartTime.month, classStartTime.day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        final dayBookings = allBookingsSnap.docs.where((doc) {
          final bd = doc.data()['bookingDate'];
          if (bd is! Timestamp) return false;
          final dt = bd.toDate();
          return !dt.isBefore(dayStart) && dt.isBefore(dayEnd);
        });
        if (dayBookings.length >= maxPerDay) {
          throw Exception('Daily booking limit reached ($maxPerDay per day). '
              'Please cancel another booking first.');
        }
      }
    }

    // ── Resolve which subscription best matches this class ────────────────────
    // When the class has requiredOfferPlanIds, prefer the subscription whose
    // planId is in that set so that per-offer limits are checked against the
    // correct offer. Fall back to the first date-valid subscription for classes
    // with no offer restriction (any offer can join).
    Map<String, dynamic>? matchedSub;
    {
      Map<String, dynamic>? fallbackSub;
      for (final doc in userSubscriptionsQuery.docs) {
        final data = doc.data();
        final subStatus = (data['status'] ?? 'pending') as String;
        if (subStatus == 'cancelled' || subStatus == 'paused') continue;
        final offerStart = (data['startDate'] as Timestamp?)?.toDate();
        final offerEnd = (data['endDate'] as Timestamp?)?.toDate();
        final withinStart =
            offerStart == null || !classStartTime.isBefore(offerStart);
        final withinEnd = offerEnd == null || !classStartTime.isAfter(offerEnd);
        if (withinStart && withinEnd) {
          final subPlanId = (data['planId'] ?? '') as String;
          if (effectiveRequiredOfferPlanIds.isNotEmpty &&
              effectiveRequiredOfferPlanIds.contains(subPlanId)) {
            matchedSub = data;
            break; // exact match for this class's required offer
          }
          fallbackSub ??= data;
        }
      }
      matchedSub ??= fallbackSub;
    }
    // usedPlanId is stored on the booking so per-plan counters stay isolated.
    final usedPlanId = (matchedSub?['planId'] as String?) ?? '';

    // ── Per-offer session limit check ───────────────────────────────────────
    if (!isDropIn && matchedSub != null) {
      final planId = (matchedSub['planId'] ?? '') as String;
      final subStart = (matchedSub['startDate'] as Timestamp?)?.toDate();
      final subEnd = (matchedSub['endDate'] as Timestamp?)?.toDate();

      if (planId.isNotEmpty) {
        final p = await _getPlan(planId);

        if (p != null) {
          final offerType = (p['offerType'] ?? 'weekly') as String;
          final checkinsPerWeek = (p['checkinsPerWeek'] ?? 0) as int;
          final checkinsPerMonth = (p['checkinsPerMonth'] ?? 0) as int;
          final totalCheckins = (p['totalCheckins'] ?? 0) as int;

          // Use the already-fetched allBookingsSnap — no extra query needed.
          // Only count bookings that consumed this same plan so that a member
          // holding multiple simultaneous offers doesn't have their limits
          // counted across unrelated classes (e.g. "skills" bookings must not
          // eat into "punic" weekly slots). Legacy bookings without usedPlanId
          // are counted conservatively so old data can't be used to bypass limits.
          bool sameOffer(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
            final docPlanId = (doc.data()['usedPlanId'] as String?) ?? '';
            return docPlanId.isEmpty || docPlanId == planId;
          }

          if ((offerType == 'weekly' || offerType == 'weekly_recurring') &&
              checkinsPerWeek > 0) {
            // Monday of the week containing classStartTime
            final daysFromMon = classStartTime.weekday - 1;
            final weekStart = DateTime(
              classStartTime.year,
              classStartTime.month,
              classStartTime.day,
            ).subtract(Duration(days: daysFromMon));
            final weekEnd = weekStart.add(const Duration(days: 7));

            final weekCount = allBookingsSnap.docs.where((doc) {
              final bd = doc.data()['bookingDate'];
              if (bd is! Timestamp) return false;
              final dt = bd.toDate();
              if (!sameOffer(doc)) return false;
              return !dt.isBefore(weekStart) && dt.isBefore(weekEnd);
            }).length;

            if (weekCount >= checkinsPerWeek) {
              throw Exception(
                'Weekly limit reached. Your offer allows $checkinsPerWeek '
                'class${checkinsPerWeek == 1 ? '' : 'es'} per week and you '
                'have already booked $weekCount this week.',
              );
            }
          } else if (offerType == 'monthly_recurring' && checkinsPerMonth > 0) {
            final monthStart =
                DateTime(classStartTime.year, classStartTime.month, 1);
            final monthEnd =
                DateTime(classStartTime.year, classStartTime.month + 1, 1);

            final monthCount = allBookingsSnap.docs.where((doc) {
              final bd = doc.data()['bookingDate'];
              if (bd is! Timestamp) return false;
              final dt = bd.toDate();
              if (!sameOffer(doc)) return false;
              return !dt.isBefore(monthStart) && dt.isBefore(monthEnd);
            }).length;

            if (monthCount >= checkinsPerMonth) {
              throw Exception(
                'Monthly limit reached. Your offer allows $checkinsPerMonth '
                'class${checkinsPerMonth == 1 ? '' : 'es'} per month and you '
                'have already booked $monthCount this month.',
              );
            }
          } else if ((offerType == 'limited_sessions' || offerType == 'pack') &&
              totalCheckins > 0) {
            final periodStart = subStart ?? DateTime(2000);
            final periodEnd = subEnd ?? DateTime(2100);

            final usedCount = allBookingsSnap.docs.where((doc) {
              final bd = doc.data()['bookingDate'];
              if (bd is! Timestamp) return false;
              final dt = bd.toDate();
              if (!sameOffer(doc)) return false;
              return !dt.isBefore(periodStart) && !dt.isAfter(periodEnd);
            }).length;

            if (usedCount >= totalCheckins) {
              throw Exception(
                'Session pack exhausted. Your offer includes $totalCheckins '
                'session${totalCheckins == 1 ? '' : 's'} and all have been used.',
              );
            }
          }
        }
      }
    }

    if (existingWaitlistQuery.docs.isNotEmpty) {
      throw Exception('You are already on the waitlist for this class.');
    }

    final capacity = (classData['capacity'] ?? 0) as int;
    final bookedCount = (classData['bookedCount'] ?? 0) as int;

    if (bookedCount < capacity) {
      final bookingRef = _firestore.collection('bookings').doc();
      await _firestore.runTransaction((transaction) async {
        final latestClassSnapshot = await transaction.get(classRef);
        final latestClassData =
            latestClassSnapshot.data() ?? <String, dynamic>{};
        final latestBooked = (latestClassData['bookedCount'] ?? 0) as int;
        final latestCapacity = (latestClassData['capacity'] ?? 0) as int;

        if (latestBooked >= latestCapacity) {
          throw Exception('This class just became full. Please retry.');
        }

        transaction.update(classRef, <String, dynamic>{
          'bookedCount': latestBooked + 1,
          'updatedAt': Timestamp.now(),
        });

        transaction.set(bookingRef, <String, dynamic>{
          'userId': userId,
          'classId': classId,
          'gymId': gymId,
          'createdAt': Timestamp.now(),
          'bookingDate': Timestamp.fromDate(DateTime(
              classStartTime.year, classStartTime.month, classStartTime.day)),
          'memberName': memberName,
          'isDropIn': isDropIn,
          'dropInPaymentStatus': dropInPaymentStatus,
          'usedPlanId': usedPlanId,
          'classStartTime': Timestamp.fromDate(classStartTime),
          'classEndTime': Timestamp.fromDate(classEndTime),
          'classTypeId': classTypeId,
        });
      });
      return BookingResult.booked;
    }

    await _firestore.runTransaction((transaction) async {
      final waitlistRef = _firestore.collection('waitlists').doc();
      final latestClassSnapshot = await transaction.get(classRef);
      final latestClassData = latestClassSnapshot.data() ?? <String, dynamic>{};
      final currentWaitlistCount =
          (latestClassData['waitlistCount'] ?? 0) as int;

      transaction.set(waitlistRef, <String, dynamic>{
        'userId': userId,
        'classId': classId,
        'gymId': gymId,
        'createdAt': Timestamp.now(),
        'memberName': memberName,
      });

      transaction.update(classRef, <String, dynamic>{
        'waitlistCount': currentWaitlistCount + 1,
        'updatedAt': Timestamp.now(),
      });
    });

    return BookingResult.waitlisted;
  }

  Future<void> cancelBooking({
    required String userId,
    required String classId,
  }) async {
    final classRef = _firestore.collection('classes').doc(classId);

    // Temp holders — filled inside transaction, used after for notification
    String? promotedUserId;
    String? promotedClassTitle;
    String? promotedClassId;

    // --- All non-transactional reads BEFORE the transaction ---

    // Look up the booking using userId + classId only — avoids needing a
    // (gymId, userId, classId) composite index and keeps the query lean.
    final bookingQuery = await _firestore
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    if (bookingQuery.docs.isEmpty) {
      throw Exception('No active booking found for this class.');
    }
    final bookingDocRef = bookingQuery.docs.first.reference;

    // Read class data for start time + title (needed for late-cancel check)
    final classSnapshot = await classRef.get();
    if (!classSnapshot.exists) throw Exception('Class not found.');
    final classData = classSnapshot.data()!;
    final classStartTime =
        (classData['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
    final classTitle = (classData['title'] ?? '') as String;

    // Read late-cancellation setting
    final lateCancelMinutes = await getLateCancellationMinutes();

    // Fetch waitlist without orderBy to avoid composite-index requirement;
    // sort client-side by createdAt to pick the earliest entry.
    final waitlistQuery =
        await _waitlistsQuery.where('classId', isEqualTo: classId).get();

    DocumentSnapshot? firstWaitlistDoc;
    if (waitlistQuery.docs.isNotEmpty) {
      final sorted = waitlistQuery.docs.toList()
        ..sort((a, b) {
          final aTs =
              (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                  0;
          final bTs =
              (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                  0;
          return aTs.compareTo(bTs);
        });
      firstWaitlistDoc = sorted.first;
    }

    // --- Transaction uses only transaction.get() for reads ---
    await _firestore.runTransaction((transaction) async {
      final latestClassSnap = await transaction.get(classRef);
      if (!latestClassSnap.exists) {
        throw Exception('Class not found.');
      }

      final latestClassData = latestClassSnap.data() ?? <String, dynamic>{};
      final bookedCount = (latestClassData['bookedCount'] ?? 0) as int;
      final nextBookedCount = bookedCount > 0 ? bookedCount - 1 : 0;

      transaction.delete(bookingDocRef);

      if (firstWaitlistDoc != null) {
        final data = firstWaitlistDoc.data() as Map<String, dynamic>? ?? {};
        final waitlistUserId = (data['userId'] ?? '') as String;
        final waitlistMemberName = (data['memberName'] ?? '') as String;

        if (waitlistUserId.isNotEmpty) {
          final promotedBookingRef = _firestore.collection('bookings').doc();
          transaction.set(promotedBookingRef, <String, dynamic>{
            'userId': waitlistUserId,
            'classId': classId,
            'gymId': gymId,
            'createdAt': Timestamp.now(),
            'memberName': waitlistMemberName,
          });
          transaction.delete(firstWaitlistDoc.reference);

          final waitlistCount = (latestClassData['waitlistCount'] ?? 0) as int;
          transaction.update(classRef, <String, dynamic>{
            'bookedCount': nextBookedCount + 1,
            'waitlistCount': waitlistCount > 0 ? waitlistCount - 1 : 0,
            'updatedAt': Timestamp.now(),
          });
          // Store promoted userId/classTitle for notification after transaction
          promotedUserId = waitlistUserId;
          promotedClassTitle =
              (latestClassData['title'] ?? 'the class') as String;
          promotedClassId = classId;
          return;
        }
      }

      transaction.update(classRef, <String, dynamic>{
        'bookedCount': nextBookedCount,
        'updatedAt': Timestamp.now(),
      });
    });

    // ── Late-cancellation penalty ───────────────────────────────────────────
    // Record a penalty if the rule is enabled and the cancellation happens
    // within `lateCancelMinutes` minutes of the class start time.
    if (lateCancelMinutes > 0) {
      final now = DateTime.now();
      final minutesUntilClass = classStartTime.difference(now).inMinutes;
      if (minutesUntilClass >= 0 && minutesUntilClass < lateCancelMinutes) {
        // Resolve member name for the record
        final userSnap = await _firestore.collection('users').doc(userId).get();
        final userData = userSnap.data() ?? <String, dynamic>{};
        final memberName =
            ((userData['displayName'] ?? '') as String).trim().isNotEmpty
                ? (userData['displayName'] as String).trim()
                : (userData['email'] ?? '') as String;

        await _firestore.collection('late_cancellations').add(<String, dynamic>{
          'userId': userId,
          'classId': classId,
          'gymId': gymId,
          'classTitle': classTitle,
          'classStartTime': Timestamp.fromDate(classStartTime),
          'cancelledAt': Timestamp.now(),
          'minutesBeforeClass': minutesUntilClass,
          'memberName': memberName,
        });
      }
    }

    // Send in-app notification to the promoted member (outside transaction)
    if (promotedUserId != null &&
        promotedClassTitle != null &&
        promotedClassId != null) {
      await _notificationService.create(
        userId: promotedUserId!,
        title: "You're in! 🎉",
        body:
            'A spot opened up in "$promotedClassTitle". You have been moved from the waitlist to the class.',
        type: NotificationType.waitlistPromoted,
        classId: promotedClassId,
      );
    }
  }

  Future<void> leaveWaitlist({
    required String userId,
    required String classId,
  }) async {
    // Bypass gymId to use the existing (userId,classId) composite index.
    final waitlistQuery = await _firestore
        .collection('waitlists')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    if (waitlistQuery.docs.isEmpty) {
      return;
    }

    final waitlistDocRef = waitlistQuery.docs.first.reference;
    final classRef = _firestore.collection('classes').doc(classId);

    await _firestore.runTransaction((transaction) async {
      final classSnapshot = await transaction.get(classRef);
      if (!classSnapshot.exists) {
        transaction.delete(waitlistDocRef);
        return;
      }

      final classData = classSnapshot.data() ?? <String, dynamic>{};
      final waitlistCount = (classData['waitlistCount'] ?? 0) as int;

      transaction.delete(waitlistDocRef);
      transaction.update(classRef, <String, dynamic>{
        'waitlistCount': waitlistCount > 0 ? waitlistCount - 1 : 0,
        'updatedAt': Timestamp.now(),
      });
    });
  }

  Future<void> checkInMember({
    required String classId,
    required String userId,
    required String checkedInBy,
  }) async {
    final now = Timestamp.now();

    // 1. Record attendance (idempotent)
    final existing = await _firestore
        .collection('attendance')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    if (existing.docs.isEmpty) {
      await _firestore.collection('attendance').add(<String, dynamic>{
        'classId': classId,
        'userId': userId,
        'gymId': gymId,
        'checkedInBy': checkedInBy,
        'checkedInAt': now,
      });
    }

    // 2. Update the booking document's checkedIn flag
    final bookingSnap = await _firestore
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    for (final doc in bookingSnap.docs) {
      await doc.reference.update(<String, dynamic>{
        'checkedIn': true,
        'checkedInAt': now,
      });
    }
  }

  Future<void> undoCheckIn({
    required String classId,
    required String userId,
  }) async {
    // 1. Remove attendance record
    final existing = await _firestore
        .collection('attendance')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    for (final doc in existing.docs) {
      await doc.reference.delete();
    }

    // 2. Reset the booking document's checkedIn flag
    final bookingSnap = await _firestore
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    for (final doc in bookingSnap.docs) {
      await doc.reference.update(<String, dynamic>{
        'checkedIn': false,
        'checkedInAt': FieldValue.delete(),
      });
    }
  }

  /// Marks every non-checked-in member booking for [classId] as checked in.
  ///
  /// Only processes real members (non-guest, non-empty userId). Skips bookings
  /// that are already checked in. Uses a single [WriteBatch] for atomicity and
  /// efficiency (Firestore limit 500 ops; typical class sizes are well under).
  Future<int> bulkCheckInAll({
    required String classId,
    required List<Booking> bookings,
    required String checkedInBy,
  }) async {
    final pending =
        bookings.where((b) => !b.checkedIn && b.userId.isNotEmpty).toList();
    if (pending.isEmpty) return 0;

    final now = Timestamp.now();
    final batch = _firestore.batch();

    for (final booking in pending) {
      batch.update(
        _firestore.collection('bookings').doc(booking.id),
        <String, dynamic>{
          'checkedIn': true,
          'checkedInAt': now,
        },
      );
      batch.set(
        _firestore.collection('attendance').doc(),
        <String, dynamic>{
          'classId': classId,
          'userId': booking.userId,
          'gymId': gymId,
          'checkedInBy': checkedInBy,
          'checkedInAt': now,
        },
      );
    }

    await batch.commit();
    return pending.length;
  }

  /// Stream attendance records for a specific user (all classes).
  Stream<List<Map<String, dynamic>>> streamAttendanceForUser(String userId) {
    // Query directly by userId (single-field, auto-indexed) to avoid needing
    // a composite (gymId, userId) index on attendance.
    return _firestore
        .collection('attendance')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {...d.data(), 'id': d.id}).toList()
          ..sort((a, b) {
            final aTs =
                (a['checkedInAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bTs =
                (b['checkedInAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bTs.compareTo(aTs);
          }));
  }

  /// Stream all waitlist entries for a class ordered by join time (FIFO).
  Stream<List<WaitlistEntry>> streamWaitlistForClass(String classId) {
    return _waitlistsQuery
        .where('classId', isEqualTo: classId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => WaitlistEntry.fromSnapshot(
              d as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    });
  }

  /// Stream the 1-based waitlist position for a user in a class.
  /// Emits null if the user is not on the waitlist.
  Stream<int?> streamUserWaitlistPosition(String userId, String classId) {
    return streamWaitlistForClass(classId).map((entries) {
      final index = entries.indexWhere((e) => e.userId == userId);
      return index == -1 ? null : index + 1;
    });
  }

  /// Manually promote the first waitlisted user to a booking (admin action).
  ///
  /// Throws if:
  ///  - nobody is on the waitlist
  ///  - the class has a finite capacity and is still full
  ///
  /// The waitlist entry reference is re-verified inside the transaction to
  /// prevent double-promotion if a concurrent cancellation beats us to it.
  /// Notification is sent best-effort after the transaction.
  Future<void> promoteFirstWaitlisted(String classId) async {
    final snap =
        await _waitlistsQuery.where('classId', isEqualTo: classId).get();

    if (snap.docs.isEmpty) throw Exception('No one is on the waitlist.');

    // Sort client-side (FIFO) — avoids composite index requirement.
    final sorted = snap.docs.toList()
      ..sort((a, b) {
        final ta =
            (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final tb =
            (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return ta.compareTo(tb);
      });
    final entry = sorted.first;
    final userId = (entry.data()['userId'] ?? '') as String;
    final memberName = (entry.data()['memberName'] ?? '') as String;
    final classRef = _firestore.collection('classes').doc(classId);

    String? promotedClassTitle;

    await _firestore.runTransaction((tx) async {
      // Re-verify the waitlist entry still exists (guards against concurrent
      // cancelBooking() or another admin promoting simultaneously).
      final entrySnap = await tx.get(entry.reference);
      if (!entrySnap.exists) {
        throw Exception(
            'This member was already promoted by another action. Refresh and try again.');
      }

      final classSnap = await tx.get(classRef);
      if (!classSnap.exists) throw Exception('Class not found.');
      final data = classSnap.data() ?? <String, dynamic>{};
      final capacity = (data['capacity'] ?? 0) as int;
      final waitlistCount = (data['waitlistCount'] ?? 0) as int;
      final bookedCount = (data['bookedCount'] ?? 0) as int;

      if (capacity > 0 && bookedCount >= capacity) {
        throw Exception(
            'The class is still full ($bookedCount/$capacity). Free a spot first.');
      }

      tx.delete(entry.reference);
      tx.update(classRef, <String, dynamic>{
        'bookedCount': bookedCount + 1,
        'waitlistCount': waitlistCount > 0 ? waitlistCount - 1 : 0,
        'updatedAt': Timestamp.now(),
      });
      tx.set(_firestore.collection('bookings').doc(), <String, dynamic>{
        'userId': userId,
        'classId': classId,
        'gymId': gymId,
        'memberName': memberName,
        'createdAt': Timestamp.now(),
      });
      promotedClassTitle = (data['title'] ?? 'the class') as String;
    });

    // Best-effort notification — a failure here must not undo the promotion.
    try {
      await _notificationService.create(
        userId: userId,
        title: "You're in! 🎉",
        body:
            'A spot opened up in "$promotedClassTitle". You have been moved from the waitlist to the class.',
        type: NotificationType.waitlistPromoted,
        classId: classId,
      );
    } catch (_) {
      // Notification failure is non-fatal; the booking was already created.
    }
  }

  /// Verifies the gym-level QR token and auto-matches the member's current
  /// booked class (window: 30 min before start → 30 min after end).
  ///
  /// Returns a map with key `status`:
  ///   - `'success'`          → checked in; also contains `classTitle`
  ///   - `'already_checked_in'` → already recorded; also contains `classTitle`
  ///   - `'pick'`             → multiple matching classes; contains `classes` list
  ///   - `'error'`            → contains `message`
  Future<Map<String, dynamic>> checkInByGymQr({
    required String gymToken,
    required String userId,
  }) async {
    // 1. Verify gym token against settings/{gymId} (tenant-scoped)
    final settingsDocId = gymId.isNotEmpty ? gymId : 'gym';
    final settingsDoc =
        await _firestore.collection('settings').doc(settingsDocId).get();
    final storedToken = (settingsDoc.data()?['gymQrToken'] ?? '') as String;
    if (storedToken.isEmpty || storedToken != gymToken) {
      return {'status': 'error', 'message': 'Invalid QR code.'};
    }

    // 2. Load member's bookings
    final bookingsSnap =
        await _bookingsQuery.where('userId', isEqualTo: userId).get();

    if (bookingsSnap.docs.isEmpty) {
      return {
        'status': 'error',
        'message': 'You have no bookings yet. Book a class first.',
      };
    }

    final classIds = bookingsSnap.docs
        .map((d) => (d.data()['classId'] ?? '') as String)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    // 3. Find classes happening within ±30 min window
    final now = DateTime.now();
    final matching = <Map<String, dynamic>>[];

    for (var i = 0; i < classIds.length; i += 10) {
      final chunk = classIds.sublist(i, (i + 10).clamp(0, classIds.length));
      final snap = await _firestore
          .collection('classes')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snap.docs) {
        final d = doc.data();
        final start = (d['startTime'] as Timestamp?)?.toDate();
        if (start == null) continue;
        final end = (d['endTime'] as Timestamp?)?.toDate() ??
            start.add(const Duration(hours: 1));

        final windowOpen = start.subtract(const Duration(minutes: 30));
        final windowClose = end.add(const Duration(minutes: 30));

        if (now.isAfter(windowOpen) && now.isBefore(windowClose)) {
          matching.add({
            'classId': doc.id,
            'title': (d['title'] ?? '') as String,
            'startTime': start,
          });
        }
      }
    }

    if (matching.isEmpty) {
      return {
        'status': 'error',
        'message': 'No active class found for you right now.\n'
            'Check-in opens 30 minutes before your class starts.',
      };
    }

    // 4. Multiple matches — let member pick
    if (matching.length > 1) {
      return {'status': 'pick', 'classes': matching};
    }

    // 5. Single match — check in immediately
    return _doCheckIn(
      classId: matching.first['classId'] as String,
      classTitle: matching.first['title'] as String,
      userId: userId,
    );
  }

  /// Completes check-in for a specific class (used after member picks from list).
  Future<Map<String, dynamic>> checkInForClass({
    required String classId,
    required String userId,
  }) async {
    final doc = await _firestore.collection('classes').doc(classId).get();
    final title = (doc.data()?['title'] ?? '') as String;
    return _doCheckIn(classId: classId, classTitle: title, userId: userId);
  }

  /// Checks in a member using a class-specific QR code.
  /// Validates: class exists, time window open (30 min before → class end),
  /// member has a booking for this class.
  Future<Map<String, dynamic>> checkInByClassQr({
    required String classId,
    required String userId,
  }) async {
    final classDoc = await _firestore.collection('classes').doc(classId).get();

    if (!classDoc.exists) {
      return {'status': 'error', 'message': 'Class not found.'};
    }

    final d = classDoc.data()!;
    final title = (d['title'] ?? '') as String;
    final start = (d['startTime'] as Timestamp?)?.toDate();
    final end = (d['endTime'] as Timestamp?)?.toDate();

    if (start == null) {
      return {'status': 'error', 'message': 'Invalid class data.'};
    }

    final now = DateTime.now();
    final windowOpen = start.subtract(const Duration(hours: 1));
    final windowClose = end ?? start.add(const Duration(hours: 1));

    if (now.isBefore(windowOpen)) {
      final minsUntil = windowOpen.difference(now).inMinutes;
      final label = minsUntil >= 60
          ? '${minsUntil ~/ 60}h ${minsUntil % 60}min'
          : '${minsUntil}min';
      return {
        'status': 'error',
        'message': 'Check-in opens in $label.\n'
            'Come back 1 hour before the class starts.',
      };
    }

    if (now.isAfter(windowClose)) {
      return {
        'status': 'error',
        'message': 'This class has already ended.',
      };
    }

    // Verify member is booked (or on waitlist — admins can bypass in UI)
    final bookingSnap = await _firestore
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    if (bookingSnap.docs.isEmpty) {
      return {
        'status': 'error',
        'message': 'You don\'t have a booking for "$title".\n'
            'Please book the class first.',
      };
    }

    return _doCheckIn(classId: classId, classTitle: title, userId: userId);
  }

  Future<Map<String, dynamic>> _doCheckIn({
    required String classId,
    required String classTitle,
    required String userId,
  }) async {
    final existing = await _firestore
        .collection('attendance')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return {'status': 'already_checked_in', 'classTitle': classTitle};
    }

    await _firestore.collection('attendance').add(<String, dynamic>{
      'userId': userId,
      'classId': classId,
      'gymId': gymId,
      'checkedInAt': Timestamp.now(),
      'classTitle': classTitle,
      'checkedInBy': 'qr',
    });

    return {'status': 'success', 'classTitle': classTitle};
  }

  Future<void> markDropInPaid(String bookingId) async {
    await _firestore.collection('bookings').doc(bookingId).update({
      'dropInPaymentStatus': 'paid',
    });
  }

  /// Books a non-member guest as a drop-in. No userId or subscription check.
  Future<void> bookGuestDropIn({
    required String classId,
    required String guestName,
    required String guestEmail,
    String dropInPaymentStatus = 'pending',
  }) async {
    final classRef = _firestore.collection('classes').doc(classId);
    final bookingRef = _firestore.collection('bookings').doc();

    await _firestore.runTransaction((transaction) async {
      final classSnap = await transaction.get(classRef);
      if (!classSnap.exists) throw Exception('Class not found.');
      final data = classSnap.data()!;
      final booked = (data['bookedCount'] ?? 0) as int;
      final capacity = (data['capacity'] ?? 0) as int;
      if (booked >= capacity) throw Exception('This class is full.');

      transaction.update(classRef, {
        'bookedCount': booked + 1,
        'updatedAt': Timestamp.now(),
      });
      transaction.set(bookingRef, {
        'userId': '',
        'classId': classId,
        'gymId': gymId,
        'createdAt': Timestamp.now(),
        'memberName': guestName.trim(),
        'guestEmail': guestEmail.trim().toLowerCase(),
        'isDropIn': true,
        'dropInPaymentStatus': dropInPaymentStatus,
        'checkedIn': false,
      });
    });
  }

  /// Force-books a member into a class and immediately checks them in,
  /// bypassing all offer, capacity, and daily-limit validations.
  ///
  /// If the member already has a booking the existing record is kept and only
  /// the check-in is recorded (idempotent).  If they are on the waitlist their
  /// waitlist entry is removed first.
  Future<void> forceBookAndCheckIn({
    required String classId,
    required String userId,
    String adminId = '',
  }) async {
    final classRef = _firestore.collection('classes').doc(classId);

    // Resolve member name
    final userSnapshot = await _firestore.collection('users').doc(userId).get();
    final userData = userSnapshot.data() ?? <String, dynamic>{};
    final rawDisplayName = (userData['displayName'] ?? '') as String;
    final rawEmail = (userData['email'] ?? '') as String;
    final memberName = rawDisplayName.trim().isNotEmpty
        ? rawDisplayName.trim()
        : rawEmail.trim();

    // Resolve class start time for the bookingDate field
    final classSnapshot = await classRef.get();
    if (!classSnapshot.exists) throw Exception('Class not found.');
    final classData = classSnapshot.data()!;
    final classStartTime =
        (classData['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();

    // Check for existing booking
    final existingBookingQuery = await _bookingsQuery
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    if (existingBookingQuery.docs.isEmpty) {
      // Remove from waitlist if present (cleanup)
      final waitlistQuery = await _waitlistsQuery
          .where('userId', isEqualTo: userId)
          .where('classId', isEqualTo: classId)
          .limit(1)
          .get();

      final bookingRef = _firestore.collection('bookings').doc();

      await _firestore.runTransaction((tx) async {
        final latestClassSnap = await tx.get(classRef);
        final latestData = latestClassSnap.data() ?? <String, dynamic>{};
        final bookedCount = (latestData['bookedCount'] ?? 0) as int;
        int waitlistCount = (latestData['waitlistCount'] ?? 0) as int;

        tx.set(bookingRef, <String, dynamic>{
          'userId': userId,
          'classId': classId,
          'gymId': gymId,
          'createdAt': Timestamp.now(),
          'bookingDate': Timestamp.fromDate(DateTime(
              classStartTime.year, classStartTime.month, classStartTime.day)),
          'memberName': memberName,
          'isDropIn': false,
          'dropInPaymentStatus': 'pending',
          'checkedIn': true,
          'checkedInAt': Timestamp.now(),
        });

        final updates = <String, dynamic>{
          'bookedCount': bookedCount + 1,
          'updatedAt': Timestamp.now(),
        };

        if (waitlistQuery.docs.isNotEmpty) {
          tx.delete(waitlistQuery.docs.first.reference);
          updates['waitlistCount'] = waitlistCount > 0 ? waitlistCount - 1 : 0;
        }

        tx.update(classRef, updates);
      });
    } else {
      // Already booked — just mark the booking as checked-in
      await existingBookingQuery.docs.first.reference.update(<String, dynamic>{
        'checkedIn': true,
        'checkedInAt': Timestamp.now(),
      });
    }

    // Record attendance (idempotent)
    final existingAttendance = await _attendanceQuery
        .where('classId', isEqualTo: classId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();

    if (existingAttendance.docs.isEmpty) {
      await _firestore.collection('attendance').add(<String, dynamic>{
        'classId': classId,
        'userId': userId,
        'gymId': gymId,
        'checkedInBy': adminId,
        'checkedInAt': Timestamp.now(),
      });
    }
  }

  Stream<List<Booking>> streamAllDropIns() {
    return _bookingsQuery
        .where('isDropIn', isEqualTo: true)
        .snapshots()
        .map((q) {
      final list = q.docs.map((d) => Booking.fromSnapshot(d)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream user IDs explicitly marked absent for [classId].
  Stream<Set<String>> streamAbsentUserIds(String classId) {
    return _firestore
        .collection('absences')
        .where('classId', isEqualTo: classId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => (d.data()['userId'] ?? '') as String)
            .where((id) => id.isNotEmpty)
            .toSet());
  }

  /// Mark a member as absent for [classId].
  Future<void> markAbsent({
    required String classId,
    required String userId,
    required String markedBy,
  }) async {
    final existing = await _firestore
        .collection('absences')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) {
      await _firestore.collection('absences').add(<String, dynamic>{
        'classId': classId,
        'userId': userId,
        'gymId': gymId,
        'markedBy': markedBy,
        'markedAt': Timestamp.now(),
      });
    }
  }

  /// Remove an absent mark for [classId].
  Future<void> undoAbsent({
    required String classId,
    required String userId,
  }) async {
    final snap = await _firestore
        .collection('absences')
        .where('userId', isEqualTo: userId)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  /// Promote a specific waitlist entry (by [entryId]) to a booking.
  /// Sends an in-app notification to the promoted user.
  Future<void> promoteWaitlistedEntry({
    required String classId,
    required String entryId,
    required String userId,
    required String memberName,
  }) async {
    final classRef = _firestore.collection('classes').doc(classId);
    final entryRef = _firestore.collection('waitlists').doc(entryId);
    String? promotedClassTitle;

    await _firestore.runTransaction((tx) async {
      final entrySnap = await tx.get(entryRef);
      if (!entrySnap.exists) {
        throw Exception('Waitlist entry no longer exists.');
      }
      final classSnap = await tx.get(classRef);
      if (!classSnap.exists) throw Exception('Class not found.');
      final data = classSnap.data() ?? <String, dynamic>{};
      final capacity = (data['capacity'] ?? 0) as int;
      final bookedCount = (data['bookedCount'] ?? 0) as int;
      final waitlistCount = (data['waitlistCount'] ?? 0) as int;

      if (capacity > 0 && bookedCount >= capacity) {
        throw Exception('Class is still full. Free a spot first.');
      }

      tx.delete(entryRef);
      tx.update(classRef, <String, dynamic>{
        'bookedCount': bookedCount + 1,
        'waitlistCount': waitlistCount > 0 ? waitlistCount - 1 : 0,
        'updatedAt': Timestamp.now(),
      });
      tx.set(_firestore.collection('bookings').doc(), <String, dynamic>{
        'userId': userId,
        'classId': classId,
        'gymId': gymId,
        'memberName': memberName,
        'createdAt': Timestamp.now(),
      });
      promotedClassTitle = (data['title'] ?? 'the class') as String;
    });

    try {
      await _notificationService.create(
        userId: userId,
        title: "You're in! 🎉",
        body:
            'A spot opened in "$promotedClassTitle". You moved from the waitlist to the class.',
        type: NotificationType.waitlistPromoted,
        classId: classId,
      );
    } catch (_) {}
  }

  /// Create in-app notifications for all booked members of [classId].
  Future<void> notifyClassMembers({
    required List<Booking> bookings,
    required String title,
    required String body,
    required String classId,
  }) async {
    for (final b in bookings) {
      if (b.userId.isEmpty) continue;
      await _notificationService.create(
        userId: b.userId,
        title: title,
        body: body,
        type: NotificationType.general,
        classId: classId,
      );
    }
  }
}
