// ignore_for_file: avoid_classes_with_only_static_members

/// # FitFlow — Firestore Database Schema
///
/// This file documents every Firestore collection used by the app.
/// It is a **reference-only** file: none of the classes here are
/// instantiated at runtime.
///
/// ## Collections overview
///
/// ```
/// firestore root
/// ├── users/                    – Authenticated gym members & staff
/// ├── classes/                  – Scheduled gym classes
/// ├── bookings/                 – Confirmed class bookings
/// ├── waitlists/                – Waitlist entries for full classes
/// ├── attendance/               – Check-in records (immutable)
/// ├── membership_plans/         – Offer/plan catalogue
/// ├── subscriptions/            – Legacy Stripe subscription mirror
/// └── user_subscriptions/       – Manual payment-tracked subscriptions
/// ```
///
/// ## Relationships
///
/// ```
/// users  ──< user_subscriptions >── membership_plans
/// users  ──< bookings            >── classes
/// users  ──< waitlists           >── classes
/// users  ──< attendance          >── classes
/// classes ──  membership_plans  (requiredOfferPlanId, optional gate)
/// ```
library;

// ─────────────────────────────────────────────────────────────────────────────
// Collection: users
// ─────────────────────────────────────────────────────────────────────────────

/// ## `users/{userId}`
///
/// Stores profile and membership state for every app user.
/// The document ID equals the Firebase Auth UID.
///
/// **Model:** [AppUser]
/// **Service:** [MemberService]
///
/// ### Fields
///
/// | Field               | Type        | Description                                       |
/// |---------------------|-------------|---------------------------------------------------|
/// | `email`             | `String`    | User's email address                              |
/// | `displayName`       | `String`    | Full name shown in the UI                         |
/// | `role`              | `String`    | `'member'` · `'staff'` · `'admin'` · `'owner'`   |
/// | `membershipPlanId`  | `String`    | *(legacy)* ref → `membership_plans/{id}`          |
/// | `subscriptionStatus`| `String`    | *(legacy)* `'none'` · `'active'` · …             |
/// | `offerStartAt`      | `Timestamp?`| *(legacy)* start of the directly-assigned offer   |
/// | `offerEndAt`        | `Timestamp?`| *(legacy)* end of the directly-assigned offer     |
/// | `createdAt`         | `Timestamp` | Document creation time                            |
/// | `updatedAt`         | `Timestamp` | Last write time                                   |
///
/// ### Notes
/// - The legacy `membershipPlanId` / `offerStartAt` / `offerEndAt` fields are
///   still read as a fallback when no `user_subscriptions` record exists.
/// - Role checks: `isAdmin → role ∈ {admin, owner}`;
///   `isStaff → role == staff`.
///
/// ### Security rules (summary)
/// - **read**: own document OR staff/admin
/// - **create**: own document (role must be `member`) OR staff/admin
/// - **update**: staff/admin, or owner of document (cannot change role/email)
abstract class UsersSchema {}

// ─────────────────────────────────────────────────────────────────────────────
// Collection: classes
// ─────────────────────────────────────────────────────────────────────────────

/// ## `classes/{classId}`
///
/// Each document represents one scheduled gym class occurrence.
/// Recurring classes are stored as individual documents sharing a
/// `recurrenceGroupId`.
///
/// **Model:** [GymClass]
/// **Service:** [ClassService]
///
/// ### Fields
///
/// | Field                | Type         | Description                                         |
/// |----------------------|--------------|-----------------------------------------------------|
/// | `title`              | `String`     | Class name (e.g. "HIIT Monday")                     |
/// | `coachName`          | `String`     | Coach's display name                                |
/// | `description`        | `String`     | Short class description                             |
/// | `startTime`          | `Timestamp`  | Class start date-time                               |
/// | `endTime`            | `Timestamp`  | Class end date-time                                 |
/// | `requiredOfferPlanId`| `String`     | If non-empty, ref → `membership_plans/{id}` required to book |
/// | `repeatWeekly`       | `bool`       | `true` when this is part of a recurring series      |
/// | `repeatWeekdays`     | `List<int>`  | ISO weekdays (1=Mon … 7=Sun) for the recurrence     |
/// | `recurrenceGroupId`  | `String?`    | Shared ID across all occurrences of a series        |
/// | `capacity`           | `int`        | Maximum number of bookings allowed                  |
/// | `bookedCount`        | `int`        | Current confirmed bookings (server-incremented)     |
/// | `waitlistCount`      | `int`        | Current waitlist entries (server-incremented)       |
/// | `createdAt`          | `Timestamp`  | Document creation time                              |
/// | `updatedAt`          | `Timestamp`  | Last write time                                     |
///
/// ### Security rules (summary)
/// - **read**: any signed-in user
/// - **write**: staff/admin only
abstract class ClassesSchema {}

