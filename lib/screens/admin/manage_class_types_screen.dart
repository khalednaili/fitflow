import 'package:flutter/material.dart';

import 'package:fit_flow/utils/crash_logger.dart';
import '../../models/class_type.dart';
import '../../services/class_type_service.dart';
import '../../l10n/app_localizations.dart';

const List<Color> _colorChoices = <Color>[
  Color(0xFF147AD6),
  Color(0xFF008272),
  Color(0xFFD83B01),
  Color(0xFF5C2D91),
  Color(0xFFC239B3),
  Color(0xFFEAA300),
  Color(0xFF498205),
  Color(0xFF4F6BED),
  Color(0xFFB146C2),
  Color(0xFF7A7574),
];

class ManageClassTypesScreen extends StatelessWidget {
  const ManageClassTypesScreen({super.key, this.gymId = ''});

  final String gymId;

  @override
  Widget build(BuildContext context) {
    final service = ClassTypeService(gymId: gymId);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('Class Types'))),
      body: StreamBuilder<List<ClassType>>(
        stream: service.streamClassTypes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final types = snapshot.data ?? <ClassType>[];
          if (types.isEmpty) {
            return Center(
              child: Text(l10n.tr('No class types yet. Add one below.')),
            );
          }
          return ListView.builder(
            itemCount: types.length,
            itemBuilder: (context, index) {
              final ct = types[index];
              final color =
                  ct.colorValue != null ? Color(ct.colorValue!) : null;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color ?? Colors.grey.shade300,
                  child: color == null
                      ? const Icon(Icons.palette_outlined, size: 18)
                      : null,
                ),
                title: Text(ct.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: l10n.tr('Edit'),
                      onPressed: () =>
                          _showEditorDialog(context, service, existing: ct),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: l10n.tr('Delete'),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(l10n.tr('Delete class type?')),
                            content: Text(
                                '${l10n.tr('Remove')} "${ct.name}"? ${l10n.tr('This cannot be undone.')}'),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: Text(l10n.tr('Cancel')),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: Text(l10n.tr('Delete')),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await service.deleteClassType(ct.id);
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditorDialog(context, service),
        icon: const Icon(Icons.add),
        label: Text(l10n.tr('Add Class Type')),
      ),
    );
  }

  Future<void> _showEditorDialog(
    BuildContext context,
    ClassTypeService service, {
    ClassType? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ClassTypeEditorDialog(
        service: service,
        existing: existing,
      ),
    );
  }
}

class _ClassTypeEditorDialog extends StatefulWidget {
  const _ClassTypeEditorDialog({required this.service, this.existing});

  final ClassTypeService service;
  final ClassType? existing;

  @override
  State<_ClassTypeEditorDialog> createState() => _ClassTypeEditorDialogState();
}

class _ClassTypeEditorDialogState extends State<_ClassTypeEditorDialog> {
  final _nameController = TextEditingController();
  int? _selectedColorValue;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameController.text = widget.existing!.name;
      _selectedColorValue = widget.existing!.colorValue;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final l10n = context.l10n;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('Please enter a class type name.'))),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (widget.existing == null) {
        await widget.service.addClassType(
          name: name,
          colorValue: _selectedColorValue,
        );
      } else {
        await widget.service.updateClassType(
          id: widget.existing!.id,
          name: name,
          colorValue: _selectedColorValue,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'saveClassType');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.tr('Save failed')}: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.tr(widget.existing == null ? 'New Class Type' : 'Edit Class Type'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.tr('Name'),
                  hintText: l10n.tr('e.g. Indoor Rowing'),
                ),
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.tr('Card color'),
                  prefixIcon: const Icon(Icons.palette_outlined),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: Text(l10n.tr('Default')),
                      selected: _selectedColorValue == null,
                      onSelected: (_) {
                        setState(() => _selectedColorValue = null);
                      },
                    ),
                    ..._colorChoices.map((color) {
                      final colorValue = color.toARGB32();
                      final selected = _selectedColorValue == colorValue;
                      return InkWell(
                        onTap: () {
                          setState(() => _selectedColorValue = colorValue);
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed:
                        _isSaving ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.tr('Cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.tr('Save')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
