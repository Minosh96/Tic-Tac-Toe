import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_avatar.dart';
import '../../core/widgets/notification_bell_button.dart';

/// Melow v3.8 Global & Friends Verified Leaderboards with direct "Add Friend"
/// action on Global Top 100 users (respecting each player's privacy setting).
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key, required this.services});

  final AppServices services;

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  String _scope = 'global';
  LeaderboardMetric _metric = LeaderboardMetric.wins;

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<LeaderboardEntry> _entries = const [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = false;
  final Set<String> _sentRequestUids = <String>{};

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _entries = const [];
      _lastDoc = null;
      _hasMore = false;
    });

    try {
      if (_scope == 'global') {
        final page = await widget.services.leaderboard.fetchGlobalPage(
          metric: _metric,
        );
        if (!mounted) return;
        setState(() {
          _entries = page.entries;
          _lastDoc = page.lastDocument;
          _hasMore = page.hasMore;
        });
      } else {
        final uid = widget.services.game.currentUid;
        final friends = await widget.services.friends.watchFriends(uid).first;
        final list = await widget.services.leaderboard.fetchFriendsLeaderboard(
          currentUid: uid,
          friendUids: friends.map((f) => f.friendUid).toList(growable: false),
          metric: _metric,
        );
        if (!mounted) return;
        setState(() {
          _entries = list;
          _hasMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load rankings right now. Pull to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _lastDoc == null || _scope != 'global') {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await widget.services.leaderboard.fetchGlobalPage(
        metric: _metric,
        startAfter: _lastDoc,
      );
      if (!mounted) return;
      setState(() {
        _entries = LeaderboardRepository.sortDeterministically(
          [..._entries, ...page.entries],
          _metric,
        );
        _lastDoc = page.lastDocument;
        _hasMore = page.hasMore;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _sendFriendRequestToGlobalUser(
    UserProfile me,
    LeaderboardEntry entry,
  ) async {
    try {
      await widget.services.friends.sendFriendRequestToLeaderboardEntry(
        me: me,
        entry: entry,
      );
      if (mounted) {
        setState(() => _sentRequestUids.add(entry.uid));
      }
      _snack('Friend request sent to ${entry.publicNickname}!');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _cancelFriendRequestToGlobalUser(
    LeaderboardEntry entry,
  ) async {
    try {
      await widget.services.friends
          .cancelOutgoingFriendRequestToUser(entry.uid);
      if (mounted) {
        setState(() => _sentRequestUids.remove(entry.uid));
      }
      _snack('Cancelled friend request to ${entry.publicNickname}.');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _medal(int rank) {
    if (rank == 1) return '🥇';
    if (rank == 2) return '🥈';
    if (rank == 3) return '🥉';
    return '#$rank';
  }

  @override
  Widget build(BuildContext context) {
    final myUid = widget.services.game.currentUid;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<UserProfile?>(
      stream: widget.services.profile.watchProfile(myUid),
      builder: (context, meSnap) {
        final me = meSnap.data;
        return StreamBuilder<List<FriendEntry>>(
          stream: widget.services.friends.watchFriends(myUid),
          builder: (context, friendsSnap) {
            final friendUidSet = {
              for (final f in (friendsSnap.data ?? const <FriendEntry>[]))
                f.friendUid,
            };
            return StreamBuilder<List<FriendRequest>>(
              stream: widget.services.friends.watchOutgoingRequests(myUid),
              builder: (context, outReqSnap) {
                final pendingOutSet = {
                  ..._sentRequestUids,
                  for (final r
                      in (outReqSnap.data ?? const <FriendRequest>[]))
                    r.receiverUid,
                };
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Leaderboards'),
                    actions: [
                      NotificationBellIconButton(
                        services: widget.services,
                        me: me,
                      ),
                      IconButton(
                        tooltip: 'Refresh rankings',
                        onPressed: _loadInitial,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  body: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 580),
                        child: RefreshIndicator(
                          onRefresh: _loadInitial,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                      value: 'global',
                                      icon:
                                          Icon(Icons.public_rounded, size: 18),
                                      label: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text('Global Top 100'),
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'friends',
                                      icon:
                                          Icon(Icons.groups_rounded, size: 18),
                                      label: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text('Friends'),
                                      ),
                                    ),
                                  ],
                                  selected: {_scope},
                                  onSelectionChanged: (v) {
                                    setState(() => _scope = v.first);
                                    _loadInitial();
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final m in LeaderboardMetric.values)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: ChoiceChip(
                                          label: Text(m.label),
                                          selected: _metric == m,
                                          onSelected: (_) {
                                            setState(() => _metric = m);
                                            _loadInitial();
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_loading)
                                const Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                )
                              else if (_error != null)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      children: [
                                        const Icon(Icons.cloud_off_rounded,
                                            size: 42),
                                        const SizedBox(height: 8),
                                        Text(_error!,
                                            textAlign: TextAlign.center),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                          onPressed: _loadInitial,
                                          child: const Text('Retry'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else if (_entries.isEmpty)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(28),
                                    child: Column(
                                      children: [
                                        const Text('🏆',
                                            style: TextStyle(fontSize: 44)),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'No verified rankings yet',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Finish multiplayer tournaments to climb the ${_scope == 'global' ? 'Global' : 'Friends'} Leaderboard!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else ...[
                                for (var i = 0; i < _entries.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _LeaderboardRow(
                                      rankLabel: _medal(i + 1),
                                      entry: _entries[i],
                                      metric: _metric,
                                      isMe: _entries[i].uid == myUid,
                                      isFriend: friendUidSet
                                          .contains(_entries[i].uid),
                                      isRequestPending: pendingOutSet
                                          .contains(_entries[i].uid),
                                      showAddFriendControl: _scope == 'global',
                                      onAddFriend: (me == null ||
                                              _entries[i].uid == myUid ||
                                              !_entries[i].allowFriendRequests)
                                          ? null
                                          : () =>
                                              _sendFriendRequestToGlobalUser(
                                                me,
                                                _entries[i],
                                              ),
                                      onCancelRequest: () =>
                                          _cancelFriendRequestToGlobalUser(
                                        _entries[i],
                                      ),
                                    ),
                                  ),
                                if (_hasMore)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: OutlinedButton(
                                      onPressed:
                                          _loadingMore ? null : _loadMore,
                                      child: Text(
                                        _loadingMore
                                            ? 'Loading more…'
                                            : 'Load More',
                                      ),
                                    ),
                                  ),
                              ],
                              const MelowFooter(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rankLabel,
    required this.entry,
    required this.metric,
    required this.isMe,
    required this.isFriend,
    required this.isRequestPending,
    required this.showAddFriendControl,
    this.onAddFriend,
    this.onCancelRequest,
  });

  final String rankLabel;
  final LeaderboardEntry entry;
  final LeaderboardMetric metric;
  final bool isMe;
  final bool isFriend;
  final bool isRequestPending;
  final bool showAddFriendControl;
  final VoidCallback? onAddFriend;
  final VoidCallback? onCancelRequest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: isMe ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Center(
                child: Text(
                  rankLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            MelowAvatar(
              avatarId: entry.avatarId,
              photoBase64: entry.photoBase64,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isMe ? '${entry.publicNickname} (You)' : entry.publicNickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.goldAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${entry.scoreFor(metric)} ${metric.label}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            if (showAddFriendControl && !isMe) ...[
              const SizedBox(width: 6),
              if (isFriend)
                Tooltip(
                  message: 'Already Friends',
                  child: Icon(
                    Icons.people_alt_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                )
              else if (isRequestPending)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  onPressed: onCancelRequest,
                  icon: const Icon(Icons.close_rounded, size: 15),
                  label: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else if (entry.allowFriendRequests)
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Add Friend (${entry.publicNickname})',
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  onPressed: onAddFriend,
                )
              else
                Tooltip(
                  message:
                      '${entry.publicNickname} disabled global friend requests',
                  child: Icon(
                    Icons.person_off_outlined,
                    size: 18,
                    color: scheme.outline,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
