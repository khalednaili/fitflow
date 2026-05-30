import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fit_flow/utils/crash_logger.dart';
import '../../l10n/app_localizations.dart';

/// Shown when the app detects no super_admin exists yet.
/// Lets the currently signed-in user claim super admin for the first time.
class BootstrapSuperAdminScreen extends StatefulWidget {
  const BootstrapSuperAdminScreen({super.key});

  @override
  State<BootstrapSuperAdminScreen> createState() =>
      _BootstrapSuperAdminScreenState();
}

class _BootstrapSuperAdminScreenState extends State<BootstrapSuperAdminScreen> {
  bool _loading = false;

  Future<void> _claim() async {
    setState(() => _loading = true);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('bootstrapSuperAdmin');
      await callable.call<Map<String, dynamic>>({});
      // Reload the ID token so AuthGate picks up the updated role
      await FirebaseAuth.instance.currentUser?.reload();
      // AuthGate will automatically rebuild and route to SuperAdminShell
    } on FirebaseFunctionsException catch (e, s) {
      await CrashLogger.log(e, s, reason: 'claimBootstrapSuperAdmin');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? context.l10n.tr('An error occurred')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'claimBootstrapSuperAdmin');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.tr('Error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(Icons.bolt, color: Colors.white, size: 40),
                ),
                SizedBox(height: 24),
                Text(
                  l10n.tr('Welcome to FitFlow'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  l10n.tr(
                    'No super admin exists yet.\nClaim the super admin role to get started.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),

                // Account info box
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: cs.outline.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          (user?.email ?? '?')[0].toUpperCase(),
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName?.isNotEmpty == true
                                  ? user!.displayName!
                                  : l10n.tr('Signed in user'),
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              user?.email ?? '',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          l10n.tr('Will become super admin'),
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onTertiaryContainer,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: _loading ? null : _claim,
                  icon: _loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(Icons.admin_panel_settings),
                  label: Text(
                    _loading
                        ? l10n.tr('Setting up…')
                        : l10n.tr('Claim Super Admin'),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: Size(double.infinity, 52),
                  ),
                ),
                SizedBox(height: 12),
                TextButton(
                  onPressed: _signOut,
                  child: Text(context.l10n.tr('Sign out')),
                ),
                SizedBox(height: 32),
                Text(
                  l10n.tr('This option disappears once a super admin exists.'),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns true if bootstrap setup is still required.
Future<bool> needsBootstrap() async {
  try {
    final snap =
        await FirebaseFirestore.instance.collection('config').doc('app').get();
    if (!snap.exists) return true;
    return snap.data()?['bootstrapped'] != true;
  } catch (error, stackTrace) {
    await CrashLogger.log(error, stackTrace, reason: 'needsBootstrap');
    // If config doc is unreadable (fresh deploy with no rules yet), assume
    // bootstrap is still needed.
    return true;
  }
}
