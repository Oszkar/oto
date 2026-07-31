pub mod api;
// Not scanned by FRB (`rust_input: crate::api`), so nothing here reaches the
// bridge surface - it is the testable half of `api::subscribe_change_events`.
pub mod consumer;
mod frb_generated;
pub mod map;
