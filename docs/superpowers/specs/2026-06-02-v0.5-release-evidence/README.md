# v0.5.0 release — hardware acceptance evidence

Mirrors the v0.4 § 8 pattern. This is the **user-ordered, non-skippable** Task 9
gate: v0.5.0 is not released until every criterion below is validated on real
hardware (LAN + a real Android device) with output captured here.

Run date: _TBD_ · LAN: _N-speaker household_ · Host: _Windows / WSL+device_

## Criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | **S1** — operator regroup → `TopologyChanged` (~5 s) + `refresh_topology` re-pull reflects new grouping | ⬜ pending | `live_topology_events` log below |
| 2 | **S4** — `model` populated for ≥2 speakers after discover + refresh | ⬜ pending | `live_model_populate` log below |
| 3 | **v0.4 regression** — Volume / Mute / Playback / Track / seed / renewal still pass | ⬜ pending | `live_events` log below |
| 4 | **S3** — release APK discovers the household on a real Android device | ⬜ pending | device note / logcat snippet |
| 5 | **Dogfood** — ≥30 min idle + ≥30 min active, regroup mid-session: events prompt, renewals clean, no rediscover storm, no errors | ⬜ pending | `v05-dogfood.log` summary |
| 6 | **S5** — lock-granularity: any UI-perceptible stutter under the active dogfood? (no → S5 "not triggered", closed) | ⬜ pending | dogfood observation |

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
# 5. Dogfood (≥30 min idle + ≥30 min active, regroup mid-session)
cargo run -p oto_native --example event-tail --features oto-wire/live-tests | tee /tmp/v05-dogfood.log
```

## Logs

### 1 — S1 topology events

```text
(paste live_topology_events output)
```

### 2 — S4 model populate

```text
(paste live_model_populate output)
```

### 3 — v0.4 regression

```text
(paste live_events output)
```

### 4 — S3 release APK on Android

```text
(device + Android version; discovery result / logcat snippet)
```

### 5 — Dogfood

```text
(idle + active summary: duration, event/error counts, renewal cycles, regroup behavior)
```

## Verdict

_TBD — fill once all six criteria pass. Then the CHANGELOG `<!-- ACCEPTANCE -->`
lines + the ROADMAP v0.5 acceptance note are updated to match, and the
`chore(release): v0.5.0` PR is opened._
