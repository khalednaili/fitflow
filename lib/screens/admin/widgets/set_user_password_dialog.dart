import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/app_user.dart';
import '../../../services/admin_auth_service.dart';
import '../../../l10n/app_localizations.dart';

Future<void> showSetUserPasswordDialog({
  required BuildContext context,
  required AppUser member,
  AdminAuthService? adminAuthService,
}) async {
  final service = adminAuthService ?? AdminAuthService();
  final l10n = context.l10n;
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();

  bool obscure = true;
  bool isSaving = false;
  String? inlineError;

  try {
    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              final password = passwordController.text.trim();
              final confirm = confirmController.text.trim();

              if (password.length < 6) {
                setDialogState(() {
                  inlineError = l10n.tr('Password must be at least 6 characters.');
                });
                return;
              }

              if (password != confirm) {
                setDialogState(() {
                  inlineError = l10n.tr('Passwords do not match.');
                });
                return;
              }

              setDialogState(() {
                isSaving = true;
                inlineError = null;
              });

              try {
                await service.setUserPassword(
                  userId: member.id,
                  newPassword: password,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } on FirebaseFunctionsException catch (error) {
                setDialogState(() {
                  isSaving = false;
                  inlineError = error.message ?? l10n.tr('Could not update password.');
                });
              } catch (_) {
                setDialogState(() {
                  isSaving = false;
                  inlineError = l10n.tr('Could not update password.');
                });
              }
            }

            final memberName = member.displayName.trim().isEmpty
                ? member.email
                : member.displayName;

            return AlertDialog(
              title: Text(l10n.tr('Set user password')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(memberName),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: l10n.tr('New password'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmController,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: l10n.tr('Confirm password'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setDialogState(() {
                            obscure = !obscure;
                          });
                        },
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (inlineError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      inlineError!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.tr('Cancel')),
                ),
                FilledButton(
                  onPressed: isSaving ? null : submit,
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.tr('Save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('Password updated successfully.'))),
      );
    }
  } finally {
    passwordController.dispose();
    confirmController.dispose();
  }
}
