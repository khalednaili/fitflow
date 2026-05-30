import 'package:flutter/material.dart';

// ── Role definitions ──────────────────────────────────────────────────────────

class RoleDef {
  const RoleDef({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

const kAllRoles = [
  RoleDef(
    id: 'member',
    label: 'Member',
    description: 'Can book classes and view the schedule',
    icon: Icons.person_outline,
    color: Color(0xFF0F766E),
  ),
  RoleDef(
    id: 'coach',
    label: 'Coach',
    description: 'Has a coach portal with class planning & check-in',
    icon: Icons.sports_outlined,
    color: Color(0xFF2563EB),
  ),
  RoleDef(
    id: 'staff',
    label: 'Staff',
    description: 'Access to admin panel and management tools',
    icon: Icons.badge_outlined,
    color: Color(0xFF7C3AED),
  ),
  RoleDef(
    id: 'admin',
    label: 'Admin',
    description: 'Full access — manages members, offers and settings',
    icon: Icons.admin_panel_settings_outlined,
    color: Color(0xFFDC2626),
  ),
];

// ── Role color helper ─────────────────────────────────────────────────────────

Color roleColor(String role) {
  switch (role) {
    case 'admin':
    case 'owner':
      return const Color(0xFFDC2626);
    case 'staff':
      return const Color(0xFF7C3AED);
    case 'coach':
      return const Color(0xFF2563EB);
    default:
      return const Color(0xFF0F766E);
  }
}

IconData roleIcon(String role) {
  switch (role) {
    case 'admin':
    case 'owner':
      return Icons.admin_panel_settings_outlined;
    case 'staff':
      return Icons.badge_outlined;
    case 'coach':
      return Icons.sports_outlined;
    default:
      return Icons.person_outline;
  }
}

// ── Role toggle card ──────────────────────────────────────────────────────────

class RoleToggleCard extends StatelessWidget {
  const RoleToggleCard({
    super.key,
    required this.role,
    required this.isSelected,
    required this.isLocked,
    required this.onToggle,
  });
  final RoleDef role;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? role.color.withValues(alpha: 0.08)
              : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? role.color.withValues(alpha: 0.5)
                : cs.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected
                    ? role.color.withValues(alpha: 0.15)
                    : cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(role.icon,
                  size: 20,
                  color: isSelected ? role.color : cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            // Label + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(role.label,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isSelected ? role.color : cs.onSurface)),
                      if (isLocked) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Always on',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(role.description,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? role.color : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? role.color : cs.outlineVariant,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Multi-role badge row ──────────────────────────────────────────────────────

class RoleBadgeRow extends StatelessWidget {
  const RoleBadgeRow({super.key, required this.roles});
  final List<String> roles;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: roles.map((r) => _RolePill(role: r)).toList(),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final color = roleColor(role);
    final icon = roleIcon(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            role[0].toUpperCase() + role.substring(1),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}
