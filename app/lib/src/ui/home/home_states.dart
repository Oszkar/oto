import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/discovery.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../shell/nav.dart';
import '../widgets/oto_icon.dart';
import '../widgets/oto_mark.dart';

class HomeLoadingState extends StatelessWidget {
  const HomeLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CenteredHomeState(
      icon: _StateIcon(child: OtoMark(42)),
      title: 'Scanning your network',
      body: 'Looking for Sonos speakers on this local network.',
    );
  }
}

class HomeEmptyState extends ConsumerWidget {
  const HomeEmptyState({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CenteredHomeState(
      icon: _StateIcon(name: 'speakers'),
      title: 'No speakers yet',
      body:
          'Make sure your Sonos system is on the same Wi-Fi network, then scan again.',
      action: FilledButton.icon(
        onPressed: () =>
            unawaited(ref.read(discoveryProvider.notifier).rediscover()),
        icon: const OtoIcon('search', size: 16),
        label: const Text('Scan network'),
      ),
    );
  }
}

class HomeErrorState extends ConsumerWidget {
  const HomeErrorState({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CenteredHomeState(
      icon: _StateIcon(name: 'wifiOff'),
      title: 'Could not find your system',
      body:
          'Check that your phone or computer is on the same local network as your Sonos system, and that multicast discovery is allowed.',
      action: FilledButton.icon(
        onPressed: () =>
            unawaited(ref.read(discoveryProvider.notifier).rediscover()),
        icon: const OtoIcon('search', size: 16),
        label: const Text('Scan network'),
      ),
    );
  }
}

class HomeStatusBanner extends ConsumerWidget {
  const HomeStatusBanner({
    super.key,
    required this.message,
    this.showRetry = true,
  });

  final String message;
  final bool showRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter12,
        0,
        Space.gutter12,
        Space.gutter12,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter12,
          vertical: Space.lg10,
        ),
        decoration: BoxDecoration(
          color: oto.fillStrong,
          border: Border.all(color: oto.line),
          borderRadius: BorderRadius.circular(Radius_.input9),
        ),
        child: Row(
          children: [
            OtoIcon('wifiOff', size: 16, color: oto.ink2),
            const SizedBox(width: Space.md8),
            Expanded(
              child: Text(
                message,
                style: TextStyles.bodySm.copyWith(color: oto.ink2),
              ),
            ),
            if (showRetry) ...[
              const SizedBox(width: Space.md8),
              TextButton.icon(
                onPressed: () => unawaited(
                  ref.read(discoveryProvider.notifier).rediscover(),
                ),
                icon: const OtoIcon('search', size: 14),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CenteredHomeState extends StatelessWidget {
  const _CenteredHomeState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final Widget icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.screen18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(height: Space.section22),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyles.titleSection.copyWith(color: oto.ink),
                  ),
                  const SizedBox(height: Space.md8),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyles.bodySm.copyWith(color: oto.inkMute),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: Space.section22),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
        // Before v0.6.4, none of these no-cache states built HomeHeader (the
        // gear's only other home) - so a user whose first scan failed had no
        // way to reach Settings at all (#104).
        const Positioned(
          top: Space.screen18,
          right: Space.screen18,
          child: _SettingsGear(),
        ),
      ],
    );
  }
}

class _SettingsGear extends StatelessWidget {
  const _SettingsGear();

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Tooltip(
      message: 'Open settings',
      child: Semantics(
        label: 'Open settings',
        button: true,
        child: InkWell(
          key: const Key('centered-state-settings'),
          onTap: () => openSettings(context),
          borderRadius: BorderRadius.circular(Radius_.art10),
          child: Container(
            width: Sizes.touchTarget44,
            height: Sizes.touchTarget44,
            decoration: BoxDecoration(
              border: Border.all(color: oto.line),
              borderRadius: BorderRadius.circular(Radius_.art10),
            ),
            alignment: Alignment.center,
            child: OtoIcon('settings', size: 17, color: oto.ink2),
          ),
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({this.name, this.child})
    : assert(name != null || child != null);

  final String? name;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: oto.fillStrong,
        borderRadius: BorderRadius.circular(Radius_.card16),
      ),
      alignment: Alignment.center,
      child: child ?? OtoIcon(name!, size: 42, color: oto.ink2),
    );
  }
}
