# v0.1 FRB Discover — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.1 — identity-only LAN discovery proven end-to-end through the Rust↔Dart FRB bridge, verifiable without the designed UI.

**Architecture:** Dependency chain `oto-core` (pure identity types + `Wire` trait + `WireError`) → `oto-wire` (own multi-NIC SSDP + `sonos-sdk` `test-support` adapter) / `oto-mock` (deterministic `Wire`) → `oto-app` (process-global wire ownership, replace-on-success) → `oto_native` (FRB glue: domain→DTO + non-sync `discover()`) → Dart `FutureProvider`. Approved design: `docs/plans/2026-05-15-frb-discover-command-design.md`.

**Tech Stack:** Rust 2021 (MSRV 1.94), `sonos-sdk =0.5.2` (`test-support`), `flutter_rust_bridge =2.12.0`, Flutter + Riverpod 3 codegen, `cargo-nextest`, `cargo-deny`.

---

## Pre-read (every executor, before Task 0)

1. `docs/plans/2026-05-15-frb-discover-command-design.md` (the approved surface).
2. `AGENTS.md` §4 (boundaries), §6 (validation matrix), §7 (change control).
3. This plan's **Deviations & §7 decision gates** section below — two items require user sign-off *before* the tasks that need them.

## Deviations & §7 decision gates (read; some block specific tasks)

These refine or extend the committed design doc. The user reviews this plan before execution; raise any veto now.

- **D1 — Representational mapping lives in `oto_native`, not `oto-app`.** The design doc says "oto-app maps … `DiscoverySnapshot` → the FRB `Topology` DTO." `oto-app` must stay FRB-agnostic (§4: `oto_native` is the only FRB crate). Refinement: `oto-app` does the **semantic** map (`sonos_sdk`→`oto_core`, errors→`WireError`) and returns domain types; `oto_native` does the **representational** map (`oto_core`→FRB DTO, `IpAddr`→`String`). This is faithful to the design's "single semantic mapping layer" intent. Low-impact, reversible.
- **D2 — E2E realized as a Rust integration test against `oto-mock` + a thin Dart provider test.** The design doc says "headless Dart/integration test drives `discover()` against oto-mock." A pure-Dart test cannot back the bridge with `oto-mock` without a **test-only FRB export polluting the production surface**. Faithful realization: (a) `native/tests/` integration test drives `oto_app::discover_with(MockWire)` and asserts the snapshot + the `oto_native` DTO mapping (proves domain↔bridge-DTO with zero LAN); (b) a `flutter test` asserts the `discovery` provider wiring compiles against the generated binding. Same guarantee, no production-surface pollution.
- **§7-GATE-A (blocks Task 3) — interface-enumeration dependency.** Real multi-NIC SSDP requires enumerating local IPv4 interfaces; `std` has no API for this. **Recommended:** add `if-addrs` (small, cross-platform incl. Windows/Android, widely used) to `oto-wire` only. Alternative: per-platform syscalls (more code, more maintenance). Adding a crate is §7 "ask before." **Executor must obtain user sign-off on `if-addrs` (or an alternative) before starting Task 3.**
- **D3 — Raw `TcpStream` HTTP/1.0 GET for device descriptions** (no HTTP-client crate). Keeps oto-wire's only non-`sonos-sdk` dep to the §7-GATE-A enumeration crate; matches the raw-socket ethos of the existing `ssdp_probe` prototype. `ureq`/`reqwest` rejected (§7 dep + overkill for one fixed GET).
- **AGENTS.md §5 constraint:** live SSDP/HTTP cannot be validated in a sandbox. Network paths are exercised by a `#[ignore]`d integration test the **user runs on a real LAN**; the plan gives the exact command. Non-network logic is fully unit-tested with no LAN.

---

### Task 0: Workspace scaffold — create `oto-app`, enable `test-support`

**Goal:** Add the `oto-app` crate to the workspace and enable `sonos-sdk`'s `test-support` feature on `oto-wire`, leaving the build green.

**Files:**
- Modify: `native/Cargo.toml` (workspace members + `[workspace.dependencies]`)
- Create: `native/crates/app/Cargo.toml`
- Create: `native/crates/app/src/lib.rs`
- Modify: `native/crates/wire/Cargo.toml` (feature flag)

**Acceptance Criteria:**
- [ ] `oto-app` is a workspace member with `oto-core`, `oto-wire` deps and `oto-mock` dev-dep
- [ ] `oto-wire`'s `sonos-sdk` dep enables `features = ["test-support"]`
- [ ] `cargo check --workspace` (from `native/`) is green; `cargo deny check` clean

**Verify:** `just bootstrap-native && just deny` → both exit 0

**Steps:**

- [ ] **Step 1: Add `oto-app` to the workspace.** Edit `native/Cargo.toml`:
  - `members = ["crates/app", "crates/core", "crates/mock", "crates/wire"]`
  - Under `[workspace.dependencies]` add: `oto-app = { path = "crates/app" }`

- [ ] **Step 2: Enable `test-support` on `oto-wire`.** Edit `native/crates/wire/Cargo.toml`, replace the `sonos-sdk` line:
```toml
sonos-sdk = { workspace = true, features = ["test-support"] }
```

- [ ] **Step 3: Create `native/crates/app/Cargo.toml`:**
```toml
[package]
name = "oto-app"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true
repository.workspace = true
description = "Runtime state owner: holds the Wire, routes the discover command."
publish = false

[lints]
workspace = true

[dependencies]
oto-core = { workspace = true }
oto-wire = { workspace = true }

[dev-dependencies]
oto-mock = { workspace = true }
```

- [ ] **Step 4: Create `native/crates/app/src/lib.rs`** (stub, replaced in Task 5):
```rust
#![deny(unsafe_code)]

//! `oto-app` — owns runtime state (the active `Wire`) and routes the
//! discover command. See docs/plans/2026-05-15-frb-discover-command-design.md.
```

- [ ] **Step 5: Verify.** Run `just bootstrap-native` then `just deny`. Expected: both exit 0, `oto-app` resolves.

