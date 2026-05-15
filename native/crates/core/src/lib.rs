#![deny(unsafe_code)]

//! Core domain logic for the oto Sonos controller.
//!
//! Pure Rust, no networking, no async, no third-party deps. The types defined
//! here are the lingua franca of the rest of the codebase: the FRB bridge
//! layer in `oto_native`, the discovery / SOAP / event layers (added later),
//! and (transitively, via FRB-generated bindings) the Dart UI.
//!
//! See `docs/plans/2026-05-15-oto-core-domain-types-design.md` for the
//! shape of these types and the alternatives considered.

pub mod error;
pub mod group;
pub mod identifiers;
pub mod identity;
pub mod speaker;
pub mod track;
pub mod transport;
pub mod volume;
pub mod wire;

pub use error::Error;
pub use group::Group;
pub use identifiers::{GroupId, SpeakerId, TrackId};
pub use identity::{DiscoverySnapshot, GroupIdentity, SpeakerIdentity};
pub use speaker::Speaker;
pub use track::Track;
pub use transport::{PlaybackState, TransportState};
pub use volume::Volume;
pub use wire::{Wire, WireError};

/// Demo bridge target that proves the FRB pipeline. Removed in step 2/3 when
/// real Sonos plumbing replaces `greet` in `oto_native::api`.
pub mod greeting {
    pub fn greet(name: &str) -> String {
        format!("Hello, {name}!")
    }

    #[cfg(test)]
    mod tests {
        use super::greet;

        #[test]
        fn greet_returns_expected_string() {
            assert_eq!(greet("world"), "Hello, world!");
        }
    }
}
