import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../../../domain/models/social_models.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_avatar.dart';

/// Phase 12 Global & Friends Verified Leaderboards with pagination & tie-breaking.
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key, required this.services});

  final AppServices services;

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  String _scope = 'global'; // global | friends
  LeaderboardMetric _metric = LeaderboardMetric.wins;

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<LeaderboardEntry> _entries = const [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
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
        final friends =
            await widget.services.friends.watchFriends(uid).first;
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
    } catch (e) {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboards'),
        actions: [
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
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'global',
                        icon: Icon(Icons.public_rounded),
                        label: Text('Global'),
                      ),
                      ButtonSegment(
                        value: 'friends',
                        icon: Icon(Icons.groups_rounded),
                        label: Text('Friends'),
                      ),
                    ],
                    selected: {_scope},
                    onSelectionChanged: (v) {
                      setState(() => _scope = v.first);
                      _loadInitial();
                    },
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final m in LeaderboardMetric.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
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
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(Icons.cloud_off_rounded, size: 42),
                            const SizedBox(height: 8),
                            Text(_error!, textAlign: TextAlign.center),
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
                            const Text('🏆', style: TextStyle(fontSize: 44)),
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
                              'Finish multiplayer tournaments to climb the verified ${_scope == 'global' ? 'Global' : 'Friends'} Leaderboard!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant),
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
                        ),
                      ),
                    if (_hasMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: OutlinedButton(
                          onPressed: _loadingMore ? null : _loadMore,
                          child: Text(
                            _loadingMore ? 'Loading more…' : 'Load More',
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
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rankLabel,
    required this.entry,
    required this.metric,
    required this.isMe,
  });

  final String rankLabel;
  final LeaderboardEntry entry;
  final LeaderboardMetric metric;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: isMe ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
      child: ListTile(
        leading: SizedBox(
          width: 42,
          child: Center(
            child: Text(
              rankLabel,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        title: Row(
          children: [
            MelowAvatar(avatarId: entry.avatarId, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isMe ? '${entry.publicNickname} (You)' : entry.publicNickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.goldAccent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '${entry.scoreFor(metric)} ${metric.label}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
