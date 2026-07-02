/// Sentinel + resolver for value-object `copyWith` methods that must be able to
/// clear a nullable field to `null`. The common `field ?? this.field` idiom can
/// only set-or-keep, never clear; these let a `copyWith` distinguish "argument
/// omitted" from "explicitly set to null" without repeating the
/// `identical(x, keep) ? this.x : x as T` dance in every field of every model.
///
/// Usage: default each nullable parameter to [keep], then resolve it with
/// [orKeep]:
///
/// ```dart
/// RoomState copyWith({Object? volume = keep}) =>
///     RoomState(volume: orKeep(volume, this.volume));
/// ```
library;

/// Marker meaning "this `copyWith` argument was omitted" (keep the current
/// value). Distinct from `null`, which means "clear the field".
const Object keep = Object();

/// Resolve a [keep]-defaulted `copyWith` argument: returns [current] when
/// [value] was omitted, otherwise [value] cast to `T` (which may be `null`).
/// A wrong-typed argument fails fast with a clear `TypeError` at this single
/// site rather than at a cast duplicated across every field.
T orKeep<T>(Object? value, T current) =>
    identical(value, keep) ? current : value as T;
