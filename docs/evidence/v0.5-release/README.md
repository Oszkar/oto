# v0.5 hardware acceptance

Historical runs: 2026-06-02/03, SDK 0.5.2, Windows host, two controllable zones (Sonos Beam and Sonos One), plus a real Android device. These results establish v0.5 coverage, not acceptance of the current SDK or UI.

| Check | Recorded result | Coverage limit |
| --- | --- | --- |
| Operator regroup | Membership event at 14.7 seconds including operator delay; refresh returned two speakers in one group | No spurious membership events in the pre-regroup window; not a strict latency benchmark |
| Model enrichment | Beam and One model names populated after discovery and refresh | Two models on one LAN |
| Property-event regression | Five live tests passed, including double discovery without a hang | Operator and seed coverage, not exhaustive command combinations |
| Renewal | 28.5 minutes, 44 events, clean renewals near 1542 seconds, no disconnect/errors | One renewal cycle |
| Android release discovery | Release-mode APK found speakers with `WifiManager.MulticastLock` held | Temporary harness built under WSL; not distribution-signing validation |
| Sustained use | Accepted from renewal and active/regroup test coverage | No separate sustained active `event-tail` session was run |
| Lock contention | None observed in the live suite | Not a load benchmark |

## Captured excerpts

```text
operator_regroup_emits_topology_changed:
  discovered 2 speakers in 2 groups
  TopologyChanged #1 after 14.7208668s
  refresh_topology: 2 speakers in 1 group, members=2
subscribe_topology_then_speakers_activates_stream: ok

[discover] Living Room -> Some("Sonos Beam")
[discover] Kitchen -> Some("Sonos One")
[refresh] Kitchen -> Some("Sonos One")
[refresh] Living Room -> Some("Sonos Beam")

double_discover_does_not_hang: ok (7.1 s)
operator_play_pause_emits_per_group_event: ok (4.6 s)
operator_volume_change_emits_event: ok (6.9 s)
renewal_cycle_observation: ok (1713 s)
subscribe_then_seed_notifies_arrive: ok (seed Volume, 2/2 speakers)
```

The Android harness reported successful discovery on screen; its throwaway branch was not merged. Use the current app and [validation instructions](../../../AGENTS.md#6-validation-matrix) for new checks. [Sonos notes](../../sonos-notes.md) preserves the relevant protocol constraints.