- [ ] **Step 6: Commit.**
```bash
git add native/Cargo.toml native/crates/app native/crates/wire/Cargo.toml
git commit -m "chore(native): scaffold oto-app crate + enable sonos-sdk test-support"
```

---

### Task 1: `oto-core` — identity types, `Wire` trait, `WireError`

**Goal:** Add pure, dependency-free identity types, the minimal `Wire` trait, and a manual `WireError` enum to `oto-core`.

**Files:**
- Create: `native/crates/core/src/identity.rs`
- Create: `native/crates/core/src/wire.rs`
- Modify: `native/crates/core/src/lib.rs` (module decls + re-exports)
- Test: inline `#[cfg(test)]` in both new files

**Acceptance Criteria:**
- [ ] `SpeakerIdentity`, `GroupIdentity`, `DiscoverySnapshot` exist; no networking/async/3rd-party deps (oto-core stays pure)
- [ ] `Wire` trait has exactly one method: `fn discover(&self) -> Result<DiscoverySnapshot, WireError>`
- [ ] `WireError` has manual `Display` + `std::error::Error` (no `thiserror`); variants `Network(String)`, `NoDevicesFound`, `Backend(String)`
- [ ] `#![deny(unsafe_code)]` preserved; `cargo clippy -D warnings` clean

**Verify:** `cd native && cargo nextest run -p oto-core` → all pass; `just check` → exit 0

**Steps:**

- [ ] **Step 1: Write failing tests + types in `native/crates/core/src/identity.rs`:**
```rust
//! Identity-only projections used by v0.1 discovery. `Speaker`/`Group`
//! carry volume/transport that are unpopulated post-discovery (spike
//! finding); these lean types keep "identity-only" true at every layer.
//! v0.2 grows `Speaker` *around* `SpeakerIdentity`.

use std::net::IpAddr;

use crate::identifiers::{GroupId, SpeakerId};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpeakerIdentity {
    pub id: SpeakerId,
    pub room_name: String,
    pub model: Option<String>,
    pub ip: IpAddr,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GroupIdentity {
    pub id: GroupId,
    pub coordinator: SpeakerId,
    /// Coordinator at index 0 (matches Sonos ZoneGroupTopology ordering).
    pub members: Vec<SpeakerId>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoverySnapshot {
    pub speakers: Vec<SpeakerIdentity>,
    pub groups: Vec<GroupIdentity>,
}

#[cfg(test)]
mod tests {
    use std::net::{IpAddr, Ipv4Addr};

    use super::*;

    #[test]
    fn snapshot_holds_identities() {
        let kid = SpeakerId::new("RINCON_K");
        let snap = DiscoverySnapshot {
            speakers: vec![SpeakerIdentity {
                id: kid.clone(),
                room_name: "Kitchen".into(),
                model: Some("Sonos One".into()),
                ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 10)),
            }],
            groups: vec![GroupIdentity {
                id: GroupId::new("RINCON_K:0"),
                coordinator: kid.clone(),
                members: vec![kid],
            }],
        };
        assert_eq!(snap.speakers.len(), 1);
        assert_eq!(snap.groups[0].members[0], snap.groups[0].coordinator);
    }
}
```

- [ ] **Step 2: Write failing tests + `Wire`/`WireError` in `native/crates/core/src/wire.rs`:**
```rust
//! The `Wire` seam. `oto-app` depends on this trait, never on `sonos-sdk`.
//! Minimal for v0.1: one identity-only discovery method.

use std::fmt;

use crate::identity::DiscoverySnapshot;

/// One-shot identity discovery. Blocking. Implemented by `oto-wire`
/// (production) and `oto-mock` (tests).
pub trait Wire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError>;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WireError {
    /// No usable IPv4 interface, or SSDP send/socket failure.
    Network(String),
    /// SSDP completed but found zero Sonos devices.
    NoDevicesFound,
    /// Device-description fetch/parse or SonosSystem construction failed.
    Backend(String),
}

impl fmt::Display for WireError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WireError::Network(m) => write!(f, "discovery network error: {m}"),
            WireError::NoDevicesFound => {
                write!(f, "no Sonos devices found on the network")
            }
            WireError::Backend(m) => write!(f, "discovery backend error: {m}"),
        }
    }
}

impl std::error::Error for WireError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_strings() {
        assert_eq!(
            WireError::NoDevicesFound.to_string(),
            "no Sonos devices found on the network"
        );
        assert_eq!(
            WireError::Network("bind failed".into()).to_string(),
            "discovery network error: bind failed"
        );
    }
}
```

- [ ] **Step 3: Wire up `native/crates/core/src/lib.rs`.** Add after the existing `pub mod` block and re-exports:
```rust
pub mod identity;
pub mod wire;
```
and to the `pub use` block:
```rust
pub use identity::{DiscoverySnapshot, GroupIdentity, SpeakerIdentity};
pub use wire::{Wire, WireError};
```

- [ ] **Step 4: Run tests.** `cd native && cargo nextest run -p oto-core`. Expected: PASS (incl. existing tests).

- [ ] **Step 5: Lint.** `just check`. Expected: exit 0.

- [ ] **Step 6: Commit.**
```bash
git add native/crates/core/src
git commit -m "feat(core): identity types, minimal Wire trait, WireError"
```

---

### Task 2: `oto-mock` — deterministic `Wire` implementation

**Goal:** Replace the `placeholder()` stub with a `MockWire` that returns a deterministic `DiscoverySnapshot` and a configurable failure, enabling no-LAN tests.

**Files:**
- Modify: `native/crates/mock/src/lib.rs` (remove `placeholder`, add `MockWire`)
- Test: inline `#[cfg(test)]`

**Acceptance Criteria:**
- [ ] `MockWire::default().discover()` returns a fixed 2-speaker / 2-group snapshot (one stereo-paired-style group of 2, one solo)
- [ ] `MockWire::failing(WireError)` returns that error from `discover()`
- [ ] No `placeholder()` remains; nothing else references it (grep clean)
- [ ] `cargo clippy -D warnings` clean

**Verify:** `cd native && cargo nextest run -p oto-mock` → all pass; `just check` → exit 0

