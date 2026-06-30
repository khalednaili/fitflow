import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/models/app_user.dart';
import 'package:fit_flow/utils/member_search.dart';

AppUser _user({
  String id = 'id',
  String name = '',
  String email = '',
}) =>
    AppUser(
      id: id,
      email: email,
      displayName: name,
      role: 'member',
      membershipPlanId: '',
      subscriptionStatus: '',
    );

void main() {
  group('filterMembers', () {
    final members = [
      _user(id: '1', name: 'Charlie Brown', email: 'charlie@example.com'),
      _user(id: '2', name: 'alice smith', email: 'alice@example.com'),
      _user(id: '3', name: 'Bob Jones', email: 'bob@gym.tn'),
      _user(id: '4', name: '', email: 'zoe@example.com'),
    ];

    test('empty query returns everyone, sorted by name (email fallback)', () {
      final r = filterMembers(members, '');
      expect(r.map((m) => m.id).toList(), ['2', '3', '1', '4']);
      // alice, Bob, Charlie, then zoe@ (name empty → email used)
    });

    test('matches by display name, case-insensitively', () {
      final r = filterMembers(members, 'ALICE');
      expect(r.map((m) => m.id).toList(), ['2']);
    });

    test('matches by email', () {
      final r = filterMembers(members, 'gym.tn');
      expect(r.map((m) => m.id).toList(), ['3']);
    });

    test('matches a member whose name is empty via its email', () {
      final r = filterMembers(members, 'zoe');
      expect(r.map((m) => m.id).toList(), ['4']);
    });

    test('returns empty when nothing matches', () {
      expect(filterMembers(members, 'nobody'), isEmpty);
    });

    test('trims and ignores surrounding whitespace in the query', () {
      expect(filterMembers(members, '  bob  ').map((m) => m.id), ['3']);
    });

    test('returns a growable, sortable list (guards the unmodifiable bug)', () {
      // MemberService returns an unmodifiable list; filterMembers must hand back
      // a fresh growable copy so callers can sort without throwing.
      final r = filterMembers(List<AppUser>.unmodifiable(members), '');
      expect(() => r.sort((a, b) => a.id.compareTo(b.id)), returnsNormally);
    });
  });

  group('memberInitials', () {
    test('uses first letters of first two name parts', () {
      expect(memberInitials(_user(name: 'Charlie Brown')), 'CB');
    });

    test('uppercases and uses two letters for a single name', () {
      expect(memberInitials(_user(name: 'alice')), 'AL');
    });

    test('falls back to email when name is empty', () {
      expect(memberInitials(_user(name: '', email: 'zoe@example.com')), 'ZO');
    });

    test('handles a single-character source', () {
      expect(memberInitials(_user(name: 'x')), 'X');
    });
  });
}
