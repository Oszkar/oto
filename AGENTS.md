# AGENTS.md — Operational Contract

Repo: `Oszkar/oto` | Branch: `main`
Agents: Claude Code, Copilot (PR review), and any other coding agent.

## 0. Prime Rule: Clarify Before Acting

If requirements are ambiguous, incomplete, or conflicting:

1. Stop.
2. Ask targeted questions.
3. Propose 1–3 concrete interpretations.
4. Wait for confirmation, **OR** proceed with the assumption stated
   explicitly — depending on impact.

**Calibration:**

- High-impact / hard-to-reverse (`oto-core` types, the `Wire` trait, the FRB command/event surface, the `sonos-sdk` pin, the own-SSDP / discovery logic, milestone boundaries) → **wait**.
- Low-impact / reversible (clippy fix, unit test, doc reword, non-breaking refactor inside one module) → **state the assumption and proceed**.
- When in doubt, wait.

## 1. System Context

oto = a fast, local-first Sonos controller for Windows and Android,
without the bloat of the official app. Flutter UI over a Rust core,
bridged with `flutter_rust_bridge` (FRB) v2; discovery / SOAP / event
logic delegated to [`tatimblin/sonos-sdk`](https://github.com/tatimblin/sonos-sdk).

This is an explicit **side project**. Optimize for usefulness, low maintenance, tight scope. Don't over-engineer for scale or a team. Bounded: once Stable (v1.0, externally tested), expect maintenance only.

Out of scope: cloud, Sonos accounts, the Sonos cloud API, multi-household, bonded-speaker modeling (v0.1), non-Win/Android release targets.

Authoritative docs: `docs/ARCHITECTURE.md` (system design — marks target vs. current), `README.md` (milestone ladder), `RELEASING.md` (versioning), `docs/plans/*` (point-in-time design + spike findings). Pre-1.0: most of the system is still planned.

## 2. Engineering Principles

Apply at all times:

- **YAGNI** — no speculative abstractions; don't add a crate/layer/feature because it "might be useful."
- **KISS** — simplest viable implementation.
- **DRY** — domain logic lives once (`oto-core`); the `sonos-sdk` adapter lives once (`oto-wire`).
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
| `sonos-sdk` | pinned **`=0.5.2`** (exact) — we use the `test-support`-gated `from_discovered_devices`, not semver-protected. Don't bump without re-checking that API + [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76) |
| FRB surface | `native/src/api.rs` is a thin shim (currently minimal — `greet`/`init_app`); **target:** sync commands return `Result`, events as a `Stream` pumped off `sonos-sdk`'s `ChangeIterator`. Extending the surface needs an ARCHITECTURE.md update first |
| Frontend | Flutter + Riverpod 3 (codegen); providers in `app/lib/src/state/` via `@riverpod`, consumed from `ConsumerWidget`. `app/pubspec.yaml` `version:` is the canonical project version |
| Generated source | FRB bindings (`app/lib/src/rust/`, `native/src/frb_generated*`) and `*.g.dart` are committed; regenerate with `just gen` after editing `native/src/api.rs` or any `@riverpod` provider |
| Lint floor | `just check` (fmt + clippy `-D warnings` + flutter analyze) and `just test` (cargo-nextest + flutter test) pass; `cargo deny check` clean |
| Android | minSdk 35, 64-bit only (cargokit locally patched — `LOCAL_PATCHES.md`), Java 21 |

## 3. Non-Negotiables

**LAN politeness.** The only thing being rate-limited is *us* against
the user's Sonos devices on a home network. `sonos-sdk` owns SOAP/GENA;
don't add aggressive polling on top. SSDP discovery is bounded and
interface-scoped (§4 / [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76)).

**Errors & logging.** `oto-core` stays deps-free: manual `Error` enum,
no `thiserror`, no `unwrap()` outside tests. `oto-wire`/`oto-app` may use
`anyhow` at boundaries and `tracing` for logs (never `log`; never
one-line-per-event at info). `sonos-sdk` construction/discovery failures
are retryable, not fatal.

**Legal.** oto controls the user's own Sonos devices on their LAN via
UPnP. Not affiliated with Sonos. Local-only — no cloud, account, or
scraping. If a device is unreachable, degrade gracefully; never
circumvent device controls.

**Secrets.** None in scope — no API keys, tokens, or credentials (local
LAN control only). Don't introduce a secret surface without raising it
first.

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

`oto-app` owns runtime state. For v0.1 that is the active `Wire` and
`discover` routing; v0.2 added playback/state command routing. v0.3
grows it to own `SonosSystem`, the `sonos_sdk`↔`oto_core` topology
mapping; v0.4 the event-pump threads.

### Architectural boundaries — agents must respect

1. **`oto-core` is pure.** Domain types only; no networking/async/deps.
   Other crates depend inward on it; it depends on nothing.
2. **`oto-wire` is the only crate that touches `sonos-sdk`.** It is the
   sole `sonos-sdk` integration point; **target:** runs its own
   multi-interface SSDP and builds the system via
   `SonosSystem::from_discovered_devices` (see `docs/ARCHITECTURE.md`;
   `sonos-sdk`'s `0.0.0.0` SSDP is broken on multi-NIC hosts —
   [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76)).
   Do not call `SonosSystem::new()`.
3. **`oto-mock` is the test `Wire` impl** — deterministic fixtures, no
   network; integration tests run without real Sonos.
4. **`oto-app` is the sole owner of runtime state** and the only place
   `sonos_sdk` types are translated to `oto_core` types.
5. **`oto_native` is glue only.** No business logic in
   `native/src/api.rs`; it delegates inward. Commands sync, events
   `Stream`.
6. **Frontend talks to the backend only via the FRB command/event
   surface.** Adding a command/event needs an ARCHITECTURE.md update
   first.

## 5. Quick Start for Agents

Every task: (1) identify the crate/layer; (2) list invariants affected
(§4 boundary, §2.1 convention); (3) smallest safe diff at the root
cause; (4) validate (§6); (5) ambiguous → ask early. Avoid drive-by
refactors. Use the context7 MCP to verify FRB / sonos-sdk / Riverpod
APIs rather than guessing.

Local dev (agents that can run commands), from the repo root:

```
just gen        # regen FRB + Riverpod codegen (after api.rs / @riverpod)
just check      # fmt + clippy -D warnings + flutter analyze
just test       # cargo-nextest + flutter test
just build-win  # debug Windows desktop
just build-apk  # debug Android APK
```

Network-dependent code (discovery) cannot be validated from a sandboxed
shell — SSDP multicast needs the real LAN. Say so and ask the user to
run it.

## 6. Validation Matrix

Before claiming work is done:

| Change touches | Required gates |
|---|---|
| any `native/**/*.rs` | `just check` + `just test` + `cargo deny check` |
| `native/src/api.rs` or any `@riverpod` provider | `just gen`; `dart scripts/verify_generated.dart` clean (CI enforces) |
| `app/lib/**` | `flutter analyze` + `flutter test`; UI verified manually in `flutter run` (from `app/`) |
| workspace `Cargo.toml` | `cargo check --workspace`; re-run `cargo deny check` if a dep changed |
| `.github/workflows/*` | YAML lints clean |
| `*.md` | internal links resolve; facts still match the code/justfile |

`clippy -D warnings` is strict; no `#[allow]` without a documented
reason in a comment above it. If you cannot run a gate, state the exact
command and ask for output — do not claim done.

## 7. Change Control

**Ask before:** changing `oto-core` types, the `Wire` trait, the FRB
surface, the `sonos-sdk` pin, adding a crate dependency, cross-crate
refactors, milestone-boundary changes, introducing any secret surface.

**Document:** assumptions, trade-offs, and load-bearing tech debt as
`// TODO(vX.Y):` with the eventual fix in one line.

**Branch & PR:** `main` is protected — never force-push to it. Branches
`feat/… fix/… docs/… chore/…`, one PR per branch, squash-merge,
conventional commit messages. `--force-with-lease` OK on feature
branches; `--force` is not. Never `--no-verify` / skip signing — fix the
hook. PRs go through review before merge.

**Doc sync:** if you change architecture, update `docs/ARCHITECTURE.md`
(source of truth for design) and `README.md` (milestone ladder)
together — drift between them is the most likely doc bug.

## 8. Communication

- Be concise; short bullets, concrete next steps.
- Ask targeted questions early; present 1–3 options with trade-offs.
- Push back on security risk, architectural violations, over-engineering, premature scope expansion (UI is v0.5 — not earlier, however easy it looks).
- Correct first, agreeable second. No busywork docs/status files unless asked.
- Persist until done or genuinely blocked; if blocked, say what you tried and what you need.