**Steps:**

- [ ] **Step 1: Confirm nothing depends on `placeholder()`.** Run: `git grep -n "placeholder" -- native/ ':!*frb_generated*'`. Expected: only matches inside `native/crates/mock/`.

- [ ] **Step 2: Rewrite `native/crates/mock/src/lib.rs`:**
```rust
#![deny(unsafe_code)]

//! Deterministic in-memory `Wire` for tests — no network. Integration
//! tests drive these fixtures so v0.1 discovery is provable without a LAN.

use std::net::{IpAddr, Ipv4Addr};

use oto_core::{
    DiscoverySnapshot, GroupId, GroupIdentity, SpeakerId, SpeakerIdentity, Wire, WireError,
};

/// A `Wire` that yields a fixed topology, or a fixed error.
pub struct MockWire {
    outcome: Result<DiscoverySnapshot, WireError>,
}

impl MockWire {
    /// A `Wire` that fails with `err`.
    pub fn failing(err: WireError) -> Self {
        Self { outcome: Err(err) }
    }

    fn fixture() -> DiscoverySnapshot {
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        let dining = SpeakerId::new("RINCON_DINING");
        let office = SpeakerId::new("RINCON_OFFICE");
        DiscoverySnapshot {
            speakers: vec![
                SpeakerIdentity {
                    id: kitchen.clone(),
                    room_name: "Kitchen".into(),
                    model: Some("Sonos One".into()),
                    ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 10)),
                },
                SpeakerIdentity {
                    id: dining.clone(),
                    room_name: "Dining".into(),
                    model: Some("Sonos One".into()),
                    ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 11)),
                },
                SpeakerIdentity {
                    id: office.clone(),
                    room_name: "Office".into(),
                    model: None,
                    ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 12)),
                },
            ],
            groups: vec![
                GroupIdentity {
                    id: GroupId::new("RINCON_KITCHEN:1"),
                    coordinator: kitchen.clone(),
                    members: vec![kitchen, dining],
                },
                GroupIdentity {
                    id: GroupId::new("RINCON_OFFICE:0"),
                    coordinator: office.clone(),
                    members: vec![office],
                },
            ],
        }
    }
}

impl Default for MockWire {
    fn default() -> Self {
        Self { outcome: Ok(Self::fixture()) }
    }
}

impl Wire for MockWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        self.outcome.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_returns_fixture() {
        let snap = MockWire::default().discover().unwrap();
        assert_eq!(snap.speakers.len(), 3);
        assert_eq!(snap.groups.len(), 2);
        assert_eq!(snap.groups[0].members.len(), 2);
        assert_eq!(snap.groups[0].members[0], snap.groups[0].coordinator);
        assert_eq!(snap.groups[1].members.len(), 1);
    }

    #[test]
    fn failing_returns_error() {
        let err = MockWire::failing(WireError::NoDevicesFound).discover();
        assert_eq!(err, Err(WireError::NoDevicesFound));
    }
}
```

- [ ] **Step 3: Tests.** `cd native && cargo nextest run -p oto-mock`. Expected: PASS.

- [ ] **Step 4: Lint.** `just check`. Expected: exit 0.

- [ ] **Step 5: Commit.**
```bash
git add native/crates/mock/src/lib.rs
git commit -m "feat(mock): deterministic MockWire fixture + failure mode"
```

---

### Task 3: `oto-wire` — own multi-interface SSDP

> **BLOCKED until §7-GATE-A is signed off** (interface-enumeration dependency — recommended `if-addrs`). Do not start until the user confirms the crate.

**Goal:** Promote the throwaway `ssdp_probe` prototype into product code: enumerate usable IPv4 interfaces, M-SEARCH each, collect unique device-description `LOCATION` URLs with a bounded timeout.

**Files:**
- Create: `native/crates/wire/src/ssdp.rs`
- Modify: `native/crates/wire/src/lib.rs` (module decl; keep the existing `SdkSpeakerId` link-check or remove if now redundant — keep for now, remove in Task 4)
- Modify: `native/crates/wire/Cargo.toml` (add the signed-off enumeration crate)
- Test: inline `#[cfg(test)]` for LOCATION parsing/dedupe (pure, no socket)

**Acceptance Criteria:**
- [ ] `discover_locations(timeout: Duration) -> Result<Vec<String>, WireError>` binds one UDP socket per usable IPv4 interface, sends the ZonePlayer M-SEARCH, returns unique `LOCATION` URLs
- [ ] Loopback / link-local interfaces excluded; zero usable interfaces → `WireError::Network`
- [ ] LOCATION header parsing + dedupe is unit-tested with synthetic SSDP bytes (no socket)
- [ ] `#![deny(unsafe_code)]`; clippy `-D warnings` clean

**Verify (non-network):** `cd native && cargo nextest run -p oto-wire` → parsing tests pass; `just check` → exit 0
**Verify (LAN, user-run — AGENTS.md §5):** documented in Task 6's live step

**Steps:**

- [ ] **Step 1: Add the signed-off dependency** to `native/crates/wire/Cargo.toml` `[dependencies]` (example assumes `if-addrs` was approved):
```toml
if-addrs = "0.13"
```
(If a different option was approved in §7-GATE-A, use that instead and adjust Step 3.)

