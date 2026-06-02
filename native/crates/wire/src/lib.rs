#![deny(unsafe_code)]

//! `oto-wire` — production wire layer backed by `sonos-api` and own SSDP.
//!
//! Owns multi-NIC SSDP discovery and direct `sonos_api` SOAP calls
//! (ZoneGroupTopology for discovery/topology; AVTransport/RenderingControl
//! for playback and state), mapped onto `oto_core` domain types behind the
//! [`Wire`] trait.
//!
//! See `docs/ARCHITECTURE.md` for the wire-layer design.

pub mod adapter;
pub mod control;
pub(crate) mod device_description;
pub(crate) mod events;
pub mod ssdp;

pub use adapter::SonosWire;
