# Octiv-Style Gym App (Flutter + Firebase)

This is a Flutter + Firebase starter app inspired by Octiv Fitness-style workflows.

## Included MVP Features

- Email/password authentication
- Member profile storage
- Upcoming classes feed from Firestore
- Class booking flow with capacity checks and waitlist fallback
- Booking cancellation with automatic waitlist promotion
- My bookings screen
- Attendance check-in (admin/staff)
- Admin dashboard (class create/edit/delete, member role management)
- Membership plans + Stripe checkout session integration hooks
- Role-based navigation and hardened Firestore rules

## Tech Stack

- Flutter (Material 3)
- Firebase Auth
- Cloud Firestore

## Project Structure

- `lib/screens/auth`: sign in/up and auth gate
- `lib/screens/home`: classes, bookings, profile
- `lib/services`: auth, class, booking, member services
- `lib/models`: user, class, booking entities

## 1) Create Flutter app shell (if needed)

If this folder is not already a Flutter project, run:

```bash
flutter create .
```

Then keep the generated platform folders (`android`, `ios`, etc.) and `pubspec.yaml` dependencies from this repo.

## 2) Install dependencies

```bash
flutter pub get
```

## 3) Connect Firebase

1. Create a Firebase project.
2. Enable Authentication (Email/Password).
3. Enable Firestore.
4. Register Android/iOS apps in Firebase.
5. Add config files:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`
6. Configure native Gradle/Xcode integration as per Firebase docs.

`main.dart` uses `Firebase.initializeApp()`.

## 4) Firestore Collections

Create these collections:

- `users/{uid}`
  - `email` (string)
  - `displayName` (string)
  - `role` (string, e.g. member)
- `classes/{classId}`
  - `title` (string)
  - `coachName` (string)
  - `description` (string)
  - `startTime` (timestamp)
  - `capacity` (number)
  - `bookedCount` (number)
- `bookings/{bookingId}`
  - `userId` (string)
  - `classId` (string)
  - `createdAt` (timestamp)
- `waitlists/{waitlistId}`
  - `userId` (string)
  - `classId` (string)
  - `createdAt` (timestamp)
- `attendance/{attendanceId}`
  - `classId` (string)
  - `userId` (string)
  - `checkedInBy` (string)
  - `checkedInAt` (timestamp)
- `membership_plans/{planId}`
  - `name` (string)
  - `description` (string)
  - `priceMonthly` (number)
  - `currency` (string)
  - `active` (bool)
  - `stripePriceId` (string)
- `subscriptions/{subscriptionId}`
  - `userId` (string)
  - `status` (string)
  - `planId` (string)
  - `planName` (string)

## 5) Seed sample classes quickly

Use Firestore console to add class docs, or run your own admin script.

## 6) Run

```bash
flutter run
```

## Next Feature Ideas (Octiv-like roadmap)

- Full Stripe customer portal redirect flow in-app
- Automated retries and dunning for failed payments
- Marketing automations (email/SMS)
- Workout builder + performance tracking
- In-app notifications and reminders

## Stripe Backend Functions

`lib/services/subscription_service.dart` calls two Firebase Functions:

- `createStripeCheckoutSession`
- `cancelStripeSubscription`

Deploy these callable functions in your Firebase backend and return `checkoutUrl` for the checkout call.
