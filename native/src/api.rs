use oto_app::discover as app_discover;
use oto_core::greeting;

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    greeting::greet(&name)
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub struct Topology {
    pub speakers: Vec<DiscoveredSpeaker>,
    pub groups: Vec<DiscoveredGroup>,
}

pub struct DiscoveredSpeaker {
    pub id: String,
    pub room_name: String,
    pub model: Option<String>,
    pub ip: String,
}

pub struct DiscoveredGroup {
    pub id: String,
    pub coordinator: String,
    pub members: Vec<String>,
}

pub enum DiscoveryError {
    Network(String),
    NoDevicesFound,
    Sdk(String),
}

// TODO(v0.4): Android release discovery needs a held WifiManager.MulticastLock
// (perms are declared in app/android/app/src/main/AndroidManifest.xml); SSDP
// multicast is dropped without it. v0.1 discovery is verified on Windows via
// this bridge.
/// Deferred warm-up. Blocking ~3–5 s; FRB runs it off the UI isolate.
/// NOT on the #[frb(init)] path. Identity-only snapshot.
pub fn discover() -> Result<Topology, DiscoveryError> {
    // Glue only: delegate inward, then the representational map (tested
    // LAN-free in `native/tests/`; see `crate::map`).
    let snap = app_discover().map_err(crate::map::to_discovery_error)?;
    Ok(crate::map::to_topology(snap))
}

// TODO(v0.2): remove the `greet` demo bridge target.
