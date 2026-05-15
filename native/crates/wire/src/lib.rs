#![deny(unsafe_code)]

//! `oto-wire` — production wire layer backed by [`sonos_sdk`].
//!
//! Skeleton only. This crate pins `sonos-sdk` into the workspace build and
//! will house the adapter that maps `sonos_sdk` types onto `oto_core`
//! domain types behind the `Wire` trait. No network or protocol logic yet.
//!
//! See `docs/ARCHITECTURE.md` for the wire-layer design and the open
//! questions to validate when this is fleshed out.

/// Anchors the SDK's speaker identifier into this crate so the dependency
/// is exercised at compile time until the real adapter lands. Replaced by
/// the `Wire` impl and `sonos_sdk` ↔ `oto_core` translation in a later step.
pub type SdkSpeakerId = sonos_sdk::SpeakerId;

#[cfg(test)]
mod tests {
    #[test]
    fn sonos_sdk_resolves_and_links() {
        // A green run here means `sonos-sdk` resolves and builds on this
        // toolchain/platform — the point of this skeleton crate.
        fn _takes(_: Option<super::SdkSpeakerId>) {}
        _takes(None);
    }
}
