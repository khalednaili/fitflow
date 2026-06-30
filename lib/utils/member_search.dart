import '../models/app_user.dart';

/// Filters [members] by [query], matching against display name or email
/// (case-insensitive, trimmed). An empty query returns everyone.
///
/// Always returns a NEW growable list sorted by display name (falling back to
/// email) — never the unmodifiable list returned by `MemberService`, so callers
/// can sort/mutate the result safely.
List<AppUser> filterMembers(List<AppUser> members, String query) {
  final q = query.trim().toLowerCase();
  final result = members.where((m) {
    if (q.isEmpty) return true;
    return m.displayName.toLowerCase().contains(q) ||
        m.email.toLowerCase().contains(q);
  }).toList();
  result.sort((a, b) {
    final an = a.displayName.trim().isEmpty ? a.email : a.displayName;
    final bn = b.displayName.trim().isEmpty ? b.email : b.displayName;
    return an.toLowerCase().compareTo(bn.toLowerCase());
  });
  return result;
}

/// Two-letter initials for an avatar, derived from display name (or email).
String memberInitials(AppUser m) {
  final source = m.displayName.trim().isNotEmpty ? m.displayName.trim() : m.email;
  if (source.isEmpty) return '?';
  final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length == 1 ? p : p.substring(0, 2)).toUpperCase();
  }
  return (parts.first[0] + parts[1][0]).toUpperCase();
}
