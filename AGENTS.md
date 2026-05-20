# AGENTS.md — Operational Contract

Repo: `Oszkar/oto` | Branch: `main` Agents: Claude Code, Copilot (PR review), Codex, and any other coding agent.

## 0. Prime Rule: Clarify Before Acting

If requirements are ambiguous, incomplete, or conflicting:

1. Stop.
2. Ask targeted questions.
3. Propose 1–3 concrete interpretations.
4. Wait for confirmation, **OR** proceed with the assumption stated explicitly — depending on impact.

**Calibration:**

- High-impact / hard-to-reverse (`oto-core` types, the `Wire` trait, the FRB command/event surface, the `sonos-api` pin, the own-SSDP / discovery logic, milestone boundaries) → **wait**.
- Low-impact / reversible (clippy fix, unit test, doc reword, non-breaking refactor inside one module) → **state the assumption and proceed**.
- When in doubt, wait.

## 1. System Context

oto = a fast, local-first Sonos controller for Windows and Android, without the bloat of the official app. Flutter UI over a Rust core, bridged with `flutter_rust_bridge` (FRB) v2; discovery / SOAP via the `sonos-api` crate (from the [`tatimblin/sonos-sdk`](https://github.com/tatimblin/sonos-sdk) family) plus oto's own multi-NIC SSDP; events are v0.4.

This is a **side project**. Optimize for usefulness, low maintenance, tight scope. Don't over-engineer for scale or a team. Bounded: once Stable (v1.0, externally tested), expect maintenance only.

Out of scope: cloud, Sonos accounts, the Sonos cloud API, multi-household.

Authoritative docs: `docs/ARCHITECTURE.md` (system design — marks target vs. current), `README.md` (incl. milestone ladder), `RELEASING.md` (versioning).

## 2. Engineering Principles

Apply at all times:

- **YAGNI** — no speculative abstractions; don't add a crate/layer/feature because it "might be useful."
- **KISS** — simplest viable implementation.
- **DRY** — domain logic lives once (`oto-core`); the `sonos-api` adapter lives once (`oto-wire`).
- **PoLP** — least privilege; one crate owns each external surface (§4).
- **Local-first** — core logic has no network/async/third-party deps; nothing reaches the LAN except the wire layer.
- **MVP bias** — solo dev; ship the milestone, record tech debt as `// TODO(vX.Y):`, don't gold-plate.

Correctness > Cleverness · Simplicity > Flexibility · Precision > Agreeability

### 2.1 Conventions

| Concern | Convention |
|---|---|
| Rust edition / MSRV | 2021 / 1.94 (workspace `Cargo.toml`); CI pins toolchain `1.94.0` |
| Workspace | one Cargo workspace at `native/`; root `oto_native` cdylib + `crates/{core,wire,mock}`; shared deps via `[workspace.dependencies]` |
| `oto-core` | pure: no networking/async/third-party deps; typed newtypes; manual `Error` enum (no `thiserror`); `#![deny(unsafe_code)]` |
| `sonos-api` | pinned **`=0.5.2`** (exact) — direct UPnP SOAP (ZoneGroupTopology / AVTransport / RenderingControl); `oto-wire`'s only sonos dep. The `sonos-sdk` umbrella was dropped at v0.3 (Open Q5). Don't bump without re-checking the SOAP surface + the multi-NIC SSDP issue [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76) |
| FRB surface | `native/src/api.rs` is a thin shim (currently minimal — `greet`/`init_app`); **target:** sync commands return `Result`, events as a `Stream` (v0.4; `sonos-api` event path per ARCHITECTURE Open Q7). Extending the surface needs an ARCHITECTURE.md update first |
| Frontend | Flutter + Riverpod 3 (codegen); providers in `app/lib/src/state/` via `@riverpod`, consumed from `ConsumerWidget`. `app/pubspec.yaml` `version:` is the canonical project version |
| Generated source | FRB bindings (`app/lib/src/rust/`, `native/src/frb_generated*`) and `*.g.dart` are committed; regenerate with `just gen` after editing `native/src/api.rs` or any `@riverpod` provider |
| Lint floor | `just check` (gen-check + fmt + clippy `-D warnings` + flutter analyze + cargo deny) and `just test` (cargo-nextest + flutter test) pass |
| Android | minSdk 35, 64-bit only (cargokit locally patched — `LOCAL_PATCHES.md`), Java 21 |

## 3. Non-Negotiables

**LAN politeness.** The only thing being rate-limited is *us* against the user's Sonos devices on a home network. `sonos-api` owns SOAP; don't add aggressive polling on top. SSDP discovery is bounded and interface-scoped (§4 / [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76)).

**Errors & logging.** `oto-core` stays deps-free: manual `Error` enum, no `thiserror`, no `unwrap()` outside tests. `oto-wire`/`oto-app` may use `anyhow` at boundaries and `tracing` for logs (never `log`; never one-line-per-event at info). Discovery / `sonos-api` SOAP failures are retryable, not fatal.

**Legal.** oto controls the user's own Sonos devices on their LAN via UPnP. Not affiliated with Sonos. Local-only — no cloud, account, or scraping. If a device is unreachable, degrade gracefully; never circumvent device controls.

**Secrets.** None in scope — no API keys, tokens, or credentials (local LAN control only). Don't introduce a secret surface without raising it first.

## 4. Repo Map

```
oto/
├── README.md  CONTRIBUTING.md  RELEASING.md  CHANGELOG.md  LICENSE(MIT)
├── justfile / Makefile          mirrored dev recipes
├── docs/ARCHITECTURE.md         system design (target vs current marked)
├── docs/plans/                  point-in-time design + spike findings
├── app/                         Flutter app (Android + Windows)
│   ├── lib/  lib/src/state/  lib/src/rust/(generated)
│   ├── rust_builder/            Cargokit shim (patched; LOCAL_PATCHES.md)
│   └── pubspec.yaml             canonical version
├── native/                      Rust workspace
│   ├── Cargo.toml               workspace root + oto_native cdylib (FRB)
│   ├── src/api.rs               FRB surface — thin, delegate inward
│   └── crates/{core,wire,mock,app}
└── .github/workflows/           ci.yml + build.yml
```

`oto-app` owns runtime state. v0.1: the active `Wire` + `discover` routing; v0.2 added playback/state command routing; v0.3 routes group-addressed commands over real ZoneGroupTopology (the `sonos-api`↔`oto_core` mapping lives in `oto-wire`, never via `SonosSystem` — Open Q1/Q5); v0.4 adds the event-pump threads.

### Architectural boundaries — agents must respect

1. **`oto-core` is pure.** Domain types only; no networking/async/deps. Other crates depend inward on it; it depends on nothing.
2. **`oto-wire` is the only crate that touches `sonos-api`.** Sole `sonos-api` integration point: runs its own multi-interface SSDP and reads topology / playback / state via direct `sonos-api` SOAP (ZoneGroupTopology / AVTransport / RenderingControl) — **never** `SonosSystem` (the `sonos-sdk` umbrella was dropped at v0.3, Open Q5; its topology layer was hardware-proven lazy / non-deterministic, Open Q1). `sonos-sdk-discovery`'s `0.0.0.0` SSDP is broken on multi-NIC hosts ([`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76)) — which is why `oto-wire` owns SSDP.
3. **`oto-mock` is the test `Wire` impl** — deterministic fixtures, no network; integration tests run without real Sonos.
4. **`oto-app` is the sole owner of runtime state** and the only place `sonos-api` types are translated to `oto_core` types.
5. **`oto_native` is glue only.** No business logic in `native/src/api.rs`; it delegates inward. Commands sync, events `Stream`.
6. **Frontend talks to the backend only via the FRB command/event surface.** Adding a command/event needs an ARCHITECTURE.md update first.

## 5. Quick Start for Agents

Every task: (1) identify the crate/layer; (2) list invariants affected (§4 boundary, §2.1 convention); (3) smallest safe diff at the root cause; (4) validate (§6); (5) ambiguous → ask early. Avoid drive-by refactors. Use the context7 MCP to verify FRB / sonos-api / Riverpod APIs rather than guessing.

Local dev (agents that can run commands), from the repo root:

```
just gen        # regen FRB + Riverpod codegen (after api.rs / @riverpod)
just check      # gen-check + fmt + clippy -D warnings + flutter analyze + cargo deny
just test       # cargo-nextest + flutter test
just build-win  # debug Windows desktop
just build-apk  # debug Android APK
```

Network-dependent code can be validated from an agent shell on a LAN with 4 Sonos devices. State explicitly when running network-dependent experiments or checks. Hardware-gated tests live under `native/crates/wire/tests/live_*.rs` behind the `live-tests` Cargo feature (and `#[ignore]` belt-and-braces); run via `cargo nextest run -p oto-wire --features live-tests --run-ignored ignored-only`.

## 6. Validation Matrix

Before claiming work is done:

| Change touches | Required gates |
|---|---|
| any `native/**/*.rs` | `just check` + `just test` (gen-check + cargo-deny are folded into `check`) |
| `native/src/api.rs` or any `@riverpod` provider | `just gen` then `just check` (gen-check covers `verify_generated.dart`; CI enforces) |
| `app/lib/**` | `just check` + `flutter test`; UI verified manually in `flutter run` (from `app/`) |
| workspace `Cargo.toml` | `cargo check --workspace` then `just check` (deny is part of `check`) |
| `.github/workflows/*` | YAML lints clean |
| `*.md` | internal links resolve; facts still match the code/justfile |

`clippy -D warnings` is strict; no `#[allow]` without a documented reason in a comment above it. If you cannot run a gate, state the exact command and ask for output — do not claim done.

## 7. Change Control

**Ask before:** changing `oto-core` types, the `Wire` trait, the FRB surface, the `sonos-api` pin, adding a crate dependency, cross-crate refactors, milestone-boundary changes, introducing any secret surface.

**Document:** assumptions, trade-offs, and load-bearing tech debt as `// TODO(vX.Y):` with the eventual fix in one line.

**Branch & PR:** `main` is protected. Branches `feat/… fix/… docs/… chore/…`, one PR per branch, squash-merge, conventional commit messages. `--force-with-lease` OK on feature branches; `--force` is not. Never `--no-verify` / skip signing — fix the hook. PRs go through review before merge.

**Doc sync:** if you change architecture, update `docs/ARCHITECTURE.md` (source of truth for design) and `README.md` together — drift between them is the most likely doc bug.

## 8. Communication

- Be concise; short bullets, concrete next steps.
- Ask targeted questions early; present 1–3 options with trade-offs.
- Push back on security risk, architectural violations, over-engineering.
- Correct first, agreeable second. No busywork docs/status files unless asked.
- Persist until done or genuinely blocked; if blocked, say what you tried and what you need.
