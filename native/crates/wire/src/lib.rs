#![deny(unsafe_code)]

//! `oto-wire` — production wire layer backed by [`sonos_sdk`].
//!
//! Owns SSDP discovery, device-description fetching, and the mapping from
//! `sonos_sdk` types onto `oto_core` domain types behind the [`Wire`] trait.
//!
//! See `docs/ARCHITECTURE.md` for the wire-layer design.

pub mod adapter;
pub mod http;
pub mod ssdp;

pub use adapter::SonosWire;