// ─────────────────────────────────────────────────────────────────────────────
// Collection: bookings
// ─────────────────────────────────────────────────────────────────────────────

/// ## `bookings/{bookingId}`
///
/// A confirmed booking linking a user to a class.
/// Booking is only allowed when the class is not full; otherwise the user
/// is placed on the waitlist (see [WaitlistsSchema]).
///
/// **Model:** [Booking]
/// **Service:** [BookingService]
///
/// ### Fields
///
/// | Field        | Type        | Description                              |
/// |--------------|-------------|------------------------------------------|
/// | `userId`     | `String`    | ref → `users/{id}`                       |
/// | `classId`    | `String`    | ref → `classes/{id}`                     |
/// | `createdAt`  | `Timestamp` | Time the booking was made                |
/// | `memberName` | `String`    | Denormalised display name at booking time|
///
/// ### Security rules (summary)
/// - **read**: any signed-in user
/// - **create**: own booking only; allowed fields: `userId`, `classId`,
///   `createdAt`, `memberName`
/// - **update**: not allowed
/// - **delete**: own booking OR staff/admin
abstract class BookingsSchema {}

// ─────────────────────────────────────────────────────────────────────────────
// Collection: waitlists
// ─────────────────────────────────────────────────────────────────────────────

/// ## `waitlists/{waitlistId}`
///
/// Holds waitlist entries when a class is at capacity.
/// Same shape as [BookingsSchema].
///
/// **Service:** [BookingService]
///
/// ### Fields
///
/// | Field        | Type        | Description                                |
/// |--------------|-------------|--------------------------------------------|
/// | `userId`     | `String`    | ref → `users/{id}`                         |
/// | `classId`    | `String`    | ref → `classes/{id}`                       |
/// | `createdAt`  | `Timestamp` | Time the waitlist entry was created        |
/// | `memberName` | `String`    | Denormalised display name at creation time |
///
/// ### Security rules (summary)
/// - **read**: own entry OR staff/admin
/// - **create**: own entry only; same allowed-fields constraint as bookings
/// - **update**: not allowed
/// - **delete**: own entry OR staff/admin
abstract class WaitlistsSchema {}

// ─────────────────────────────────────────────────────────────────────────────
// Collection: attendance
// ─────────────────────────────────────────────────────────────────────────────

/// ## `attendance/{attendanceId}`
///
/// Immutable check-in records written by staff when a member attends a class.
///
/// **Service:** [BookingService] (`streamCheckedInUserIds`)
///
/// ### Fields
///
/// | Field          | Type        | Description                                      |
/// |----------------|-------------|--------------------------------------------------|
/// | `classId`      | `String`    | ref → `classes/{id}`                             |
/// | `userId`       | `String`    | ref → `users/{id}` — the member who checked in   |
/// | `checkedInBy`  | `String`    | ref → `users/{id}` — staff/admin who performed check-in |
/// | `checkedInAt`  | `Timestamp` | Check-in timestamp                               |
///
/// ### Security rules (summary)
/// - **read**: any signed-in user
/// - **create**: staff/admin only; allowed fields enforced by rules
/// - **update / delete**: not allowed
abstract class AttendanceSchema {}

// ─────────────────────────────────────────────────────────────────────────────
// Collection: membership_plans
// ─────────────────────────────────────────────────────────────────────────────

