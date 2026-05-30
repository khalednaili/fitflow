import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:fit_flow/utils/crash_logger.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../home/home_shell.dart';
import '../super_admin/bootstrap_super_admin_screen.dart';
import '../super_admin/super_admin_shell.dart';
import 'gym_picker_screen.dart';
import 'sign_in_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();
  // Cache both streams so StreamBuilder never gets a new object on rebuild.
  late final Stream<User?> _authStream = _authService.authStateChanges();
  String? _cachedUid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;

  /// Returns a cached user-document stream, only recreating it when the UID
  /// changes (e.g. after sign-out / sign-in with a different account).
  Stream<DocumentSnapshot<Map<String, dynamic>>> _streamForUid(String uid) {
    if (uid != _cachedUid) {
      _cachedUid = uid;
      _userDocStream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots();
    }
    return _userDocStream!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final firebaseUser = snapshot.data;
        if (firebaseUser == null) {
          unawaited(CrashLogger.clearUser());
          return const SignInScreen();
        }

        // Stream user Firestore doc so role changes (e.g. after bootstrap) are
        // detected immediately without requiring a full sign-out/sign-in.
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _streamForUid(firebaseUser.uid),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!userSnap.hasData || !userSnap.data!.exists) {
              return FutureBuilder<bool>(
                future: needsBootstrap(),
                builder: (context, bootSnap) {
                  if (bootSnap.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (bootSnap.data == true) {
                    return const BootstrapSuperAdminScreen();
                  }
                  return const HomeShell();
                },
              );
            }

            final appUser = AppUser.fromSnapshot(userSnap.data!);
            unawaited(CrashLogger.setUser(firebaseUser.uid));

            if (appUser.isSuperAdmin) {
              return const SuperAdminShell();
            }

            // Members who haven't joined a gym yet must pick one first.
            if (appUser.gymId.isEmpty && appUser.role == 'member') {
              return const GymPickerScreen();
            }

            return const HomeShell();
          },
        );
      },
    );
  }
}
