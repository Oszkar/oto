# Design system

The oto visual language: what it is, where it lives now, and the durable rules
that outlived the original prototype.

## Source of truth

The design tokens are **Dart, in the app** - not a separate spec file:

| Concern | Canonical location |
| --- | --- |
| Spacing, radius, type scale, elevation | [`app/lib/src/theme/tokens.dart`](../../app/lib/src/theme/tokens.dart) |
| Colour roles (inks, fills, lines, status, accent) | [`app/lib/src/theme/oto_colors.dart`](../../app/lib/src/theme/oto_colors.dart) |
| `ThemeData` assembly (Material mapping) | [`app/lib/src/theme/oto_theme.dart`](../../app/lib/src/theme/oto_theme.dart) |
| Accent swatches (teal default + indigo/amber/slate) | [`app/lib/src/theme/accent.dart`](../../app/lib/src/theme/accent.dart) |

There is deliberately **no JSON token file and no codegen pipeline**: two themes
and one consumer don't warrant it (KISS/YAGNI). Change a token in the Dart above
and the app follows; nothing else to keep in sync.

The living, hot-reloadable view of screens and states is the **showcase**:

```
cd app && flutter run -t lib/showcase/main.dart
```

It renders every screen and presentation state against fixture data, with
brightness / accent / layout toggles - the replacement for the old static
prototype.

## Brand assets (`brand/`)

The only non-code design artefacts kept in this directory. Consumed live -
e.g. the README logo and the app icon derive from these.

- `oto-mark*.svg`, `oto-mark-512.png`, `oto-icon-512.png` - the mark.
- `oto-lockup-{black,white}.svg` - wordmark lockups. **Outline the Geist
  wordmark before sending to any external vendor** (the lockups reference the
  live font).
- `favicon-{16,32,48}.png`, `apple-touch-icon-180.png` - web/app icons.

## Durable rules (behaviour the pixels didn't convey)

These are product invariants, not styling preferences. Most are already enforced
in code; kept here as the rationale.

### The source model

The core abstraction is a **source**, not a speaker. A source is either a
**group of rooms playing in sync** or a **single room** on its own.

- **Transport (play / pause / skip / shuffle / repeat) is per-source** -
  group-wide. To play something different in one room, ungroup it first.
- **Volume is per-room** (the exception); a group also has a **group master**
  that moves all members proportionally.
- Now-playing surfaces are **derived from room state**, never hand-authored -
  `sourcesFromRooms` is the single guardrail (a screen can't claim a different
  source count than its rooms imply). See
  [`app/lib/src/state/sources.dart`](../../app/lib/src/state/sources.dart).
- Idle / powered-off rooms are not sources.

### Colour & type

- The four inks (`ink` / `ink2` / `inkMute` / `inkFaint`) are **one base colour
  at descending alpha**, not four hand-picked hexes.
- **`inkFaint` is decorative only** - never load-bearing text. Meta/caption text
  uses `inkMute` (AA-passing).
- Two themes only: light + dark. Dark is a true dark (`#0e0e10`), not a tint.
- **Accent** is user-selectable; `accentSoft` is the accent at low alpha for
  badges/pills (pre-resolved - no runtime colour-mix).

### Accessibility

- **44 px minimum touch target** everywhere (transparent hit-slop around smaller
  glyphs is fine - keep it with `InkResponse` / min `Size`, don't shrink to the
  visible glyph).

## History

This directory once held the pre-implementation prototype: a React/JSX hi-fi
mock (`hifi-*.jsx`, `design-canvas.jsx`), an HTML v3 comp, a platform-neutral
`design-tokens.json`, and a `HANDOFF.md`. They were faithful design-time
scaffolding for the v0.6 UI and have all been translated into the Flutter app,
so they were retired once they began to drift from (and under-describe) the
shipped, backend-true UI. Recover any of them from git history if needed
(`git log -- docs/design-system/`).
