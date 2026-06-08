# oto — controller handoff notes

Companion to the v3 prototype (`Sonos Controller v3.html`) and `handoff/design-tokens.json`.
Target: **Flutter**. This doc captures the **behavioural rules and model** that pixels alone don't convey — read it before implementing.

---

## 1. The source model (most important)

The app's core abstraction is a **source**, not a speaker.

- A **source** = one independent audio stream. It is either a **group of rooms playing in sync**, or a **single room** on its own.
- **Transport (play / pause / skip / shuffle / repeat) is per-source — group-wide.** Pausing any member of a group pauses the whole source. To play something different in one room, you **ungroup** it first.
- **Volume is the exception: it is per-room.** A group additionally has a **group master** volume (moves all members proportionally).
- Idle and powered-off rooms are **not** sources.

### Derivation rule (don't hand-author state)
The "now playing" surfaces are **derived from room state**, never set independently. In the prototype this is `sourcesFromRooms(rooms)`. A screen must never be able to claim a different number of sources than its rooms imply. Reproduce this as a single selector/computed in Flutter — it's the guardrail that prevents the invalid states we hit during design.

---

## 2. Surfaces & where transport lives

| Surface | Scope | Controls |
|---|---|---|
| **Room card / stack row** (Home) | one room | **start/stop that room** (the only way to start an *idle* room) + **per-room volume**. No skip/prev. |
| **Merged group card** | one group = one source | shared now-playing + **one** group transport; **group master volume** + nested **per-room** levels (capped at 4 + "N more → Room detail"). |
| **Bottom strip / floating bar** | all active sources | one row per source; grows upward; per-source play/pause; row taps through to that source's Now Playing. Caps at 3 + "N more". |
| **Now Playing** | one source | full transport. Reached from the bottom strip. |
| **Queue** | one source | reached only from Now Playing. |

The redundancy between a room's play button and the bottom strip is intentional and conventional (list item + bottom bar). The room button's unique job is **starting idle rooms**, which the strip can't do.

---

## 3. Navigation
- **Home** is the hub. Two layouts (Cards / Stack) toggled in the header — same data, user preference, persist it.
- **Settings** = gear in the Home header. System/network/user prefs only — **no audio settings** (those live per-room in Room detail / Sound).
- **Group editor** opens from the Home group affordance; **Room detail** from tapping a room.
- Search and the multi-source "manage all" / source-switcher destinations are **not yet designed** (see Open items).

---

## 4. Tokens & theming
- All color/type/space/radius values are in `handoff/design-tokens.json`, resolved to concrete values.
- **ink/ink2/inkMute/inkFaint are one ink color at descending alpha** — implement as `base.withOpacity(a)`, not four hex constants.
- **`inkFaint` is decorative only** — never use it for text a user must read (we bumped several violations during review; don't reintroduce them).
- **Accent** is user-selectable (teal default, + indigo/amber/slate). `accentSoft` is the accent at low alpha for badges/pills — pre-resolved in the token file (no `color-mix`).
- Two themes only: light + dark. Dark is a true dark (`#0e0e10` bg), not a tint.

## 5. Accessibility baked in
- **44px minimum touch target** everywhere (transparent hit-slop around smaller glyphs — keep this in Flutter with `InkResponse`/min `Size`, don't shrink to the visual glyph).
- Meta text uses `inkMute` (AA-passing), not `inkFaint`.
- Clickable rows in the prototype are `<div>`s with no roles/focus — **add semantics** (`Semantics`, focus, labels) in Flutter; that layer was out of scope for the visual prototype.

---

## 6. Cleanup / cruft to resolve at handoff
- **Naming:** files and `<title>` still say "Sonos Controller". The product is **oto**; "Sonos" should appear only as a factual interop reference, not as the app name. Trademarked feature terms were genericized earlier (e.g. "Sonosnet" → "Local network"); **"TruePlay"** is still pending a genericize-or-clear decision.
- **`V3_SOURCES`** (in `hifi-unified.jsx`) is a hand-authored sources array still referenced by one state screen in `hifi-states.jsx`. Everywhere else now derives from rooms — fold that last screen onto `sourcesFromRooms` and delete the literal.
- The prototype renders **static states** across artboards (no live group expand/collapse, source switching, or tap-through). That's intentional for a design prototype — interactions are specified here in prose for the Flutter build.

## 7. Open design items (not yet designed — decide before/with build)
- **Search** — icon + field exist; no results or empty state.
- **Source switcher / "manage all"** — the bottom strip's "+N more" has no destination sheet.
- **Settings sub-screens** — Devices, Network, etc. are chevron rows with no detail pages (decide custom vs. native pickers).
- **Group card details** — cap count (currently 4), whether the title carries the count, and where **ungroup** lives.
- **TruePlay** trademark (see §6).

---

## Assets
- Brand mark + lockups (SVG), 512px PNG, app icon, favicons: `brand/` — see `oto Brand Mark.html`.
- Wordmark in the lockups references live Geist; **outline before sending to external vendors.**