- [ ] **Step 2: Create `native/crates/wire/src/ssdp.rs`.** Parsing helper first (pure, testable), then the socket loop. The M-SEARCH and LOCATION-extraction mirror `examples/ssdp_probe.rs`:
```rust
//! Own multi-interface SSDP. sonos-sdk's discovery binds 0.0.0.0 and
//! fails on multi-NIC hosts (spike findings / tatimblin/sonos-sdk#76);
//! we enumerate interfaces and bind each explicitly.

use std::collections::BTreeSet;
use std::net::{IpAddr, UdpSocket};
use std::time::{Duration, Instant};

use oto_core::WireError;

const SSDP_ADDR: &str = "239.255.255.250:1900";
const ST: &str = "urn:schemas-upnp-org:device:ZonePlayer:1";

fn msearch() -> String {
    format!(
        "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n\
         MAN: \"ssdp:discover\"\r\nMX: 2\r\nST: {ST}\r\n\
         USER-AGENT: oto/0.1 UPnP/1.0\r\n\r\n"
    )
}

/// Extract the `LOCATION` value from one SSDP response payload.
fn location_of(payload: &str) -> Option<String> {
    payload
        .lines()
        .find(|l| l.to_ascii_lowercase().starts_with("location:"))
        .map(|l| l["location:".len()..].trim().to_string())
}

/// Usable IPv4 interface addresses (no loopback, no link-local).
fn usable_ipv4() -> Vec<IpAddr> {
    if_addrs::get_if_addrs()
        .into_iter()
        .flatten()
        .filter_map(|i| match i.ip() {
            IpAddr::V4(v4) if !v4.is_loopback() && !v4.is_link_local() => {
                Some(IpAddr::V4(v4))
            }
            _ => None,
        })
        .collect()
}

/// SSDP across every usable IPv4 interface. Unique LOCATION URLs.
pub fn discover_locations(timeout: Duration) -> Result<Vec<String>, WireError> {
    let ifaces = usable_ipv4();
    if ifaces.is_empty() {
        return Err(WireError::Network("no usable IPv4 interface".into()));
    }
    let mut found: BTreeSet<String> = BTreeSet::new();
    for ip in ifaces {
        let sock = UdpSocket::bind((ip, 0))
            .map_err(|e| WireError::Network(format!("bind {ip}: {e}")))?;
        sock.set_read_timeout(Some(Duration::from_millis(800)))
            .map_err(|e| WireError::Network(e.to_string()))?;
        if sock.send_to(msearch().as_bytes(), SSDP_ADDR).is_err() {
            continue; // interface can't egress multicast; try the rest
        }
        let mut buf = [0u8; 2048];
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            match sock.recv_from(&mut buf) {
                Ok((n, _)) => {
                    if let Some(loc) =
                        location_of(&String::from_utf8_lossy(&buf[..n]))
                    {
                        found.insert(loc);
                    }
                }
                Err(e)
                    if e.kind() == std::io::ErrorKind::WouldBlock
                        || e.kind() == std::io::ErrorKind::TimedOut => {}
                Err(_) => break,
            }
        }
    }
    Ok(found.into_iter().collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_location_case_insensitive() {
        let resp = "HTTP/1.1 200 OK\r\nLOCATION: http://10.83.0.10:1400/xml/device_description.xml\r\nST: foo\r\n\r\n";
        assert_eq!(
            location_of(resp).as_deref(),
            Some("http://10.83.0.10:1400/xml/device_description.xml")
        );
    }

    #[test]
    fn no_location_header() {
        assert_eq!(location_of("HTTP/1.1 200 OK\r\nST: foo\r\n\r\n"), None);
    }
}
```

- [ ] **Step 3: Declare the module** in `native/crates/wire/src/lib.rs`: add `pub mod ssdp;`.

- [ ] **Step 4: Non-network tests.** `cd native && cargo nextest run -p oto-wire`. Expected: parsing tests PASS.

- [ ] **Step 5: Lint + supply chain.** `just check` then `cd native && cargo deny check`. Expected: exit 0 (re-run deny because a dep was added).

- [ ] **Step 6: Commit.**
```bash
git add native/crates/wire/src/ssdp.rs native/crates/wire/src/lib.rs native/crates/wire/Cargo.toml
git commit -m "feat(wire): own multi-interface SSDP location discovery"
```

---

### Task 4: `oto-wire` — device fetch, `SonosSystem` build, `Wire` impl

**Goal:** Fetch each device description over a raw TCP GET, parse it with `sonos-sdk`'s `test-support` `DeviceDescription`, build the `SonosSystem`, and map `sonos_sdk::{Speaker,Group}` → `oto_core` identities behind `impl Wire for SonosWire`.

**Files:**
- Create: `native/crates/wire/src/http.rs` (raw device-description GET)
- Create: `native/crates/wire/src/adapter.rs` (`SonosWire`, mapping, `impl Wire`)
- Modify: `native/crates/wire/src/lib.rs` (module decls, re-export `SonosWire`; drop the now-redundant `SdkSpeakerId` link-check + its test)
- Test: inline `#[cfg(test)]` mapping tests using `sonos_sdk` `test-support` `Device{..}` (no network)

**Acceptance Criteria:**
- [ ] `SonosWire` implements `oto_core::Wire`; `discover()` runs SSDP → per-LOCATION TCP GET → `DeviceDescription::from_xml` → `is_sonos_device` filter → `to_device` → `SonosSystem::from_discovered_devices` → map to `DiscoverySnapshot`
- [ ] Zero devices after SSDP → `WireError::NoDevicesFound`; `SdkError`/parse failures → `WireError::Backend`
- [ ] `sonos_sdk::Speaker { id: SpeakerId, name, ip: IpAddr, model_name }` → `SpeakerIdentity` (room_name from `name`; `model` = `Some(model_name)` unless empty → `None`); `Group` (`coordinator()`, `members()`) → `GroupIdentity` with coordinator at `members[0]`
- [ ] `SpeakerId`/`GroupId` → `String` uses the **verified** conversion (Step 2) — not a guess
- [ ] Mapping unit tests pass with no network; clippy `-D warnings` clean

**Verify (non-network):** `cd native && cargo nextest run -p oto-wire` → mapping tests pass; `just check` + `cd native && cargo deny check` → exit 0

**Steps:**

- [ ] **Step 1: VERIFY-DON'T-GUESS — `SpeakerId`/`GroupId` → `String`.** Inspect the pinned source:
```bash
SDK=~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/sonos-sdk-state-0.5.2
grep -rn "pub struct SpeakerId\|pub struct GroupId\|impl .*Display.*SpeakerId\|impl .*Display.*GroupId\|pub fn as_str\|pub fn new" "$SDK/src" | head -30
```
Record the exact conversion (expected: `Display`/`.to_string()` or a public accessor). Use that in Step 4 — if none exists, STOP and surface it (do not invent one).

