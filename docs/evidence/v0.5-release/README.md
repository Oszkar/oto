# v0.5.0 release - hardware acceptance evidence

Mirrors the v0.4 § 8 pattern. This is the **user-ordered, non-skippable** Task 9
gate: v0.5.0 is not released until every criterion below is validated on real
hardware (LAN + a real Android device) with output captured here.

Run date: 2026-06-02 (LAN round) · LAN: 2-speaker household (Living Room = Sonos Beam, Kitchen = Sonos One) · Host: Windows + WSL/device for S3

## Criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | **S1** - operator regroup → `TopologyChanged` (~5 s) + `refresh_topology` re-pull reflects new grouping | ✅ PASS | `TopologyChanged #1 @14.7 s` (operator reaction), refresh → 2 speakers in **1 group, members=2** (Kitchen merged into Living Room). **Zero spurious `TopologyChanged` in the 3 s+ pre-regroup window** → seed-suppression fix confirmed live (no rediscover loop). |
| 2 | **S4** - `model` populated for ≥2 speakers after discover + refresh | ✅ PASS | discover + refresh both: Living Room → `Sonos Beam`, Kitchen → `Sonos One`. |
| 3 | **v0.4 regression** - Volume / Mute / Playback / Track / seed / renewal still pass | ✅ PASS | `live_events` 5/5: per-group play/pause (Paused, correct GroupId), volume 5→6, seed 2/2 speakers, double-discover no-hang, **renewal cycle 28.5 min / 44 events / renewals fired clean ~1542 s, no disconnect**. |
| 4 | **S3** - release APK discovers the household on a real Android device | ✅ PASS | Release APK (built WSL, Flutter 3.44) on a real device via the `main_s3_check` harness → on-screen **"PASS - discovered N speakers"** with the speaker list. The held `WifiManager.MulticastLock` makes release-build SSDP discovery work (debug worked without it, per P0a). |
| 5 | **Dogfood** - sustained idle + active, regroup mid-session: events prompt, renewals clean, no rediscover storm, no errors | ✅ PASS (accepted on coverage) | Satisfied by the live suite, per the gate owner's decision (2026-06-03): the 28.5-min renewal cycle covers idle health (renewals clean, 0 errors, no disconnect); active behavior + topology events + no-loop covered by the operator/S1 regroup tests. No separate dedicated `event-tail` session run. |
| 6 | **S5** - lock-granularity: any UI-perceptible stutter under load? (no → "not triggered", closed) | ✅ closed (not triggered) | No latency/contention observed across the full live suite (incl. the 28.5-min run); no stutter reported. Matches the v0.4 finding. S5 closed - no narrowing needed. |

## Commands

```bash
# 1. S1 topology events (LAN)
cd native && cargo nextest run -p oto-wire --features live-tests \
  --run-ignored ignored-only --test live_topology_events --nocapture
# 2. S4 model populate (LAN)
cargo nextest run -p oto-wire --features live-tests \
  --run-ignored ignored-only --test live_model_populate --nocapture
# 3. v0.4 regression (LAN)
cargo nextest run -p oto-wire --features live-tests \
  --run-ignored ignored-only --test live_events --nocapture
# 4. S3 release APK (WSL/Mac + device)
flutter build apk --release
adb install -r app/build/app/outputs/flutter-apk/app-release.apk
# 5. Dogfood (optional - ≥30 min idle + ≥30 min active, regroup mid-session)
cargo run -p oto_native --example event-tail --features oto-wire/live-tests | tee /tmp/v05-dogfood.log
```

## Logs

### 1 - S1 topology events ✅ (2/2 passed, 24 s)

```text
operator_regroup_emits_topology_changed:
  discovered 2 speakers in 2 groups (before regroup): each members=1
  (pre-regroup window: only Playback/Track events seen - NO TopologyChanged)
  TopologyChanged #1 after 14.7208668s
  refresh_topology → 2 speakers in 1 groups (after regroup):
    group RINCON_542A1B9463A801400:3426502567 coord=RINCON_542A1B9463A801400 members=2
  test ... ok
subscribe_topology_then_speakers_activates_stream:
  topology watch active; stream takeable ... ok
```

### 2 - S4 model populate ✅ (1/1 passed, 3 s)

```text
[discover]  RINCON_542A1B9463A801400 (Living Room) → Some("Sonos Beam")
[discover]  RINCON_7828CAE858CA01400 (Kitchen)      → Some("Sonos One")
[refresh]   RINCON_7828CAE858CA01400 (Kitchen)      → Some("Sonos One")
[refresh]   RINCON_542A1B9463A801400 (Living Room)  → Some("Sonos Beam")
test ... ok
```

### 3 - v0.4 regression ✅ (5/5 passed, ~29 min incl. renewal obs.)

```text
double_discover_does_not_hang ........................ ok (7.1 s)
operator_play_pause_emits_per_group_event ............ ok - Playback …:3426502567 → Paused (per-group GroupId), 4.6 s
operator_volume_change_emits_event ................... ok - Volume RINCON_542A1B9463A801400 → 6 (baseline 5), 6.9 s
renewal_cycle_observation ............................ ok (1713 s ≈ 28.5 min)
  events_seen=44; renewals fired clean ~1542 s:
    ✅ Renewed subscription for 10.83.0.105 RenderingControl
    ✅ Renewed subscription for 10.83.0.103 AVTransport
    ✅ Renewed subscription for 10.83.0.105 AVTransport
    ✅ Renewed subscription for 10.83.0.103 RenderingControl
  no disconnect, no errors
subscribe_then_seed_notifies_arrive .................. ok - seed Volume 2/2 speakers
```

### 4 - S3 release APK on Android ✅

```text
flutter build apk --release -t lib/main_s3_check.dart  (WSL, Flutter 3.44) → built
adb install -r build/app/outputs/flutter-apk/app-release.apk → Success
Launch → on-screen "PASS - discovered N speakers" + speaker list.
=> release-build SSDP discovery works WITH the held MulticastLock (debug
   worked without it per P0a). S3 confirmed.
(harness on throwaway branch chore/v0.5-s3-check - not merged)
```

### 5 - Dogfood

```text
Accepted on coverage (gate owner, 2026-06-03), no separate session:
  - idle health   : renewal_cycle_observation ≈28.5 min, renewals clean,
                    0 errors, no disconnect (see § 3)
  - active + topo  : operator volume/play-pause + S1 regroup (TopologyChanged,
                    no spurious seeds, refresh re-pull correct)
```

## Verdict

**All 6 criteria satisfied - v0.5.0 release-ready.** S1, S4, v0.4 regression,
and S3 PASS with captured evidence; the S1 run confirms the codex-review
seed-suppression fix on hardware (no spurious `TopologyChanged`, no rediscover
loop). Criterion 5 accepted on the live-suite coverage and S5 closed
"not triggered" per the gate owner's decision (2026-06-03). CHANGELOG
`<!-- ACCEPTANCE -->` lines + the ROADMAP v0.5 acceptance note finalized; the
`chore(release): v0.5.0` PR follows.

Hardware: 2-speaker LAN (Living Room = Sonos Beam @ 10.83.0.103, Kitchen =
Sonos One @ 10.83.0.105); Android release on a real device (WSL build,
Flutter 3.44).
