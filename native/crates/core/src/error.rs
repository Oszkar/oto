//! Domain-level errors for `oto-core`.
//!
//! Manual `Display` / `Error` impls keep the crate dependency-free.

use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// A volume value outside the supported `0..=100` range was supplied to
    /// [`crate::Volume::new`].
    InvalidVolume(u8),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::InvalidVolume(v) => {
                write!(f, "volume {v} is out of range (expected 0..=100)")
            }
        }
    }
}

impl std::error::Error for Error {}

#[cfg(test)]
mod tests {
    use super::Error;

    #[test]
    fn invalid_volume_display() {
        assert_eq!(
            Error::InvalidVolume(150).to_string(),
            "volume 150 is out of range (expected 0..=100)"
        );
    }
}
