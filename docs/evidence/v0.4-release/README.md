# v0.4 hardware acceptance

Historical run: 2026-05-26, Windows 11, two responsive Sonos players, SDK 0.5.2. Starting revision: [`commit.txt`](commit.txt). These results do not validate the current SDK or later UI.

## Evidence and coverage

| Artifact | Coverage |
| --- | --- |
| [Live tests](01-live-tests.log) | Four live tests passed: seeds, topology, and operator event routing |
| [Idle session](02-idle-30min.log) | 31.6 minutes; subscription renewal near 24.6 minutes; no spurious events after warmup |
| [Active session](03-active-30min.log) | 34.6 minutes; track metadata, multi-speaker volume, play/pause, regroup, and renewal while playing |
| [Network interruption](04-wifi-drop.log) | Recovery after a short host-network outage and after fresh discovery |

The run was accepted for v0.4 with Android validation deferred. The later [Android smoke](../v0.5-android-debug.md) and [v0.5 release record](../v0.5-release/README.md) cover that gap.

## Limits useful for future tests

- Operator reaction time was included in measured latency; this was not a strict sub-second command-to-event benchmark.
- Mute delivery was covered by seeds and automated tests, not an operator mute toggle. Natural track advance is not proof of every skip command.
- The outage lasted roughly 20-30 seconds; it does not establish recovery after subscription expiry or guarantee replay of missed state.
- Regrouped IDs became stale until a new discovery, as expected for v0.4. Later releases added automatic topology refresh.
- Missing initial notifications on repeated subscriptions required partial-state handling. Seed tests must not require every speaker to seed immediately.
- The original notes disagree with later records about speaker model labels at the same IPs. Treat the logs as evidence of IDs and routing, not reliable model-identification evidence.

Old OpenSSL/Perl build troubleshooting and temporary harness instructions are omitted because the TLS workaround is [retired](../../../LOCAL_PATCHES.md#2-retired-sonos-sdk-tls-fork).