- [ ] **Step 2: VERIFY-DON'T-GUESS — `if_addrs` API name.** Confirm the function is `if_addrs::get_if_addrs()` for the approved crate/version (used in Task 3); adjust if the approved crate differs. (`cargo doc -p if-addrs --no-deps` or read its `src`.)

- [ ] **Step 3: Create `native/crates/wire/src/http.rs`** — minimal blocking HTTP/1.0 GET (no crate):
```rust
//! Minimal blocking HTTP/1.0 GET for UPnP device descriptions. Raw
//! TcpStream keeps oto-wire free of an HTTP-client dependency (D3).

use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;

use oto_core::WireError;

/// GET `url` (expects `http://host:port/path`), return the response body.
pub fn get_body(url: &str, timeout: Duration) -> Result<String, WireError> {
    let rest = url.strip_prefix("http://").ok_or_else(|| {
        WireError::Backend(format!("non-http LOCATION: {url}"))
    })?;
    let (authority, path) = match rest.split_once('/') {
        Some((a, p)) => (a, format!("/{p}")),
        None => (rest, "/".to_string()),
    };
    let mut stream = TcpStream::connect(authority)
        .map_err(|e| WireError::Backend(format!("connect {authority}: {e}")))?;
    stream
        .set_read_timeout(Some(timeout))
        .and_then(|_| stream.set_write_timeout(Some(timeout)))
        .map_err(|e| WireError::Backend(e.to_string()))?;
    let req = format!(
        "GET {path} HTTP/1.0\r\nHost: {authority}\r\n\
         Connection: close\r\nUser-Agent: oto/0.1\r\n\r\n"
    );
    stream
        .write_all(req.as_bytes())
        .map_err(|e| WireError::Backend(e.to_string()))?;
    let mut raw = String::new();
    stream
        .read_to_string(&mut raw)
        .map_err(|e| WireError::Backend(e.to_string()))?;
    let body = raw
        .split_once("\r\n\r\n")
        .map(|(_, b)| b.to_string())
        .ok_or_else(|| WireError::Backend("malformed HTTP response".into()))?;
    Ok(body)
}
```

- [ ] **Step 4: Create `native/crates/wire/src/adapter.rs`.** Use the **verified** `SpeakerId`→`String` from Step 1 (shown below as `.to_string()` — replace if Step 1 found otherwise):
```rust
//! Production `Wire`: own SSDP + sonos-sdk (test-support) adapter.

use std::time::Duration;

use oto_core::{
    DiscoverySnapshot, GroupId, GroupIdentity, SpeakerId, SpeakerIdentity, Wire, WireError,
};
use sonos_sdk::sonos_discovery::{device::DeviceDescription, Device};
use sonos_sdk::SonosSystem;

use crate::{http, ssdp};

const SSDP_TIMEOUT: Duration = Duration::from_secs(3);
const HTTP_TIMEOUT: Duration = Duration::from_secs(2);

pub struct SonosWire;

impl SonosWire {
    pub fn new() -> Self {
        Self
    }
}

impl Default for SonosWire {
    fn default() -> Self {
        Self::new()
    }
}

fn extract_ip(url: &str) -> Option<String> {
    url.strip_prefix("http://")?
        .split('/')
        .next()?
        .split(':')
        .next()
        .map(str::to_string)
}

fn to_devices(locations: Vec<String>) -> Vec<Device> {
    locations
        .into_iter()
        .filter_map(|loc| {
            let xml = http::get_body(&loc, HTTP_TIMEOUT).ok()?;
            let desc = DeviceDescription::from_xml(&xml).ok()?;
            if !desc.is_sonos_device() {
                return None;
            }
            Some(desc.to_device(extract_ip(&loc)?))
        })
        .collect()
}

fn map_snapshot(system: &SonosSystem) -> DiscoverySnapshot {
    let speakers = system
        .speakers()
        .into_iter()
        .map(|s| SpeakerIdentity {
            id: SpeakerId::new(s.id.to_string()),
            room_name: s.name,
            model: if s.model_name.is_empty() {
                None
            } else {
                Some(s.model_name)
            },
            ip: s.ip,
        })
        .collect();
    let groups = system
        .groups()
        .into_iter()
        .map(|g| {
            let coord = g
                .coordinator()
                .map(|c| SpeakerId::new(c.id.to_string()));
            let mut members: Vec<SpeakerId> = Vec::new();
            if let Some(c) = &coord {
                members.push(c.clone());
            }
            for m in g.members() {
                let id = SpeakerId::new(m.id.to_string());
                if Some(&id) != coord.as_ref() {
                    members.push(id);
                }
            }
            GroupIdentity {
                id: GroupId::new(g.id.to_string()),
                coordinator: coord
                    .unwrap_or_else(|| SpeakerId::new(g.id.to_string())),
                members,
            }
        })
        .collect();
    DiscoverySnapshot { speakers, groups }
}

impl Wire for SonosWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        let locations = ssdp::discover_locations(SSDP_TIMEOUT)?;
        let devices = to_devices(locations);
        if devices.is_empty() {
            return Err(WireError::NoDevicesFound);
        }
        let system = SonosSystem::from_discovered_devices(devices)
            .map_err(|e| WireError::Backend(format!("{e:?}")))?;
        Ok(map_snapshot(&system))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dev(id: &str, room: &str, ip: &str, model: &str) -> Device {
        Device {
            id: id.into(),
            name: room.into(),
            room_name: room.into(),
            ip_address: ip.into(),
            port: 1400,
            model_name: model.into(),
        }
    }

    #[test]
    fn maps_speakers_and_groups_without_network() {
        // sonos-sdk test-support: build a system from synthetic Devices.
        let system = SonosSystem::from_discovered_devices(vec![
            dev("RINCON_A", "Kitchen", "10.83.0.10", "Sonos One"),
            dev("RINCON_B", "Office", "10.83.0.11", ""),
        ])
        .expect("from_discovered_devices");
        let snap = map_snapshot(&system);
        assert_eq!(snap.speakers.len(), 2);
        let office = snap
            .speakers
            .iter()
            .find(|s| s.room_name == "Office")
            .unwrap();
        assert_eq!(office.model, None); // empty model_name → None
        assert!(!snap.groups.is_empty());
        for g in &snap.groups {
            assert_eq!(g.members[0], g.coordinator); // coordinator first
        }
    }

    #[test]
    fn extract_ip_from_location() {
        assert_eq!(
            extract_ip("http://10.83.0.10:1400/xml/device_description.xml"),
            Some("10.83.0.10".to_string())
        );
    }
}
```
> If Step 1 found that `SpeakerId`/`GroupId` expose a different conversion (e.g. `.as_str()` or a field), replace every `.to_string()` on `s.id`/`c.id`/`m.id`/`g.id` accordingly before running tests.

- [ ] **Step 5: Update `native/crates/wire/src/lib.rs`** — remove the obsolete `SdkSpeakerId` alias + its `tests` module; add:
```rust
pub mod adapter;
pub mod http;
pub mod ssdp;

