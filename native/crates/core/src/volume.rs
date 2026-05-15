//! Speaker volume — a validated newtype over `u8` constrained to `0..=100`.

use std::fmt;

use crate::error::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Volume(u8);

impl Volume {
    /// Minimum (silent).
    pub const MIN: Volume = Volume(0);

    /// Maximum.
    pub const MAX: Volume = Volume(100);

    /// Construct, returning [`Error::InvalidVolume`] for values outside
    /// `0..=100`.
    pub fn new(v: u8) -> Result<Self, Error> {
        if v > 100 {
            Err(Error::InvalidVolume(v))
        } else {
            Ok(Self(v))
        }
    }

    /// Construct, clamping out-of-range inputs into `0..=100`. Useful at the
    /// SOAP-parsing boundary where the wire side can report stale or
    /// platform-specific values.
    pub fn clamped(v: i32) -> Self {
        Self(v.clamp(0, 100) as u8)
    }

    /// Borrow the underlying `u8`.
    pub fn get(self) -> u8 {
        self.0
    }
}

impl fmt::Display for Volume {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[cfg(test)]
mod tests {
    use super::Volume;
    use crate::error::Error;

    #[test]
    fn new_accepts_in_range() {
        for v in [0u8, 1, 50, 100] {
            assert_eq!(Volume::new(v).unwrap().get(), v);
        }
    }

    #[test]
    fn new_rejects_out_of_range() {
        for v in [101u8, 150, 255] {
            assert_eq!(Volume::new(v), Err(Error::InvalidVolume(v)));
        }
    }

    #[test]
    fn clamped_clamps_below_zero() {
        assert_eq!(Volume::clamped(-5).get(), 0);
        assert_eq!(Volume::clamped(i32::MIN).get(), 0);
    }

    #[test]
    fn clamped_clamps_above_max() {
        assert_eq!(Volume::clamped(200).get(), 100);
        assert_eq!(Volume::clamped(i32::MAX).get(), 100);
    }

    #[test]
    fn clamped_passes_in_range() {
        assert_eq!(Volume::clamped(0).get(), 0);
        assert_eq!(Volume::clamped(50).get(), 50);
        assert_eq!(Volume::clamped(100).get(), 100);
    }

    #[test]
    fn min_and_max_constants() {
        assert_eq!(Volume::MIN.get(), 0);
        assert_eq!(Volume::MAX.get(), 100);
    }

    #[test]
    fn display_renders_inner_value() {
        assert_eq!(Volume::new(42).unwrap().to_string(), "42");
    }

    #[test]
    fn ordering() {
        assert!(Volume::new(50).unwrap() < Volume::new(60).unwrap());
        assert!(Volume::MIN < Volume::MAX);
    }
}