/// ## `membership_plans/{planId}`
///
/// The catalogue of membership offers available to members.
///
/// **Model:** [MembershipPlan]
/// **Service:** [SubscriptionService]
///
/// ### Fields
///
/// | Field             | Type      | Description                                                    |
/// |-------------------|-----------|----------------------------------------------------------------|
/// | `name`            | `String`  | Human-readable plan name                                       |
/// | `offerType`       | `String`  | `'limited_sessions'` · `'weekly_recurring'` · `'monthly_recurring'` |
/// | `checkinsPerWeek` | `int`     | Max check-ins per week (for `weekly_recurring`)               |
/// | `checkinsPerMonth`| `int`     | Max check-ins per month (for `monthly_recurring`)             |
/// | `totalCheckins`   | `int`     | Total check-ins in the pack (for `limited_sessions`)          |
/// | `billingCycle`    | `String`  | `'recurrent'` · `'one_time'`                                  |
/// | `durationValue`   | `int`     | Positive duration quantity (e.g. `3`, `5`, `12`)              |
/// | `durationUnit`    | `String`  | `'day'` · `'week'` · `'month'` · `'year'`                     |
/// | `price`           | `int`     | Price in whole currency units (e.g. `50` = 50 TND, not cents)   |
/// | `priceMonthly`    | `int`     | Alias for `price` — kept for backward compatibility            |
/// | `currency`        | `String`  | ISO 4217 currency code (default `'TND'`)                       |
/// | `description`     | `String`  | Longer description shown to members                            |
/// | `active`          | `bool`    | Only active plans are shown to members                         |
/// | `stripePriceId`   | `String`  | Stripe Price ID (empty when Stripe is not used)                |
/// | `createdAt`       | `Timestamp` | Document creation time                                       |
/// | `updatedAt`       | `Timestamp` | Last write time                                              |
///
/// ### Security rules (summary)
/// - **read**: any signed-in user
/// - **write**: admin/owner only
abstract class MembershipPlansSchema {}

// ─────────────────────────────────────────────────────────────────────────────
// Collection: subscriptions  (legacy / Stripe mirror)
// ─────────────────────────────────────────────────────────────────────────────

/// ## `subscriptions/{subscriptionId}` *(legacy)*
///
/// Mirror of Stripe subscription objects written by a Cloud Function.
/// Only queried to check for active/trialing/past_due status.
/// Prefer [UserSubscriptionsSchema] for new subscriptions.
///
/// **Service:** [SubscriptionService] (`streamCurrentSubscription`)
///
/// ### Key fields queried by the app
///
/// | Field    | Type     | Description                                      |
/// |----------|----------|--------------------------------------------------|
/// | `userId` | `String` | ref → `users/{id}`                               |
/// | `status` | `String` | `'active'` · `'trialing'` · `'past_due'` · …    |
///
/// ### Security rules (summary)
/// - **read**: own document OR staff/admin
/// - **create / update**: staff/admin
/// - **delete**: admin/owner only
abstract class SubscriptionsSchema {}

// ─────────────────────────────────────────────────────────────────────────────
// Collection: user_subscriptions
// ─────────────────────────────────────────────────────────────────────────────

/// ## `user_subscriptions/{subscriptionId}`
///
/// Manual, payment-tracked subscriptions managed by staff.
/// Document ID convention: `{userId}_{planId}`.
///
/// **Model:** [UserSubscription], [PaymentRecord]
/// **Service:** [SubscriptionService]
///
/// ### Fields
///
/// | Field            | Type              | Description                                          |
/// |------------------|-------------------|------------------------------------------------------|
/// | `userId`         | `String`          | ref → `users/{id}`                                   |
/// | `planId`         | `String`          | ref → `membership_plans/{id}`                        |
/// | `totalAmount`    | `int`             | Full price in whole currency units (not cents)       |
/// | `amountPaid`     | `int`             | Amount paid so far in whole currency units           |
/// | `currency`       | `String`          | ISO 4217 currency code (default `'TND'`)             |
/// | `status`         | `String`          | `'pending'` · `'completed'` · `'cancelled'`          |
/// | `startDate`      | `Timestamp?`      | Subscription validity start                          |
/// | `endDate`        | `Timestamp?`      | Subscription validity end (`null` = open-ended)      |
/// | `paymentHistory` | `List<Map>`       | Ordered list of [PaymentRecordSchema] entries        |
/// | `updatedAt`      | `Timestamp`       | Last write time                                      |
///
/// ### `paymentHistory` entries — [PaymentRecord]
///
/// | Field    | Type        | Description                                          |
/// |----------|-------------|------------------------------------------------------|
/// | `amount` | `int`       | Payment amount in whole currency units               |
/// | `date`   | `Timestamp` | Date the payment was recorded                        |
/// | `method` | `String`    | `'cash'` · `'card'` · `'transfer'` · …              |
/// | `notes`  | `String`    | Optional free-text note                              |
///
/// ### Status transitions
/// ```
/// pending ──(full payment recorded)──> completed
/// pending ──(admin cancels)──────────> cancelled
/// ```
///
/// ### Security rules (summary)
/// - **read**: own document OR staff/admin
/// - **create**: staff/admin (`userId` and `planId` required)
/// - **update**: staff/admin
/// - **delete**: admin/owner only
abstract class UserSubscriptionsSchema {}
