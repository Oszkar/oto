#![deny(unsafe_code)]

//! Core domain logic for the oto Sonos controller.
//!
//! Pure Rust, no networking, no async, no third-party deps. The types defined
//! here are the lingua franca of the rest of the codebase: the FRB bridge
//! layer in `oto_native`, the discovery / SOAP / event layers (added later),
//! and (transitively, via FRB-generated bindings) the Dart UI.
//!
//! See `docs/ARCHITECTURE.md` § "The `Wire` seam" for the type surface
//! these support and `docs/sonos-notes.md` for the Sonos protocol details
//! they mirror (`SpeakerId`/`GroupId` identifier shapes, `Volume` range,
//! DIDL-Lite → `Track`, transport state strings → `PlaybackState`).

pub mod error;
pub mod events;
pub mod group;
pub mod identifiers;
pub mod identity;
pub mod speaker;
pub mod state;
pub mod track;
pub mod transport;
pub mod volume;
pub mod wire;

pub use error::Error;
pub use events::ChangeEvent;
pub use group::Group;
pub use identifiers::{GroupId, SpeakerId, TrackId};
pub use identity::{DiscoverySnapshot, GroupIdentity, SpeakerIdentity};
pub use speaker::Speaker;
pub use state::{SpeakerState, TrackPosition};
pub use track::Track;
pub use transport::{PlaybackState, TransportState};
pub use volume::Volume;
pub use wire::{Wire, WireError};
