import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../../models/app_user.dart';
import '../../l10n/app_localizations.dart';

class SuperAdminsListScreen extends StatelessWidget {
  const SuperAdminsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('Super Admins')),
        actions: [
          FilledButton.icon(
            onPressed: () => _showCreateDialog(context),
            icon: Icon(Icons.add),
            label: Text(context.l10n.tr('New Super Admin')),
          ),
          SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'super_admin')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('${context.l10n.tr('Error')}: ${snapshot.error}'),
            );
          }

          final users =
              snapshot.data?.docs.map(AppUser.fromSnapshot).toList() ?? [];

          if (users.isEmpty) {
            return Center(
                child: Text(context.l10n.tr('No super admins found.')));
          }

          return ListView.separated(
            padding: EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => SizedBox(height: 8),
            itemBuilder: (context, i) => _SuperAdminTile(user: users[i]),
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _CreateSuperAdminDialog(),
    );
  }
}

class _SuperAdminTile extends StatelessWidget {
  const _SuperAdminTile({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Text(
            user.displayName.isNotEmpty
                ? user.displayName[0].toUpperCase()
                : user.email[0].toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title:
            Text(user.displayName.isNotEmpty ? user.displayName : user.email),
        subtitle: Text(user.email),
        trailing: Chip(
          label: Text(
            context.l10n.tr('Super Admin'),
            style: TextStyle(fontSize: 11),
          ),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Super Admin Dialog
// ---------------------------------------------------------------------------
class _CreateSuperAdminDialog extends StatefulWidget {
  const _CreateSuperAdminDialog();

  @override
  State<_CreateSuperAdminDialog> createState() =>
      _CreateSuperAdminDialogState();
}

class _CreateSuperAdminDialogState extends State<_CreateSuperAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscurePassword = true;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('superAdminCreateSuperAdmin');
      await callable.call(<String, dynamic>{
        'displayName': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.tr('Super admin created successfully!')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseFunctionsException catch (e, s) {
      await CrashLogger.log(e, s, reason: 'createSuperAdmin');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? context.l10n.tr('An error occurred')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'createSuperAdmin');
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.tr('New Super Admin')),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.tr('Full Name *'),
                  prefixIcon: Icon(Icons.person_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.l10n.tr('Required')
                    : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: context.l10n.tr('Email *'),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return context.l10n.tr('Required');
                  }
                  if (!v.contains('@')) {
                    return context.l10n.tr('Enter a valid email');
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: context.l10n.tr('Password *'),
                  prefixIcon: Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return context.l10n.tr('Required');
                  }
                  if (v.length < 6) {
                    return context.l10n.tr('Minimum 6 characters');
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(context.l10n.tr('Cancel')),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(context.l10n.tr('Create')),
        ),
      ],
    );
  }
}