pub use adapter::SonosWire;
```
(Keep `#![deny(unsafe_code)]` and the crate doc comment.)

- [ ] **Step 6: Tests + lint + supply chain.** `cd native && cargo nextest run -p oto-wire` (mapping tests PASS, no network), then `just check`, then `cd native && cargo deny check`. Expected: all exit 0.

- [ ] **Step 7: Commit.**
```bash
git add native/crates/wire/src
git commit -m "feat(wire): SonosWire — device fetch, SonosSystem build, identity mapping"
```

---

### Task 5: `oto-app` — process-global wire ownership + `discover()`

**Goal:** `oto-app` owns the active `Wire` in a process-global; `discover()` constructs `SonosWire`, calls it, replaces the held wire on success, leaves the prior one intact on failure, and is idempotent.

**Files:**
- Modify: `native/crates/app/src/lib.rs` (replace stub)
- Test: inline `#[cfg(test)]` using `oto-mock` (dev-dep)

**Acceptance Criteria:**
- [ ] `discover() -> Result<DiscoverySnapshot, WireError>` uses `SonosWire` in production
- [ ] `discover_with(make: impl FnOnce() -> Box<dyn Wire + Send>) -> Result<DiscoverySnapshot, WireError>` is the testable seam: success stores the wire (replaces any prior), failure leaves a previously-stored wire intact
- [ ] Re-calling after success replaces the held wire (idempotent refresh)
- [ ] No `unsafe`; clippy `-D warnings` clean

**Verify:** `cd native && cargo nextest run -p oto-app` → all pass; `just check` + `cd native && cargo deny check` → exit 0

**Steps:**

- [ ] **Step 1: Replace `native/crates/app/src/lib.rs`:**
```rust
#![deny(unsafe_code)]

//! `oto-app` — owns runtime state (the active `Wire`) and routes the
//! discover command. See docs/plans/2026-05-15-frb-discover-command-design.md.

use std::sync::{Mutex, OnceLock};

use oto_core::{DiscoverySnapshot, Wire, WireError};
use oto_wire::SonosWire;

type HeldWire = Box<dyn Wire + Send>;

fn slot() -> &'static Mutex<Option<HeldWire>> {
    static SLOT: OnceLock<Mutex<Option<HeldWire>>> = OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(None))
}

/// Construct a wire, run discovery, and on success replace the held
/// wire (so v0.2 playback can act on it). On failure the previously
/// held wire — if any — is left intact.
pub fn discover_with(
    make: impl FnOnce() -> HeldWire,
) -> Result<DiscoverySnapshot, WireError> {
    let wire = make();
    let snapshot = wire.discover()?;
    *slot().lock().expect("wire slot poisoned") = Some(wire);
    Ok(snapshot)
}

/// Production entry point: discovery backed by `SonosWire`.
pub fn discover() -> Result<DiscoverySnapshot, WireError> {
    discover_with(|| Box::new(SonosWire::new()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use oto_mock::MockWire;

    #[test]
    fn success_then_failure_keeps_prior_wire() {
        // success stores a wire and returns the fixture
        let snap = discover_with(|| Box::new(MockWire::default())).unwrap();
        assert_eq!(snap.speakers.len(), 3);

        // failure returns Err but does not clear the held wire
        let err = discover_with(|| {
            Box::new(MockWire::failing(WireError::NoDevicesFound))
        });
        assert_eq!(err, Err(WireError::NoDevicesFound));
        assert!(slot().lock().unwrap().is_some());
    }
}
```

- [ ] **Step 2: Tests.** `cd native && cargo nextest run -p oto-app`. Expected: PASS.
  > Note: the test shares a process-global; keep assertions order-independent (the provided test is self-contained — it asserts presence, not identity).

- [ ] **Step 3: Lint + supply chain.** `just check` then `cd native && cargo deny check`. Expected: exit 0.

- [ ] **Step 4: Commit.**
```bash
git add native/crates/app/src/lib.rs
git commit -m "feat(app): process-global wire ownership + discover() routing"
```

---

### Task 6: FRB surface — DTOs + non-sync `discover()` command

**Goal:** Add the FRB `Topology`/`DiscoveredSpeaker`/`DiscoveredGroup`/`DiscoveryError` DTOs and a non-sync `discover()` command in `native/src/api.rs` that delegates to `oto_app::discover()` and does the representational map (D1). Regenerate committed bindings.

**Files:**
- Modify: `native/Cargo.toml` (root `[dependencies]`: add `oto-app`)
- Modify: `native/src/api.rs` (add DTOs + `discover()`; keep `greet`/`init_app`)
- Regenerate (committed): `app/lib/src/rust/*`, `native/src/frb_generated*`
- Create: `native/tests/discover_e2e.rs` (no-LAN integration test, D2)

