import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/friend_connection.dart';
import '../../services/friend_service.dart';
import '../../services/member_service.dart';
import '../../widgets/user_avatar.dart';

const _kTeal = Color(0xFF0F766E);

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.gymId});

  final String gymId;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late final FriendService _friendService;
  late final MemberService _memberService;
  late final TabController _tabController;

  late final Stream<List<FriendConnection>> _friendsStream;
  late final Stream<List<FriendConnection>> _requestsStream;

  final _searchController = TextEditingController();
  List<AppUser> _searchResults = [];
  bool _searching = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _friendService = FriendService(gymId: widget.gymId);
    _memberService = MemberService(gymId: widget.gymId);
    _tabController = TabController(length: 3, vsync: this);
    _friendsStream = _friendService.streamFriends(_myUid);
    _requestsStream = _friendService.streamPendingRequests(_myUid);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final all = await _memberService.streamMembers().first;
      final q = query.toLowerCase();
      setState(() {
        _searchResults = all
            .where((u) =>
                u.id != _myUid &&
                (u.displayName.toLowerCase().contains(q) ||
                    u.email.toLowerCase().contains(q)))
            .take(20)
            .toList();
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: _kTeal,
            title: Text(
              context.l10n.tr('Friends'),
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            iconTheme: IconThemeData(color: Colors.white),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: context.l10n.tr('Friends')),
                Tab(text: context.l10n.tr('Requests')),
                Tab(text: context.l10n.tr('Find')),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _FriendsTab(
              stream: _friendsStream,
              myUid: _myUid,
              friendService: _friendService,
              memberService: _memberService,
            ),
            _RequestsTab(
              stream: _requestsStream,
              myUid: _myUid,
              friendService: _friendService,
              memberService: _memberService,
            ),
            _FindTab(
              searchController: _searchController,
              searchResults: _searchResults,
              searching: _searching,
              myUid: _myUid,
              friendService: _friendService,
              gymId: widget.gymId,
              onSearch: _search,
              onSnack: _snack,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Friends tab ──────────────────────────────────────────────────────────────

class _FriendsTab extends StatelessWidget {
  const _FriendsTab({
    required this.stream,
    required this.myUid,
    required this.friendService,
    required this.memberService,
  });

  final Stream<List<FriendConnection>> stream;
  final String myUid;
  final FriendService friendService;
  final MemberService memberService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendConnection>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        final friends = snap.data ?? [];
        if (friends.isEmpty) {
          return _EmptyState(
            icon: Icons.group_outlined,
            message: context.l10n.tr('No friends yet. Find people in the Find tab.'),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.all(16),
          itemCount: friends.length,
          separatorBuilder: (_, __) => SizedBox(height: 8),
          itemBuilder: (context, i) {
            final friendId = friends[i].friendId(myUid);
            return _UserTile(
              userId: friendId,
              memberService: memberService,
              trailing: IconButton(
                icon: Icon(Icons.person_remove_outlined,
                    color: Colors.red.shade400, size: 20),
                tooltip: context.l10n.tr('Remove friend'),
                onPressed: () async {
                  await friendService.removeFriend(myUid, friendId);
                },
              ),
            );
          },
        );
      },
    );
  }
}

// ── Requests tab ─────────────────────────────────────────────────────────────

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({
    required this.stream,
    required this.myUid,
    required this.friendService,
    required this.memberService,
  });

  final Stream<List<FriendConnection>> stream;
  final String myUid;
  final FriendService friendService;
  final MemberService memberService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendConnection>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        final requests = snap.data ?? [];
        if (requests.isEmpty) {
          return _EmptyState(
            icon: Icons.inbox_outlined,
            message: context.l10n.tr('No pending requests.'),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, __) => SizedBox(height: 8),
          itemBuilder: (context, i) {
            final req = requests[i];
            return _UserTile(
              userId: req.requesterId,
              memberService: memberService,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon:
                        Icon(Icons.check_circle, color: _kTeal, size: 22),
                    tooltip: context.l10n.tr('Accept'),
                    onPressed: () => friendService.acceptRequest(req.id),
                  ),
                  IconButton(
                    icon: Icon(Icons.cancel_outlined,
                        color: Colors.red.shade400, size: 22),
                    tooltip: context.l10n.tr('Decline'),
                    onPressed: () => friendService.declineRequest(req.id),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Find tab ─────────────────────────────────────────────────────────────────

class _FindTab extends StatelessWidget {
  const _FindTab({
    required this.searchController,
    required this.searchResults,
    required this.searching,
    required this.myUid,
    required this.friendService,
    required this.gymId,
    required this.onSearch,
    required this.onSnack,
  });

  final TextEditingController searchController;
  final List<AppUser> searchResults;
  final bool searching;
  final String myUid;
  final FriendService friendService;
  final String gymId;
  final void Function(String) onSearch;
  final void Function(String) onSnack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: context.l10n.tr('Search by name or email…'),
              prefixIcon: Icon(Icons.search_outlined),
              suffixIcon: searching
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: onSearch,
          ),
        ),
        Expanded(
          child: searchResults.isEmpty
              ? Center(
                  child: Text(
                    searchController.text.length < 2
                        ? context.l10n.tr('Type at least 2 characters to search.')
                        : context.l10n.tr('No members found.'),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: searchResults.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final user = searchResults[i];
                    return _SearchResultTile(
                      user: user,
                      myUid: myUid,
                      friendService: friendService,
                      onSnack: onSnack,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Search result tile with dynamic connection state ─────────────────────────

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.user,
    required this.myUid,
    required this.friendService,
    required this.onSnack,
  });

  final AppUser user;
  final String myUid;
  final FriendService friendService;
  final void Function(String) onSnack;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FriendConnection?>(
      stream: friendService.streamConnection(myUid, user.id),
      builder: (context, snap) {
        final conn = snap.data;
        Widget trailing;

        if (conn == null) {
          trailing = OutlinedButton.icon(
            onPressed: () async {
              final msg = context.l10n.tr('Friend request sent!');
              await friendService.sendRequest(
                  requesterId: myUid, receiverId: user.id);
              onSnack(msg);
            },
            icon: Icon(Icons.person_add_outlined, size: 16),
            label: Text(context.l10n.tr('Add')),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kTeal,
              side: BorderSide(color: _kTeal),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          );
        } else if (conn.isPending && conn.requesterId == myUid) {
          trailing = Chip(
            label: Text(context.l10n.tr('Pending'),
                style: TextStyle(fontSize: 12)),
            backgroundColor:
                Colors.orange.withValues(alpha: 0.12),
          );
        } else if (conn.isPending && conn.receiverId == myUid) {
          trailing = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.check_circle, color: _kTeal, size: 20),
                onPressed: () => friendService.acceptRequest(conn.id),
                tooltip: context.l10n.tr('Accept'),
              ),
              IconButton(
                icon: Icon(Icons.cancel_outlined,
                    color: Colors.red.shade400, size: 20),
                onPressed: () => friendService.declineRequest(conn.id),
                tooltip: context.l10n.tr('Decline'),
              ),
            ],
          );
        } else {
          trailing = Chip(
            avatar: Icon(Icons.check, size: 14, color: _kTeal),
            label: Text(context.l10n.tr('Friends'),
                style:
                    TextStyle(fontSize: 12, color: _kTeal)),
            backgroundColor: _kTeal.withValues(alpha: 0.1),
          );
        }

        final initials = (user.displayName.isNotEmpty
                ? user.displayName[0]
                : user.email.isNotEmpty
                    ? user.email[0]
                    : '?')
            .toUpperCase();

        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: UserAvatar(
              photoUrl: user.photoUrl,
              initials: initials,
              color: _kTeal,
              radius: 20,
            ),
            title: Text(user.displayName.isNotEmpty
                ? user.displayName
                : user.email),
            subtitle: user.fitnessLevel.isNotEmpty
                ? Text(user.fitnessLevel)
                : null,
            trailing: trailing,
          ),
        );
      },
    );
  }
}

// ── Reusable user tile (loads user by ID) ────────────────────────────────────

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.userId,
    required this.memberService,
    required this.trailing,
  });

  final String userId;
  final MemberService memberService;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: memberService.streamUser(userId),
      builder: (context, snap) {
        final user = snap.data;
        final name = user?.displayName.isNotEmpty == true
            ? user!.displayName
            : user?.email ?? '…';
        final initials =
            name.isNotEmpty ? name[0].toUpperCase() : '?';

        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: UserAvatar(
              photoUrl: user?.photoUrl ?? '',
              initials: initials,
              color: _kTeal,
              radius: 20,
            ),
            title: Text(name),
            subtitle: user?.fitnessLevel.isNotEmpty == true
                ? Text(user!.fitnessLevel)
                : null,
            trailing: trailing,
          ),
        );
      },
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.outlineVariant),
            SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
