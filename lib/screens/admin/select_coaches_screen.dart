import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../services/member_service.dart';
import '../../widgets/user_avatar.dart';
import '../../l10n/app_localizations.dart';

class CoachSelectionResult {
  const CoachSelectionResult({required this.id, required this.name});
  final String id;
  final String name;
}

// ── Entry point ───────────────────────────────────────────────────────────────
// On wide screens (web/tablet) renders as a Dialog.
// On narrow screens pushes as a full-screen route.
Future<List<CoachSelectionResult>?> pickCoaches({
  required BuildContext context,
  required String gymId,
  required List<CoachSelectionResult> initialSelection,
}) {
  final isWide = MediaQuery.of(context).size.width > 640;
  if (isWide) {
    return showDialog<List<CoachSelectionResult>>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: SelectCoachesScreen(
            gymId: gymId,
            initialSelection: initialSelection,
          ),
        ),
      ),
    );
  }
  return Navigator.of(context).push<List<CoachSelectionResult>>(
    MaterialPageRoute<List<CoachSelectionResult>>(
      builder: (_) => Scaffold(
        body: SelectCoachesScreen(
          gymId: gymId,
          initialSelection: initialSelection,
        ),
      ),
    ),
  );
}

// ── Screen / Dialog body ──────────────────────────────────────────────────────
class SelectCoachesScreen extends StatefulWidget {
  const SelectCoachesScreen({
    super.key,
    required this.gymId,
    required this.initialSelection,
  });
  final String gymId;
  final List<CoachSelectionResult> initialSelection;

  @override
  State<SelectCoachesScreen> createState() => _SelectCoachesScreenState();
}

class _SelectCoachesScreenState extends State<SelectCoachesScreen> {
  late final _memberService = MemberService(gymId: widget.gymId);
  final _searchController = TextEditingController();
  final Map<String, CoachSelectionResult> _selectedById = {};

  @override
  void initState() {
    super.initState();
    for (final s in widget.initialSelection) {
      _selectedById[s.id] = s;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _displayName(AppUser user) {
    final n = user.displayName.trim();
    return n.isNotEmpty ? n : user.email;
  }

  void _toggle(AppUser coach) {
    final name = _displayName(coach);
    setState(() {
      if (_selectedById.containsKey(coach.id)) {
        _selectedById.remove(coach.id);
      } else {
        _selectedById[coach.id] =
            CoachSelectionResult(id: coach.id, name: name);
      }
    });
  }

  void _confirm() {
    Navigator.of(context).pop(_selectedById.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final selectedCount = _selectedById.length;

    return Column(
      children: [
        // ── Header ───────────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, cs.primary.withValues(alpha: 0.75)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.record_voice_over_outlined,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.tr('Select Coaches'),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        Text(
                          selectedCount == 0
                              ? l10n.tr('Tap a coach to assign them')
                              : '$selectedCount ${l10n.tr(selectedCount == 1 ? 'coach selected' : 'coaches selected')}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Done button in header
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    onPressed: _confirm,
                    child: Text(
                        selectedCount == 0 ? l10n.tr('Skip') : '${l10n.tr('Done')} ($selectedCount)'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Search bar
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: l10n.tr('Search by name or email…'),
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                  prefixIcon: Icon(Icons.search,
                      color: Colors.white.withValues(alpha: 0.8)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.15),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Selected strip ────────────────────────────────────────────────────
        if (_selectedById.isNotEmpty)
          Container(
            color: cs.primaryContainer.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 13, color: cs.primary),
                    const SizedBox(width: 5),
                    Text(l10n.tr('ASSIGNED'),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                            letterSpacing: 0.8)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _selectedById.values.map((coach) {
                    return Chip(
                      avatar: CircleAvatar(
                        backgroundColor: cs.primary,
                        child: Text(
                          coach.name.isNotEmpty
                              ? coach.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      label: Text(coach.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () =>
                          setState(() => _selectedById.remove(coach.id)),
                      backgroundColor:
                          cs.primaryContainer.withValues(alpha: 0.5),
                      side:
                          BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

        // ── Coach list ────────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<AppUser>>(
            stream: _memberService.streamCoaches(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final coaches = snapshot.data ?? <AppUser>[];

              if (coaches.isEmpty) {
                return _EmptyCoaches(
                  icon: Icons.group_off_outlined,
                  message:
                      'No coaches found.\nCreate users with the "coach" role first.',
                );
              }

              final q = _searchController.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? coaches
                  : coaches.where((c) {
                      return _displayName(c).toLowerCase().contains(q) ||
                          c.email.toLowerCase().contains(q);
                    }).toList();

              if (filtered.isEmpty) {
                return _EmptyCoaches(
                  icon: Icons.search_off_outlined,
                  message: '${context.l10n.tr('No coaches match')} "$q"',
                );
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final coach = filtered[i];
                  final name = _displayName(coach);
                  final selected = _selectedById.containsKey(coach.id);
                  return _CoachCard(
                    coach: coach,
                    name: name,
                    selected: selected,
                    accentColor: cs.primary,
                    onTap: () => _toggle(coach),
                  );
                },
              );
            },
          ),
        ),

        // ── Sticky footer ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(context.l10n.tr('Cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                    selectedCount == 0
                        ? context.l10n.tr('Confirm (none)')
                        : '${context.l10n.tr('Confirm')} $selectedCount ${context.l10n.tr(selectedCount == 1 ? 'coach' : 'coaches')}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Coach card ────────────────────────────────────────────────────────────────

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    required this.coach,
    required this.name,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final AppUser coach;
  final String name;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    // Fitness badge
    final fitnessLevel = coach.fitnessLevel;
    final Color fitColor;
    final String fitLabel;
    switch (fitnessLevel.toLowerCase()) {
      case 'rx':
        fitColor = Colors.red.shade600;
        fitLabel = 'RX';
        break;
      case 'intermediate':
        fitColor = Colors.orange.shade600;
        fitLabel = 'Intermediate';
        break;
      case 'beginner':
        fitColor = Colors.green.shade600;
        fitLabel = 'Beginner';
        break;
      default:
        fitColor = cs.onSurfaceVariant;
        fitLabel = '';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.07)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? accentColor.withValues(alpha: 0.5)
                : cs.outlineVariant,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Avatar
                Stack(
                  children: [
                    UserAvatar(
                      photoUrl: coach.photoUrl,
                      initials: initials,
                      color: accentColor,
                      radius: 24,
                    ),
                    if (selected)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                            border: const Border.fromBorderSide(
                                BorderSide(color: Colors.white, width: 1.5)),
                          ),
                          child: const Icon(Icons.check,
                              size: 10, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),

                // Name + email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: selected ? accentColor : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        coach.email,
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      if (fitLabel.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: fitColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: fitColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            context.l10n.tr(fitLabel),
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: fitColor),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Check indicator
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: selected
                      ? Icon(Icons.check_circle,
                          key: const ValueKey('checked'),
                          color: accentColor,
                          size: 22)
                      : Icon(Icons.radio_button_unchecked,
                          key: const ValueKey('unchecked'),
                          color: cs.outlineVariant,
                          size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyCoaches extends StatelessWidget {
  const _EmptyCoaches({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
