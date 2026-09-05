# Reactive event spike: SDK 0.5.2

Historical comparison on a Windows host and four-speaker household, with two responsive players participating. This supports the choice of the SDK reactive stack, not acceptance of later SDK versions. Current integration rules live in [Sonos notes](../../sonos-notes.md#event-model).

## Result

Both paths delivered the exercised operator actions with sub-second latency and no observed errors. The SDK path was chosen because it already owned subscriptions, renewal, parsing, and change detection. The raw callback-server prototype omitted renewal, so its shorter run did not establish long-session reliability.

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

## Raw evidence

- SDK path: [idle](path-a-idle.log), [active](path-a-active.log).
- Raw callback-server path: [idle](path-b-idle.log), [active](path-b-active.log).

Event counts are not directly comparable: one raw NOTIFY bundles multiple properties, while the SDK also emits polling-derived position changes. The observed position cadence did not reproduce the suspected intermittent-update problem, but this was one LAN and one session.

Revisit a custom stack only if SDK reliability or maintenance warrants owning renewal, XML decoding, and change detection. The raw prototype logs document its behavior but are not a maintained implementation.
