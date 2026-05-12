#![deny(unsafe_code)]

//! Core domain logic for the oto Sonos controller.
//!
//! Pure Rust, no FRB. Anything platform-facing lives in the parent
//! `oto_native` crate's `api` module.

pub mod greeting {
    pub fn greet(name: &str) -> String {
        format!("Hello, {name}!")
    }
}

#[cfg(test)]
mod tests {
    use super::greeting;

    #[test]
    fn greet_returns_expected_string() {
        assert_eq!(greeting::greet("world"), "Hello, world!");
    }
}
