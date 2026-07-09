# v0.4 - Pre-milestone spike findings

Status: spike complete (archived evidence). The scoping/design docs this once accompanied have been retired; the durable findings below now live in [`docs/sonos-notes.md` § Event model](../../sonos-notes.md#event-model-v04-load-bearing).

## Decision

**Path A wins for v0.4** - v0.4 builds on the upstream `sonos-sdk-state` reactive layer (`StateManager` + `SonosEventManager`) rather than raw `sonos-sdk-callback-server` + own change-detection. Cold-start is handled by the initial SUBSCRIBE NOTIFY (no separate `.fetch()` step). This is a bounded milestone decision, not a permanent architectural bet; the non-chosen Path B stays a v0.5 reconsideration point.

## Evidence summary

Hardware: 4-speaker Sonos household; Windows desktop dev box. Two responsive speakers participated:

- `RINCON_542A1B9463A801400` - "Living Room" - Beam, 10.83.0.103 (music playing throughout)
- `RINCON_7828CAE858CA01400` - "Kitchen" - Sonos One, 10.83.0.105 (idle)

Raw logs: the sibling `path-a-{idle,active}.log` / `path-b-{idle,active}.log` files - four files, ~310 KB total.

| Metric | Path A (`sonos-sdk-state`) | Path B (`callback-server` + own SUBSCRIBE) |
|---|---|---|
| Idle duration | ~27 min | ~26.5 min |
| Idle events / NOTIFYs | 827 events | 25 NOTIFYs (~33× fewer raw; ~5–10× fewer when fairly decomposed) |
| Idle errors / warnings | 0 | 0 |
| SUBSCRIBE failures | n/a | 0 (all 4 SIDs returned) |
| Active duration | ~8.5 min | ~8.4 min |
| Active event count | 262 | 82 NOTIFYs |
| Renewals exercised | Yes (4 at ~25 min) | Not exercised (renewal omitted from spike) |
| Latency to operator action | Sub-second | Sub-second |

## What decided it

In priority order (per spike-scope § 8):

1. **Correctness - tied within the spike.** Both paths: zero warnings, zero errors, every operator action surfaced with sub-second latency, group volume propagated correctly across members, no observed drops, no observed out-of-order arrivals, no observed duplicates.

2. **Cold-start tractability - tied.** The SUBSCRIBE's initial NOTIFY delivers full property state on both paths. Path A's cache went `None → populated` automatically ~50 ms after firewall detection completed; Path B's first NOTIFY per subscription contained the equivalent state. **The watch-after-fetch suppression concern documented in the original `sonos-notes` is moot for our use case - neither path requires an explicit `.fetch()` step.** Probes 2 and 3 from the spike scope are not needed.

3. **Code surface owned - Path A by an order of magnitude.** Path A's production shape is a ~50-line facade in `oto-wire` that bridges `sonos_state::StateManager` to oto's `ChangeEvent`. Path B's production shape is ~500–1000 lines: SUBSCRIBE + RENEW logic, doubly-escaped `LastChange` XML parsing, per-property decomposition (one NOTIFY contains many properties), per-property change-detection against last-seen. **This is the determining factor for a side project bounded at v1.0.**

4. **Long-running stability - tied; Path A more comfortable.** Path A's renewal mechanism fired automatically at the documented `renewal_threshold` mark (~25 min into the 27 min idle run) and survived. Path B's renewal code is on us if we adopt that path - we wouldn't even have noticed in the spike window (1800 s default timeout > 26.5 min run).

5. **Dep weight - Path B marginally lighter.** Both pull `tokio` + `warp` + `reqwest` transitively. Path A pulls ~25 crates total in the family; Path B pulls ~10. The delta is in libraries we'd never touch directly. Not a tiebreaker.

## What's in the bargain - honest costs of Path A

These get recorded in `sonos-notes.md § Event model` so they're not forgotten:

- **Polling on top of GENA.** `sonos-stream::polling::scheduler` polls AVTransport + RenderingControl every 5 s after a 5 s activation delay. This roughly doubles the traffic to the user's speakers compared to raw-GENA-only. ~0.5 polled events/sec per playing speaker is real LAN traffic - trivial in absolute terms but worth recording as a politeness cost.
- **`Position` is polling-derived, not GENA-derived.** Path A's ~2 s `position` cadence is the polling layer, not real Sonos behavior. Raw GENA delivers AVTransport NOTIFYs only ~every 3 minutes in bursts of 2–3 messages.
- **tokio is unavoidable.** `AGENTS.md`'s "no tokio in oto's own code" needs revisiting - Path A pulls the runtime via `sonos-event-manager` (worker thread). Path B would too via `warp` (callback server). The principle survives as "no async/await in oto's own surface"; tokio in the lockfile is the cost of any event-stream architecture.
- **Opaque debugging surface.** When something goes wrong inside `sonos-state` / `sonos-stream` / `sonos-event-manager`, we read upstream source. Acceptable for a hobby project given the maintainer is active and the lower layers (`callback-server`, `sonos-api`) are solid.
- **Bare `StateManager::new()` is an ergonomic footgun** - silently no-ops watches if no `SonosEventManager` is attached. The recommended `watch_property_with_subscription::<P>` helper is the only safe path. Cost us a 25 min idle run on rev 1; finding folded into `sonos-notes`.

## Findings worth keeping (durable Sonos / SDK facts)

These fold into `docs/sonos-notes.md` in the same PR:

1. **`sonos-stream` polls on top of GENA**, with observed `BrokerConfig`: callback port range 3400–3500, `polling_activation_delay: 5s`, `base_polling_interval: 5s`, `subscription_timeout: 1800s`, `renewal_threshold: 300s` (renew 5 min before expiry).
2. **The doubly-escaped `LastChange` XML format** - one NOTIFY contains a `<LastChange>` element whose inner XML is URI-encoded once, and any `<CurrentTrackMetaData>` value inside that is URI-encoded a second time (DIDL inside Event inside e:propertyset). Sample in sonos-notes.
3. **One NOTIFY = many property events when decomposed.** RenderingControl NOTIFY bundles Volume (Master/LF/RF), Mute (Master/LF/RF), Bass, Treble, Loudness, OutputFixed, SpeakerSize, SubGain, SubCrossover. AVTransport NOTIFY bundles TransportState, CurrentTrack, CurrentTrackURI, CurrentTrackDuration, CurrentTrackMetaData (DIDL-Lite), etc.
4. **Raw GENA AVTransport cadence on a playing speaker:** ~3 min between NOTIFY bursts; bursts are 2–3 messages within ~250 ms. If real-time position is needed in a UI, the implementation polls explicitly - the upstream `sonos-stream` does exactly this.
5. **Cold-start is the SUBSCRIBE's first NOTIFY**, not a separate `.fetch()`. Replaces the "watch-after-fetch suppression" framing in the v0.3-era sonos-notes.
6. **Group volume propagates as per-speaker volume events** within ~6 ms of each other across all group members. v0.4 needs UI-side collapse logic (or render from group-volume, not per-speaker).
7. **The "intermittent `position` updates" concern from the v0.3-era sonos-notes did not reproduce** in 35 min combined on real hardware. Downgrade from "load-bearing concern" to "watch for it; not observed in v0.4 spike." Caveat: single session, single LAN - not a "solved" claim.
8. **Renewal cycle in Path A works automatically.** Four renewals observed at the documented threshold; survived without intervention. If Path B is ever revisited, renewal is on us.
9. **`tokio` is unavoidable for v0.4** regardless of path.

## What we don't carry forward

- **Probes 2 and 3 from the spike scope** (hybrid fetch+watch, watch+bounded-fetch-fallback) - moot. The initial SUBSCRIBE NOTIFY handles cold-start cleanly without requiring an explicit `.fetch()` step on either path. Probe 1 (watch-only) is the implementation pattern.
- **The `Position` property as an oto-watched field.** Path A surfaces ~95% of all events as `position`, and most of that is polling-derived. Recommendation: drop `Position` from v0.4's watched-property list; derive UI position locally as `(last-known position from a transport event) + (wall-clock elapsed since)`, occasionally resynced. This applies whether we ship Path A or B - the data show position-event firehose isn't useful for our UI shape.
- **`spike/v0.4-events` as a branch.** Deleted after this PR merges. The commits survive in git history and serve as a working starting point for anyone who wants to build a Path-B alternative (see "alternative crate" below).

## Path A → Path B reversibility

The decision is reversible at bounded cost:

- v0.5 reconsideration point (already in the spec): if topology events surface unreliability in the upstream reactive layer (which has less hardware coverage upstream), re-pick.
- Migration cost A → B: delete ~50 lines of facade in `oto-wire`, drop in the spike-callback-server skeleton from git history as a starting point, write the renewal layer + property decomposition + change-detection that the spike binary omits. `Wire` trait / `ChangeEvent` / FRB stream / `oto-app::StateManager` all stay unchanged (the seam is designed for this swap).
- Migration cost B → A: more work - delete the ~500–1000 lines of SUBSCRIBE/RENEW/parser/diff code and write the thin facade from scratch.

The asymmetry comes from upstream being the maintained artifact: adopting it is "rent"; building Path B is "own." Switching rent → own is harder than the reverse.

## An alternative Path-B Rust crate - out of scope for oto

This is **not on oto's roadmap.** oto is explicitly bounded at v1.0 - maintenance-only thereafter - and forking a parallel library is exactly the kind of scope creep the v1.0 boundary exists to prevent.

That said, **the spike-callback-server.rs binary is unintentionally a working starting point** for anyone who wants to build a Path-B Rust library (call it `sonos-events-rs` or whatever): add renewal logic, write the doubly-escaped `LastChange` XML parser, add a public API. The spike commits survive in this PR's git history.

Recorded here so the work isn't lost. The case for that crate gets stronger if/when upstream `sonos-sdk-*` stops being maintained or the documented weak spots actually bite users in production. Neither is true today.

## Updates landing in this PR

- This findings doc.
- Raw evidence under `2026-05-22-v0.4-spike-evidence/`.
- `docs/sonos-notes.md § Event model` - full rewrite per the durable findings above.
- `docs/superpowers/specs/2026-05-21-v0.4-live-property-events-design.md`:
  - § 2 watched-property list: drop `Position`; derive locally instead.
  - § 6 cold-start handling: placeholder replaced - "Probe 1 (watch-only) via `watch_property_with_subscription`; the initial SUBSCRIBE NOTIFY seeds the cache."
  - § 8.1 latency target: confirmed sub-second on both paths; the ≤ 500 ms target is comfortable.
  - § 9 known issues: intermittent-position concern downgraded per finding #7; bare-`new()` footgun added.
  - § 12 out-of-scope: passive forward-reference to the alternative-crate possibility.
