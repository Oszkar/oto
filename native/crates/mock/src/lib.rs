#![deny(unsafe_code)]

//! Mocked transport and speaker simulator for tests.
//!
//! Both Rust integration tests and Flutter integration tests should be
//! able to drive the same fake speaker fixtures from here.

pub fn placeholder() -> &'static str {
    "oto-mock placeholder"
}