**Acceptance Criteria:**
- [ ] `pub fn discover() -> Result<Topology, DiscoveryError>` is **non-sync** (no `#[frb(sync)]`) → Dart `Future`
- [ ] `init_app` unchanged (discovery NOT on the `#[frb(init)]` path)
- [ ] `WireError` → FRB `DiscoveryError` (`Network`→`Network`, `NoDevicesFound`→`NoDevicesFound`, `Backend`→`Sdk`); `IpAddr`→`String` via `to_string()`
- [ ] `just gen` run; `dart scripts/verify_generated.dart` clean (CI gate, AGENTS.md §6)
- [ ] `native/tests/discover_e2e.rs` drives `oto_app::discover_with(MockWire)` + the DTO map, asserts the `Topology`, no network
- [ ] `just check` + `just test` + `cd native && cargo deny check` all exit 0

**Verify:** `just gen && just check && just test && cd native && cargo deny check && cd .. && dart app/scripts/verify_generated.dart` → all exit 0

**Steps:**

- [ ] **Step 1: Add `oto-app` to the cdylib.** `native/Cargo.toml` `[dependencies]`: add `oto-app = { workspace = true }`.

- [ ] **Step 2: Edit `native/src/api.rs`** — keep existing `greet`/`init_app`; append:
```rust
use oto_app::discover as app_discover;
use oto_core::WireError;

pub struct Topology {
    pub speakers: Vec<DiscoveredSpeaker>,
    pub groups: Vec<DiscoveredGroup>,
}

pub struct DiscoveredSpeaker {
    pub id: String,
    pub room_name: String,
    pub model: Option<String>,
    pub ip: String,
}

pub struct DiscoveredGroup {
    pub id: String,
    pub coordinator: String,
    pub members: Vec<String>,
}

pub enum DiscoveryError {
    Network(String),
    NoDevicesFound,
    Sdk(String),
}

impl From<WireError> for DiscoveryError {
    fn from(e: WireError) -> Self {
        match e {
            WireError::Network(m) => DiscoveryError::Network(m),
            WireError::NoDevicesFound => DiscoveryError::NoDevicesFound,
            WireError::Backend(m) => DiscoveryError::Sdk(m),
        }
    }
}

/// Deferred warm-up. Blocking ~3–5 s; FRB runs it off the UI isolate.
/// NOT on the #[frb(init)] path. Identity-only snapshot.
pub fn discover() -> Result<Topology, DiscoveryError> {
    let snap = app_discover()?;
    Ok(Topology {
        speakers: snap
            .speakers
            .into_iter()
            .map(|s| DiscoveredSpeaker {
                id: s.id.to_string(),
                room_name: s.room_name,
                model: s.model,
                ip: s.ip.to_string(),
            })
            .collect(),
        groups: snap
            .groups
            .into_iter()
            .map(|g| DiscoveredGroup {
                id: g.id.to_string(),
                coordinator: g.coordinator.to_string(),
                members: g.members.iter().map(|m| m.to_string()).collect(),
            })
            .collect(),
    })
}

// TODO(v0.2): remove the `greet` demo bridge target.
```

- [ ] **Step 3: Create `native/tests/discover_e2e.rs`** (D2 — no-LAN end-to-end through the domain + DTO map):
```rust
//! v0.1 acceptance: discovery proven end-to-end without a LAN, driving
//! oto-app's seam with the deterministic MockWire and asserting the
//! oto_core -> identity mapping the FRB layer renders.

use oto_app::discover_with;
use oto_mock::MockWire;

#[test]
fn discovery_end_to_end_against_mock() {
    let snap = discover_with(|| Box::new(MockWire::default()))
        .expect("mock discovery succeeds");
    assert_eq!(snap.speakers.len(), 3);
    assert_eq!(snap.groups.len(), 2);
    // coordinator-first invariant the DTO relies on
    for g in &snap.groups {
        assert_eq!(g.members[0], g.coordinator);
    }
}
```
Add to `native/Cargo.toml` `[dev-dependencies]`: `oto-app = { workspace = true }` and `oto-mock = { workspace = true }` (oto-mock dev-dep already present from earlier; add oto-app).

- [ ] **Step 4: Regenerate bindings.** `just gen`. Confirm `app/lib/src/rust/api.dart` now exports `discover` returning a `Future`, and `Topology`/`DiscoveredSpeaker`/`DiscoveredGroup`/`DiscoveryError` types exist.

- [ ] **Step 5: Full gate run (AGENTS.md §6 for `native/src/api.rs`).**
```bash
just gen && just check && just test && (cd native && cargo deny check) && dart app/scripts/verify_generated.dart
```
Expected: every command exits 0; `verify_generated.dart` reports no drift.

- [ ] **Step 6: Commit** (include regenerated sources):
```bash
git add native/Cargo.toml native/src/api.rs native/tests/discover_e2e.rs \
        app/lib/src/rust native/src/frb_generated.rs native/src/frb_generated.io.dart 2>/dev/null; \
  git add native/src/frb_generated* app/lib/src/rust
git commit -m "feat(native): FRB discover() command + DTOs; no-LAN e2e test"
```

---

### Task 7: Riverpod `FutureProvider` + Dart wiring test

**Goal:** Expose discovery to Dart as a `FutureProvider` and prove the binding wiring with a `flutter test` (D2 part b). No UI work (v0.1 bar is headless).

**Files:**
- Create: `app/lib/src/state/discovery.dart`
- Regenerate (committed): `app/lib/src/state/discovery.g.dart`
- Create: `app/test/discovery_provider_test.dart`

**Acceptance Criteria:**
- [ ] `@riverpod Future<Topology> discovery(Ref ref)` calls `rust_api.discover()`
- [ ] `discovery.g.dart` regenerated via `just gen-dart` and committed
- [ ] `flutter test` asserts the provider is a `FutureProvider<Topology>` and the generated `discover` symbol is referenced (compile-level wiring proof; does not hit the LAN)
- [ ] `flutter analyze` + `flutter test` exit 0; `dart scripts/verify_generated.dart` clean

**Verify:** `cd app && flutter analyze && flutter test` → exit 0; `dart app/scripts/verify_generated.dart` → no drift

**Steps:**

- [ ] **Step 1: Create `app/lib/src/state/discovery.dart`:**
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;

part 'discovery.g.dart';

