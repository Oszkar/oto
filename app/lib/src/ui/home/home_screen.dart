import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../shell/oto_nav_rail.dart';
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
        rail: const OtoNavRail(),
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
        rail: const OtoNavRail(),
        body: _HomeContent(
          household: household,
          banner: const HomeStatusBanner(
            message: 'Refresh failed. Showing cached state.',
          ),
        ),
      ),
      // Cached rooms, none of them answering. Renders the normal Home content
      // (the last known state is still the most useful thing to show) plus the
      // retry banner - HomeStatusBanner defaults to showRetry, whose button
      // runs a full rediscover, which is the path that clears stale health.
      HomeAllUnreachable(:final household) => OtoScaffold(
        detail: const NowPlayingPane(),
        rail: const OtoNavRail(),
        body: _HomeContent(
          household: household,
          banner: const HomeStatusBanner(
            message: 'No speakers are responding. Showing the last known state.',
          ),
        ),
      ),
      // A partial outage (some, not all, rooms unreachable) doesn't qualify
      // for HomeAllUnreachable, but still needs a way out - see room_card.dart
      // for the per-room recovery path this banner's retry complements (#104).
      HomeReady(:final household) => OtoScaffold(
        detail: const NowPlayingPane(),
        rail: const OtoNavRail(),
        body: _HomeContent(
          household: household,
          banner: household.rooms.values.any((r) => !r.online)
              ? const HomeStatusBanner(message: "Some rooms aren't responding.")
              : null,
        ),
      ),
    };
  }
}

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent({required this.household, this.banner});

  final Household household;
  final Widget? banner;

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

/// First-frame estimate for [_HomeContentState._stripInset], before the strip
/// has been laid out. Sized for the common single-source strip; anything taller
/// corrects on the next frame.
const double _stripInsetEstimate = 96;

class _HomeContentState extends ConsumerState<_HomeContent> {
  // Own controller so this scrollable never contends with another primary
  // scrollable (e.g. the wide NowPlayingPane) for the app-wide
  // PrimaryScrollController - see responsive_pop.dart's sibling fix.
  final _scrollController = ScrollController();

  /// Bottom room reserved in the scroll view for the floating strip.
  ///
  /// Measured, not assumed. The strip renders ONE row per active source,
  /// uncapped (`bottom_strip.dart`), so its height grows with the household:
  /// a fixed reserve was right for one source and left the last card roughly
  /// 50 px covered at full scroll with two. Deriving `rowHeight * n` from a
  /// constant instead would go stale the moment a row gains a line, and fail
  /// silently again.
  double _stripInset = _stripInsetEstimate;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onStripHeight(double height) {
    // Clear the strip by its real height plus the gutter the body uses
    // everywhere else, so the last card never kisses it.
    final inset = height + Space.gutter12;
    if (!mounted || inset == _stripInset) return;
    setState(() => _stripInset = inset);
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(currentHomeLayoutProvider);
    final groups = _sortedGroups(widget.household);
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
            ?widget.banner,
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  // Bottom padding leaves room for the floating strip so the
                  // last card never hides behind it (phone only). Driven by
                  // the strip's measured height - see [_stripInset].
                  padding: EdgeInsets.fromLTRB(
                    Space.gutter12,
                    0,
                    Space.gutter12,
                    (!wide && hasActiveStream) ? _stripInset : Space.gutter12,
                  ),
                  child: layout == HomeLayout.cards
                      ? _CardsBody(groups: groups)
                      : _StackBody(groups: groups),
                ),
              ),
            ),
          ],
        ),
        if (!wide && hasActiveStream)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _MeasureHeight(
              onChange: _onStripHeight,
              child: BottomStrip(
                onTapSource: (s) => openSource(context, ref, s.id),
              ),
            ),
          ),
      ],
    );
  }
}

/// Reports its child's laid-out height to [onChange] whenever that height
/// changes. Used to size the scroll view's bottom reserve off the floating
/// strip's real height rather than a guess.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onChange, required Widget super.child});

  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureHeightBox(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _MeasureHeightBox renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureHeightBox extends RenderProxyBox {
  _MeasureHeightBox(this.onChange);

  ValueChanged<double> onChange;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size.height) return;
    _reported = size.height;
    // Reporting synchronously would run a `setState` in the middle of layout,
    // which Flutter forbids. Defer to after this frame; the reserve is one
    // frame stale on a source-count change, which is invisible unless you are
    // already pinned to the very bottom of the list at that instant.
    final height = size.height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(height));
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
          Expanded(
            child: RoomCard(key: ValueKey(left), speakerId: left),
          ),
          const SizedBox(width: Space.gutter12),
          Expanded(
            child: right == null
                ? const SizedBox.shrink()
                : RoomCard(key: ValueKey(right), speakerId: right),
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
        children.add(
          RoomRow(
            key: ValueKey(g.memberIds.single),
            speakerId: g.memberIds.single,
          ),
        );
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
