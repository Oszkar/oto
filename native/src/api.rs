use oto_core::greeting;

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    greeting::greet(&name)
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

use oto_app::discover as app_discover;
use oto_core::WireError;

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

impl From<WireError> for DiscoveryError {
    fn from(e: WireError) -> Self {
        match e {
            WireError::Network(m) => DiscoveryError::Network(m),
            WireError::NoDevicesFound => DiscoveryError::NoDevicesFound,
            WireError::Backend(m) => DiscoveryError::Sdk(m),
        }
    }
}

// TODO(v0.4): Android release discovery needs a held WifiManager.MulticastLock
// (perms are declared in app/android/app/src/main/AndroidManifest.xml); SSDP
// multicast is dropped without it. v0.1 discovery is verified on Windows via
// this bridge.
/// Deferred warm-up. Blocking ~3–5 s; FRB runs it off the UI isolate.
/// NOT on the #[frb(init)] path. Identity-only snapshot.
pub fn discover() -> Result<Topology, DiscoveryError> {
    let snap = app_discover()?;
    Ok(Topology {
        speakers: snap
            .speakers
            .into_iter()
            .map(|s| DiscoveredSpeaker {
                id: s.id.to_string(),
                room_name: s.room_name,
                model: s.model,
                ip: s.ip.to_string(),
            })
            .collect(),
        groups: snap
            .groups
            .into_iter()
            .map(|g| DiscoveredGroup {
                id: g.id.to_string(),
                coordinator: g.coordinator.to_string(),
                members: g.members.iter().map(|m| m.to_string()).collect(),
            })
            .collect(),
    })
}

// TODO(v0.2): remove the `greet` demo bridge target.
