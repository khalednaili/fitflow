import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/gym_announcement.dart';
import '../../../services/announcement_service.dart';
import '../../../utils/crash_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin Announcements Tab
// ─────────────────────────────────────────────────────────────────────────────

class AdminAnnouncementsTab extends StatefulWidget {
  const AdminAnnouncementsTab({super.key, required this.gymId});
  final String gymId;

  @override
  State<AdminAnnouncementsTab> createState() => _AdminAnnouncementsTabState();
}

class _AdminAnnouncementsTabState extends State<AdminAnnouncementsTab> {
  late final AnnouncementService _service;
  GymAnnouncement? _editing; // null = create new

  @override
  void initState() {
    super.initState();
    _service = AnnouncementService(gymId: widget.gymId);
  }

  void _startEdit(GymAnnouncement? a) => setState(() => _editing = a);
  void _clearEdit() => setState(() => _editing = null);

  Future<void> _delete(GymAnnouncement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text('"${a.title}" will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _service.delete(a.id);
      } catch (e, s) {
        await CrashLogger.log(e, s, reason: 'AnnouncementsTab.delete');
      }
    }
  }

  Future<void> _toggle(GymAnnouncement a) async {
    try {
      await _service.toggleActive(a.id, !a.isActive);
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'AnnouncementsTab.toggle');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return isWide
            ? _buildWideLayout(context)
            : _buildNarrowLayout(context);
      },
    );
  }

  // ── Wide layout (≥900px): list left, form right ──────────────────────────

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: announcement list
        SizedBox(
          width: 380,
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                _ListHeader(
                  onNew: () => _startEdit(null),
                ),
                const Divider(height: 1),
                Expanded(child: _AnnouncementList(
                  service: _service,
                  selectedId: _editing?.id,
                  onEdit: _startEdit,
                  onDelete: _delete,
                  onToggle: _toggle,
                )),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // Right: form
        Expanded(
          child: _AnnouncementForm(
            key: ValueKey(_editing?.id ?? 'new'),
            gymId: widget.gymId,
            existing: _editing,
            service: _service,
            onSaved: _clearEdit,
          ),
        ),
      ],
    );
  }

  // ── Narrow layout: list + FAB ─────────────────────────────────────────────

  Widget _buildNarrowLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openFormSheet(context, null),
        backgroundColor: const Color(0xFF0F766E),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: _AnnouncementList(
        service: _service,
        selectedId: null,
        onEdit: (a) => _openFormSheet(context, a),
        onDelete: _delete,
        onToggle: _toggle,
      ),
    );
  }

  Future<void> _openFormSheet(
      BuildContext context, GymAnnouncement? a) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: _AnnouncementForm(
            key: ValueKey(a?.id ?? 'new'),
            gymId: widget.gymId,
            existing: a,
            service: _service,
            onSaved: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Announcement list
// ─────────────────────────────────────────────────────────────────────────────

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          const Text('Announcements',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const Spacer(),
          FilledButton.icon(
            onPressed: onNew,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label:
                const Text('New', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementList extends StatelessWidget {
  const _AnnouncementList({
    required this.service,
    required this.selectedId,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final AnnouncementService service;
  final String? selectedId;
  final void Function(GymAnnouncement) onEdit;
  final void Function(GymAnnouncement) onDelete;
  final void Function(GymAnnouncement) onToggle;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GymAnnouncement>>(
      stream: service.streamAll(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.campaign_outlined,
                    size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('No announcements yet',
                    style: TextStyle(color: Colors.grey.shade400)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          separatorBuilder: (_, __) => Divider(
              height: 1, indent: 16, endIndent: 16,
              color: Colors.grey.shade100),
          itemBuilder: (_, i) => _AnnouncementTile(
            announcement: list[i],
            isSelected: list[i].id == selectedId,
            onEdit: () => onEdit(list[i]),
            onDelete: () => onDelete(list[i]),
            onToggle: () => onToggle(list[i]),
          ),
        );
      },
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({
    required this.announcement,
    required this.isSelected,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final GymAnnouncement announcement;
  final bool isSelected;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final pColor = _pColor(a.priority);
    final dateFmt = DateFormat('d MMM yyyy');
    final isExpired = a.isExpired;

    return InkWell(
      onTap: onEdit,
      hoverColor: const Color(0xFF0F766E).withValues(alpha: 0.03),
      child: Container(
        color: isSelected
            ? const Color(0xFF0F766E).withValues(alpha: 0.05)
            : null,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Priority dot
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 4),
              decoration:
                  BoxDecoration(color: pColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: a.isActive
                                ? Colors.black87
                                : Colors.grey.shade400,
                            decoration: isExpired
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: a.type == AnnouncementType.popup
                              ? const Color(0xFF7C3AED)
                                  .withValues(alpha: 0.1)
                              : const Color(0xFF0F766E)
                                  .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          a.type == AnnouncementType.popup
                              ? 'POPUP'
                              : 'BANNER',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: a.type == AnnouncementType.popup
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF0F766E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    a.body,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        dateFmt.format(a.createdAt),
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade400),
                      ),
                      if (a.expiresAt != null) ...[
                        Text(' · expires ${dateFmt.format(a.expiresAt!)}',
                            style: TextStyle(
                                fontSize: 10,
                                color: isExpired
                                    ? Colors.red
                                    : Colors.grey.shade400)),
                      ],
                      const Spacer(),
                      // Active toggle
                      InkWell(
                        onTap: onToggle,
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          children: [
                            Icon(
                              a.isActive
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              size: 13,
                              color: a.isActive
                                  ? const Color(0xFF059669)
                                  : Colors.grey.shade400,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              a.isActive ? 'Live' : 'Off',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: a.isActive
                                    ? const Color(0xFF059669)
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Delete
                      InkWell(
                        onTap: onDelete,
                        borderRadius: BorderRadius.circular(4),
                        child: Icon(Icons.delete_outline_rounded,
                            size: 15, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _pColor(AnnouncementPriority p) => switch (p) {
        AnnouncementPriority.danger => const Color(0xFFDC2626),
        AnnouncementPriority.warning => const Color(0xFFF97316),
        AnnouncementPriority.info => const Color(0xFF0F766E),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Announcement form (create / edit)
// ─────────────────────────────────────────────────────────────────────────────

class _AnnouncementForm extends StatefulWidget {
  const _AnnouncementForm({
    super.key,
    required this.gymId,
    required this.existing,
    required this.service,
    required this.onSaved,
  });

  final String gymId;
  final GymAnnouncement? existing;
  final AnnouncementService service;
  final VoidCallback onSaved;

  @override
  State<_AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends State<_AnnouncementForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late AnnouncementType _type;
  late AnnouncementPriority _priority;
  DateTime? _expiresAt;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _titleCtrl = TextEditingController(text: a?.title ?? '');
    _bodyCtrl = TextEditingController(text: a?.body ?? '');
    _type = a?.type ?? AnnouncementType.banner;
    _priority = a?.priority ?? AnnouncementPriority.info;
    _expiresAt = a?.expiresAt;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      if (_isEditing) {
        final updated = widget.existing!.copyWith(
          title: _titleCtrl.text.trim(),
          body: _bodyCtrl.text.trim(),
          type: _type,
          priority: _priority,
          expiresAt: _expiresAt,
          clearExpiry: _expiresAt == null,
          bumpVersion: true, // invalidate client dismissals
        );
        await widget.service.update(updated);
      } else {
        await widget.service.create(
          title: _titleCtrl.text.trim(),
          body: _bodyCtrl.text.trim(),
          type: _type,
          priority: _priority,
          createdBy: FirebaseAuth.instance.currentUser?.uid ?? '',
          expiresAt: _expiresAt,
        );
      }
      widget.onSaved();
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'AnnouncementForm.save');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _expiresAt ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.campaign_outlined,
                        color: Color(0xFF0F766E), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEditing
                          ? 'Edit Announcement'
                          : 'New Announcement',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Type toggle ────────────────────────────────────────────
              _FormLabel('Display type'),
              const SizedBox(height: 8),
              _TypeToggle(
                  value: _type,
                  onChanged: (t) => setState(() => _type = t)),
              const SizedBox(height: 16),

              // ── Priority ───────────────────────────────────────────────
              _FormLabel('Priority'),
              const SizedBox(height: 8),
              _PriorityPicker(
                  value: _priority,
                  onChanged: (p) => setState(() => _priority = p)),
              const SizedBox(height: 16),

              // ── Title ──────────────────────────────────────────────────
              _FormLabel('Title *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleCtrl,
                decoration: _inputDecoration(
                    hint: 'e.g. Gym closed Saturday'),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Title is required'
                    : null,
              ),
              const SizedBox(height: 16),

              // ── Body ───────────────────────────────────────────────────
              _FormLabel('Message *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bodyCtrl,
                maxLines: 4,
                decoration: _inputDecoration(
                    hint:
                        'e.g. The gym will be closed this Saturday for maintenance. See you Sunday!'),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Message is required'
                    : null,
              ),
              const SizedBox(height: 16),

              // ── Expiry ─────────────────────────────────────────────────
              _FormLabel('Expiry date (optional)'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickExpiry,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined,
                                size: 16,
                                color: Colors.grey.shade500),
                            const SizedBox(width: 8),
                            Text(
                              _expiresAt != null
                                  ? DateFormat('d MMM yyyy')
                                      .format(_expiresAt!)
                                  : 'No expiry — runs until deactivated',
                              style: TextStyle(
                                fontSize: 13,
                                color: _expiresAt != null
                                    ? Colors.black87
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_expiresAt != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _expiresAt = null),
                      tooltip: 'Clear expiry',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // ── Preview ────────────────────────────────────────────────
              if (_titleCtrl.text.isNotEmpty ||
                  _bodyCtrl.text.isNotEmpty) ...[
                _FormLabel('Preview'),
                const SizedBox(height: 8),
                _PreviewCard(
                    title: _titleCtrl.text.trim(),
                    body: _bodyCtrl.text.trim(),
                    type: _type,
                    priority: _priority),
                const SizedBox(height: 24),
              ],

              // ── Save button ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          _isEditing
                              ? l10n.tr('Save changes')
                              : l10n.tr('Publish announcement'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
                        ),
                ),
              ),

              if (_isEditing) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: widget.onSaved,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: Color(0xFF0F766E), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151)),
      );
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.value, required this.onChanged});
  final AnnouncementType value;
  final ValueChanged<AnnouncementType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: AnnouncementType.values
          .map((t) => _TypeChip(
                type: t,
                selected: value == t,
                onTap: () => onChanged(t),
              ))
          .toList(),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(
      {required this.type,
      required this.selected,
      required this.onTap});
  final AnnouncementType type;
  final bool selected;
  final VoidCallback onTap;

  static const _labels = {
    AnnouncementType.banner: ('Banner', Icons.horizontal_split_rounded,
        'Shows as a colored bar at the top of the dashboard'),
    AnnouncementType.popup: ('Popup', Icons.open_in_new_rounded,
        'Auto-shows as a dialog when members open the app'),
  };

  @override
  Widget build(BuildContext context) {
    final (label, icon, desc) = _labels[type]!;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF0F766E).withValues(alpha: 0.08)
                : Colors.white,
            border: Border.all(
              color: selected
                  ? const Color(0xFF0F766E)
                  : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon,
                      size: 16,
                      color: selected
                          ? const Color(0xFF0F766E)
                          : Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: selected
                              ? const Color(0xFF0F766E)
                              : Colors.black87)),
                ],
              ),
              const SizedBox(height: 4),
              Text(desc,
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityPicker extends StatelessWidget {
  const _PriorityPicker(
      {required this.value, required this.onChanged});
  final AnnouncementPriority value;
  final ValueChanged<AnnouncementPriority> onChanged;

  static const _opts = [
    (AnnouncementPriority.info, 'Info', Color(0xFF0F766E)),
    (AnnouncementPriority.warning, 'Warning', Color(0xFFF97316)),
    (AnnouncementPriority.danger, 'Danger', Color(0xFFDC2626)),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _opts.map((opt) {
        final (p, label, color) = opt;
        final selected = value == p;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.12)
                    : Colors.white,
                border: Border.all(
                  color: selected ? color : Colors.grey.shade300,
                  width: selected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: selected ? color : Colors.grey.shade600)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.title,
    required this.body,
    required this.type,
    required this.priority,
  });

  final String title;
  final String body;
  final AnnouncementType type;
  final AnnouncementPriority priority;

  @override
  Widget build(BuildContext context) {
    const pColors = {
      AnnouncementPriority.info: (
        Color(0xFFF0FDFA),
        Color(0xFF0F766E),
        Color(0xFF99F6E4),
        Icons.info_outline_rounded,
      ),
      AnnouncementPriority.warning: (
        Color(0xFFFFFBEB),
        Color(0xFFB45309),
        Color(0xFFFDE68A),
        Icons.warning_amber_rounded,
      ),
      AnnouncementPriority.danger: (
        Color(0xFFFEF2F2),
        Color(0xFFDC2626),
        Color(0xFFFECACA),
        Icons.error_outline_rounded,
      ),
    };
    final (bg, fg, border, icon) = pColors[priority]!;

    if (type == AnnouncementType.popup) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: fg, size: 22),
            ),
            const SizedBox(height: 10),
            Text(title.isEmpty ? 'Your title here' : title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 36,
              decoration: BoxDecoration(
                  color: fg, borderRadius: BorderRadius.circular(8)),
              child: const Center(
                  child: Text('Got it',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13))),
            ),
          ],
        ),
      );
    }

    // Banner preview
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? 'Your title here' : title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: fg)),
                if (body.isNotEmpty)
                  Text(body,
                      style: TextStyle(
                          fontSize: 11,
                          color: fg.withValues(alpha: 0.85))),
              ],
            ),
          ),
          Icon(Icons.close_rounded,
              size: 14, color: fg.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}
