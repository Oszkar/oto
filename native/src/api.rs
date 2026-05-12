use oto_core::greeting;

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    greeting::greet(&name)
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
