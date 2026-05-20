# Discovery spike — findings

**Date:** 2026-05-15 **Context:** Before designing the `Wire` trait we ran a throwaway spike against `sonos-sdk` on real hardware to answer the three open questions in `ARCHITECTURE.md`. The spike found a showstopper in `sonos-sdk`'s discovery on multi-NIC Windows. This doc records the evidence, root cause, and the resulting strategy.

Spike code: `native/crates/wire/examples/{spike,ssdp_probe}.rs` (throwaway; kept because `ssdp_probe` is the prototype of the fix).

## Evidence

LAN: 4 Sonos units on `10.83.0.0/24` (router DHCP table). Windows PC wired (`10.83.0.10/24`, plus a WSL Hyper-V vEthernet at `172.28.80.1/20`). macOS on Wi-Fi, single NIC.

| Test | Result |
|---|---|
| Win `ssdp_probe` bound to `10.83.0.10` | 3 responders, correct `LOCATION` URLs |
| Win `ssdp_probe` bound to `0.0.0.0` | **0 responders** |
| Win `GET http://10.83.0.103:1400/xml/device_description.xml` | **200** |
| macOS `ssdp_probe` bound to `0.0.0.0` | 3 responders |
| macOS full `sonos-sdk` spike | **success** — 2 speakers, 2 groups, 4.6s |

## Root cause

`sonos-sdk-discovery-0.5.2/src/ssdp.rs:27`:

```rust
let socket = UdpSocket::bind("0.0.0.0:0")
```

The SSDP socket binds to `0.0.0.0` and the M-SEARCH multicast is sent without ever setting the multicast egress interface (`set_multicast_if_v4` / `IP_MULTICAST_IF`) and without enumerating interfaces. On a multi-NIC host the OS picks the egress interface from the routing table; the WSL vEthernet wins, so the query never reaches `10.83.0.0/24`. Single-NIC hosts (macOS Wi-Fi) work by accident.

The library is otherwise sound — the full `sonos-sdk` flow works correctly on macOS. The defect is isolated to discovery interface binding. This *strengthens* the decision to adopt `sonos-sdk`.

## Decision

**Own multi-interface SSDP + `SonosSystem::from_discovered_devices`, plus an upstream fix.**

- `oto-wire` performs its own SSDP across all usable IPv4 interfaces (prototype: `examples/ssdp_probe.rs`), fetches each device description, builds `Vec<sonos_sdk::Device>`, and calls `SonosSystem::from_discovered_devices(devices)`.
- That constructor is `pub` only behind `sonos-sdk`'s `test-support` feature (`test-support = []` — zero extra deps; also re-exports `Device`). We enable it.
- **Risk:** depending on a `test-support`-gated API in production. It is not a stable contract — a future `sonos-sdk` release could change it without a semver bump. **Mitigation:** pin `sonos-sdk = "=0.5.2"` (exact) while we depend on it, and land the upstream fix so the workaround (and the feature) can be dropped.
- Upstream: file an issue now with this evidence; submit a PR (bind per interface / set `IP_MULTICAST_IF` / enumerate interfaces) alongside `oto-wire`'s own SSDP work.

Rejected alternatives: upstream-fix-first (blocks all Windows progress on an unknown maintainer timeline); vendor/patch the discovery crate (second local patch to maintain, on top of the cargokit one).

## Other findings (feed the `Wire` trait design)

- **`SonosSystem::new()` blocked 4.6s even on a healthy network.** Off the FRB `init_app` path for certain; needs a deferred warm-up command and a UI loading state. (Open question #2 → resolved.)
- **`volume`/`mute`/`playback_state` `.get()` all returned `None` immediately after discovery.** `.get()` is `Option<T>` over an initially empty cache. The translation layer must `.fetch()` or `.watch()` to populate; it cannot assume post-discovery data is present.
- **0 events in a 12s window with no `.watch()` registered.** Confirms the opt-in event model: `oto-app` must explicitly register watches per property. The Phase-2 spike needs `.watch()` calls. (Open question #3 → informed: granularity is a deliberate design choice, not forced.)
- **`SpeakerId` = `RINCON_…`; `GroupId` = `RINCON_…:<n>`. Solo speaker reports `members=1 standalone=true`** — directly validates oto-core decision D2 (group-of-one model).
- **Device-count discrepancy:** router shows 4 Sonos; raw SSDP found 3 (`.115` silent on both platforms); `sonos-sdk` surfaced 2 named speakers (`.187` SSDP-visible but not listed). Likely bonded/satellite or asleep units. Ties to the bonded-speaker question deferred in oto-core. **New open item**, not a blocker.

## ZoneGroupTopology (open question #1) — still open

The spike confirmed *static* group/standalone reporting works. Whether `sonos-sdk` emits *topology-change* events (group form/break, coordinator change) is unverified — it needs the Phase-2 spike with explicit `.watch()` on the topology property. Remains the historical weak spot to validate before relying on it.
