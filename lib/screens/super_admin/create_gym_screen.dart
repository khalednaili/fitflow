import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:fit_flow/utils/crash_logger.dart';
import '../../l10n/app_localizations.dart';

class CreateGymScreen extends StatefulWidget {
  const CreateGymScreen({super.key});

  @override
  State<CreateGymScreen> createState() => _CreateGymScreenState();
}

class _CreateGymScreenState extends State<CreateGymScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscurePassword = true;

  final _gymNameController = TextEditingController();
  final _gymAddressController = TextEditingController();
  final _gymDescriptionController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();

  @override
  void dispose() {
    _gymNameController.dispose();
    _gymAddressController.dispose();
    _gymDescriptionController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    setState(() => _loading = true);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('superAdminCreateGym');
      await callable.call(<String, dynamic>{
        'gymName': _gymNameController.text.trim(),
        'gymAddress': _gymAddressController.text.trim(),
        'gymDescription': _gymDescriptionController.text.trim(),
        'adminName': _adminNameController.text.trim(),
        'adminEmail': _adminEmailController.text.trim(),
        'adminPassword': _adminPasswordController.text,
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr(
              'Gym "${_gymNameController.text.trim()}" created successfully!',
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
      nav.pop();
    } on FirebaseFunctionsException catch (e, s) {
      await CrashLogger.log(e, s, reason: 'createGym');
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message ?? l10n.tr('An error occurred')),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'createGym');
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('Error')}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.tr('Create New Gym'))),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Gym Info ───────────────────────────────────────
                  Text(context.l10n.tr('Gym Information'),
                      style: Theme.of(context).textTheme.titleLarge),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _gymNameController,
                    decoration: InputDecoration(
                      labelText: context.l10n.tr('Gym Name *'),
                      prefixIcon: Icon(Icons.fitness_center),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.tr('Required')
                        : null,
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _gymAddressController,
                    decoration: InputDecoration(
                      labelText: context.l10n.tr('Address'),
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _gymDescriptionController,
                    decoration: InputDecoration(
                      labelText: context.l10n.tr('Description'),
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                    maxLines: 3,
                  ),
                  SizedBox(height: 32),

                  // ── Admin Account ──────────────────────────────────
                  Text(context.l10n.tr('Admin Account'),
                      style: Theme.of(context).textTheme.titleLarge),
                  SizedBox(height: 4),
                  Text(
                    l10n.tr(
                        'This account will be the primary admin for the gym.'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _adminNameController,
                    decoration: InputDecoration(
                      labelText: context.l10n.tr('Admin Full Name *'),
                      prefixIcon: Icon(Icons.person_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.tr('Required')
                        : null,
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _adminEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: context.l10n.tr('Admin Email *'),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return l10n.tr('Required');
                      }
                      if (!v.contains('@')) {
                        return l10n.tr('Enter a valid email');
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _adminPasswordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: context.l10n.tr('Admin Password *'),
                      prefixIcon: Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return l10n.tr('Required');
                      }
                      if (v.length < 6) {
                        return l10n.tr('Minimum 6 characters');
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 32),

                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16)),
                    child: _loading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(context.l10n.tr('Create Gym')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