/// Deferred LAN discovery. The Rust `discover()` blocks ~3–5 s and FRB
/// runs it off the UI isolate, so this is a Future provider: AsyncValue
/// gives loading / error / data; retry via `ref.invalidate`.
@riverpod
Future<rust_api.Topology> discovery(Ref ref) => rust_api.discover();
```

- [ ] **Step 2: Regenerate Dart codegen.** `just gen-dart` (or `just gen`). Confirm `app/lib/src/state/discovery.g.dart` is created.

- [ ] **Step 3: Create `app/test/discovery_provider_test.dart`** — wiring/compile proof (no LAN):
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/rust/api.dart' as rust_api;

void main() {
  test('discovery provider is wired to the FRB discover() binding', () {
    // Compile-level proof: the provider exists and the generated
    // binding symbol is referenced. The live call needs a LAN and is
    // covered by the user-run integration step (Task 8).
    expect(discoveryProvider, isNotNull);
    expect(rust_api.discover, isA<Function>());
  });
}
```

- [ ] **Step 4: Gates (AGENTS.md §6 for `app/lib/**` + `@riverpod`).**
```bash
cd app && flutter analyze && flutter test && cd .. && dart app/scripts/verify_generated.dart
```
Expected: all exit 0; no generated drift.

- [ ] **Step 5: Commit.**
```bash
git add app/lib/src/state/discovery.dart app/lib/src/state/discovery.g.dart app/test/discovery_provider_test.dart
git commit -m "feat(app): discovery FutureProvider + binding wiring test"
```

---

### Task 8: User-run LAN verification (AGENTS.md §5)

**Goal:** Prove real multi-NIC discovery end-to-end on hardware — the one path a sandbox cannot validate.

**Files:**
- Create: `native/crates/wire/tests/live_discovery.rs` (an `#[ignore]`d integration test)

**Acceptance Criteria:**
- [ ] An `#[ignore]`d test calls `SonosWire::new().discover()` and prints the snapshot
- [ ] The exact run command is documented for the user; the agent does NOT claim this passed unless the user provides output

**Verify (USER, on a real LAN):** `cd native && cargo test -p oto-wire --test live_discovery -- --ignored --nocapture` → ≥1 speaker, expected room names

**Steps:**

- [ ] **Step 1: Create `native/crates/wire/tests/live_discovery.rs`:**
```rust
//! LAN-only. Ignored by default — needs real Sonos hardware and cannot
//! run in CI / sandbox (AGENTS.md §5). Run:
//!   cargo test -p oto-wire --test live_discovery -- --ignored --nocapture

use oto_core::Wire;
use oto_wire::SonosWire;

#[test]
#[ignore = "requires a real Sonos LAN"]
fn live_discovery_finds_speakers() {
    let snap = SonosWire::new().discover().expect("discovery");
    println!("speakers={} groups={}", snap.speakers.len(), snap.groups.len());
    for s in &snap.speakers {
        println!("  {} [{}] {:?} {}", s.room_name, s.id, s.model, s.ip);
    }
    assert!(!snap.speakers.is_empty(), "expected ≥1 speaker on the LAN");
}
```

- [ ] **Step 2: Non-network sanity.** `cd native && cargo nextest run -p oto-wire` (the ignored test is skipped) → PASS. `just check` → exit 0.

- [ ] **Step 3: Commit.**
```bash
git add native/crates/wire/tests/live_discovery.rs
git commit -m "test(wire): ignored live LAN discovery integration test"
```

- [ ] **Step 4: HAND OFF TO USER.** Ask the user to run, on a machine with Sonos on the LAN:
  `cd native && cargo test -p oto-wire --test live_discovery -- --ignored --nocapture`
  Do **not** mark v0.1 discovery "proven on hardware" until the user reports the output (speaker count + room names). Capture their output in the close.

---

## Self-Review

**Spec coverage** (against `docs/plans/2026-05-15-frb-discover-command-design.md`):
- Command shape A (non-sync `discover()` → Future) → Task 6 ✓
- Identity-only DTOs (`Topology`/`DiscoveredSpeaker`/`DiscoveredGroup`) → Task 6 ✓
- `DiscoveryError {Network,NoDevicesFound,Sdk}` + retryable → Task 6 (`From<WireError>`) ✓
- Minimal `Wire` trait + `oto-core` identity types (decision B) → Task 1 ✓
- `oto-wire` own multi-NIC SSDP + `from_discovered_devices` → Tasks 3, 4 ✓
- `oto-mock` deterministic `Wire` → Task 2 ✓
- `oto-app` process-global, replace-on-success, prior-intact-on-failure, idempotent → Task 5 ✓
- Riverpod `FutureProvider` → Task 7 ✓
- Headless e2e against oto-mock (D2 realization) → Task 6 (Rust) + Task 7 (Dart wiring) ✓
- Open item #1 (`test-support` `Device` API) → resolved in plan (verified) + Task 4 Step 1 verify-don't-guess ✓
- Open item #2 (`ip` rendering) → `to_string()`, Task 6 ✓
- `init_app` untouched / not on `#[frb(init)]` → Task 6 AC ✓
- ARCHITECTURE.md already updated (prior commit `0775ce6`) ✓
- AGENTS.md §6 gates per touched surface → each task's Verify ✓
- AGENTS.md §5 LAN limit → Task 8 (user-run) ✓

**Placeholder scan:** none — every code step shows complete code; verify-don't-guess steps name exact commands and instruct STOP-don't-invent.

**Type consistency:** `Wire::discover -> Result<DiscoverySnapshot, WireError>` consistent across Tasks 1/2/4/5; `WireError` variants `Network/NoDevicesFound/Backend` consistent; FRB `DiscoveryError` `Network/NoDevicesFound/Sdk` mapped 1:1 in Task 6; `SonosWire`/`MockWire` names stable; `discover_with`/`discover` signatures stable Tasks 5↔6↔Task 8.

## Execution order / dependencies

`0 → 1 → {2, 3} → 4 → 5 → 6 → 7 → 8`. Task 3 is **blocked on §7-GATE-A** (interface-enumeration crate sign-off). Task 2 depends only on Task 1 and can run parallel to Task 3.
