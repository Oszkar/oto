import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/breakpoints.dart';
import '../../state/home_view_state.dart';
import '../../state/model/group_state.dart';
import '../../state/model/household.dart';
import '../../state/prefs.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../now_playing/now_playing_pane.dart';
import '../shell/nav.dart';
import '../shell/oto_scaffold.dart';
import 'bottom_strip.dart';
import 'group_card.dart';
import 'home_header.dart';
import 'home_states.dart';
import 'room_card.dart';
import 'room_row.dart';

/// The assembled Home screen: HomeHeader on top, the group/solo body in the
/// selected layout, and the floating BottomStrip pinned over the bottom.
///
/// Composition rule (spec §6): EVERY room belongs to a group, so we iterate
/// `household.groups`. A multi-member group renders ONE merged [GroupCard];
/// a single-member group renders a [RoomCard] (Cards layout) / [RoomRow]
/// (Stack layout) for its sole member. A grouped room thus appears ONLY inside
/// its group card -- never also as a standalone card.
///
/// In Cards layout, solo room cards pack 2-up while group cards span full
/// width; in Stack layout everything is a single column. The body scrolls; the
/// strip floats over it via a [Stack] so it stays reachable at the bottom.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeViewStateProvider);
    return switch (state) {
      HomeInitialLoading() => const OtoScaffold(body: HomeLoadingState()),
      HomeEmpty() => const OtoScaffold(body: HomeEmptyState()),
      HomeDiscoveryFailedNoCache(:final error) => OtoScaffold(
        body: HomeErrorState(error: error),
      ),
      HomeDiscoveringWithCache(:final household) => OtoScaffold(
        detail: const NowPlayingPane(),
        body: _HomeContent(
          household: household,
          banner: HomeStatusBanner(
            message: 'Scanning again. Showing cached state.',
            showRetry: false,
          ),
        ),
      ),
      HomeDiscoveryFailedWithCache(:final household) => OtoScaffold(
        detail: const NowPlayingPane(),
        body: _HomeContent(
          household: household,
          banner: const HomeStatusBanner(
            message: 'Refresh failed. Showing cached state.',
          ),
        ),
      ),
      HomeReady(:final household) => OtoScaffold(
        detail: const NowPlayingPane(),
        body: _HomeContent(household: household),
      ),
    };
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.household, this.banner});

  final Household household;
  final Widget? banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(settingsProvider.select((s) => s.layout));
    final groups = _sortedGroups(household);
    final hasActiveStream = groups.any((g) => g.hasActiveStream);
    // On wide the persistent detail pane replaces the floating strip; only the
    // phone layout keeps the strip (and reserves bottom room for it).
    final wide = context.isWide;

    return Stack(
      children: [
        // Header + scrollable body fill the scaffold; the strip floats over
        // the bottom (Positioned below).
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomeHeader(),
            ?banner,
            Expanded(
              child: SingleChildScrollView(
                // Bottom padding leaves room for the floating strip so the
                // last card never hides behind it (phone only).
                padding: EdgeInsets.fromLTRB(
                  Space.gutter12,
                  0,
                  Space.gutter12,
                  (!wide && hasActiveStream) ? 96 : Space.gutter12,
                ),
                child: layout == HomeLayout.cards
                    ? _CardsBody(groups: groups)
                    : _StackBody(groups: groups),
              ),
            ),
          ],
        ),
        if (!wide && hasActiveStream)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BottomStrip(
              onTapSource: (s) => openSource(context, ref, s.id),
            ),
          ),
      ],
    );
  }
}

/// Groups in a stable, deterministic order: by coordinator id then group id, so
/// the body never reshuffles on an unrelated state tick. (Coordinator name is
/// not used here to keep this independent of `rooms`; ids are stable.)
List<GroupState> _sortedGroups(Household h) {
  final groups = h.groups.values.toList();
  groups.sort((a, b) {
    final byCoord = a.coordinatorId.compareTo(b.coordinatorId);
    return byCoord != 0 ? byCoord : a.id.compareTo(b.id);
  });
  return groups;
}

/// Cards layout body: a single column where multi-member groups span full
/// width and consecutive solo rooms pack two-per-row. Walks the ordered groups
/// once, flushing the pending solo row before each full-width group card.
class _CardsBody extends StatelessWidget {
  const _CardsBody({required this.groups});

  final List<GroupState> groups;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    // Solo room ids awaiting placement into a 2-up row.
    final pendingSolos = <String>[];

    void flushSolos() {
      for (var i = 0; i < pendingSolos.length; i += 2) {
        final left = pendingSolos[i];
        final right = (i + 1 < pendingSolos.length)
            ? pendingSolos[i + 1]
            : null;
        children.add(_soloRow(left, right));
      }
      pendingSolos.clear();
    }

    for (final g in groups) {
      if (g.memberIds.length > 1) {
        // A group card breaks the solo flow: flush, then span full width.
        flushSolos();
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: Space.gutter12),
            child: GroupCard(groupId: g.id),
          ),
        );
      } else {
        pendingSolos.add(g.memberIds.single);
      }
    }
    flushSolos();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// One 2-up row of solo room cards; the right slot is an empty spacer when an
  /// odd count leaves the row half-full, so a lone card keeps its half-width.
  Widget _soloRow(String left, String? right) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.gutter12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: RoomCard(speakerId: left)),
          const SizedBox(width: Space.gutter12),
          Expanded(
            child: right == null
                ? const SizedBox.shrink()
                : RoomCard(speakerId: right),
          ),
        ],
      ),
    );
  }
}

/// Stack layout body: a single column of solo [RoomRow]s and full-width
/// [GroupCard]s, in the ordered-group sequence.
class _StackBody extends StatelessWidget {
  const _StackBody({required this.groups});

  final List<GroupState> groups;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    final children = <Widget>[];
    for (final g in groups) {
      if (g.memberIds.length > 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: Space.gutter12),
            child: GroupCard(groupId: g.id),
          ),
        );
      } else {
        children.add(RoomRow(speakerId: g.memberIds.single));
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: Space.gutter12),
      decoration: BoxDecoration(
        color: oto.surface,
        border: Border.all(color: oto.line),
        borderRadius: BorderRadius.circular(Radius_.card16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
