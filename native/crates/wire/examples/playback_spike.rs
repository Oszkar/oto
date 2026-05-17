//! Throwaway v0.2 playback/read probe — NOT part of the product.
//!
//! Exercises the 6 commands + 4 reads from `sonos_api` 0.5.2 directly against
//! a real speaker so the v0.2 `Wire`/DTO surface can be built from measured
//! fact rather than guesswork.
//!
//! # Consumption path
//!
//! `sonos_sdk` (the umbrella crate already in oto-wire's `[dependencies]`) does
//! **not** re-export `SonosClient` or `services::av_transport` /
//! `services::rendering_control`.  A direct `sonos-api = "=0.5.2"` dev-dep is
//! therefore required in `oto-wire`'s `[dev-dependencies]` (see Cargo.toml).
//! All builder names come from `sonos-api-0.5.2/src/services/av_transport/operations.rs`
//! and `…/rendering_control/operations.rs` (the `pub use …_operation as …` aliases
//! at the bottom of each file).
//!
//! # Usage
//!
//! Run from the workspace root:
//!
//! ```text
//! cargo run -p oto-wire --example playback_spike -- <SPEAKER_IP>
//! ```
//!
//! Redirect stdout to a file and keep the full transcript for the findings doc:
//!
//! ```text
//! cargo run -p oto-wire --example playback_spike -- 192.168.1.X 2>&1 | tee docs/findings-playback-spike.txt
//! ```
//!
//! # Safety / non-destructiveness
//!
//! Execution order is read-first, then round-trip writes back to the read
//! value, then Pause→Play, then Next/Previous.  If the speaker is idle
//! (STOPPED), the Pause and Next/Previous calls will likely return a SOAP
//! fault — those errors are printed and the spike continues.  Nothing
//! permanent is changed.
//!
//! # Five questions this output must answer
//!
//! 1. Exact builder names/signatures + response field types incl. `InstanceID`.
//! 2. Does `sonos_api` decode `CurrentTrackMetaData` DIDL-Lite XML, or is it a
//!    raw string that oto-wire must parse?
//! 3. `ApiError` variant shapes → how to map them to oto-core errors.
//! 4. Volume range (is `desired_volume: u8` clamped 0–100? what does the device
//!    report for an over-range write?).
//! 5. Confirmed sync — no tokio runtime required.

// spike: dead_code is expected — the `print_result` helper and the
// `execute_enhanced` / `execute` branching are intentionally verbose.
#![allow(dead_code)]

use sonos_api::services::{av_transport, rendering_control};
use sonos_api::SonosClient;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Print the label, the raw Ok/Err tag, and the full Debug output.
fn print_result<T: std::fmt::Debug, E: std::fmt::Debug>(label: &str, result: &Result<T, E>) {
    match result {
        Ok(v) => {
            println!("\n[OK]  {label}");
            println!("{v:#?}");
        }
        Err(e) => {
            println!("\n[ERR] {label}");
            println!("{e:#?}");
        }
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() {
    let ip = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: playback_spike <SPEAKER_IP>");
        std::process::exit(1);
    });

    println!("=== oto v0.2 playback spike — target: {ip} ===");
    println!("(confirmed sync: no tokio runtime; this is a blocking std thread)");

    let client = SonosClient::new();

    // -----------------------------------------------------------------------
    // READS FIRST (non-destructive)
    // -----------------------------------------------------------------------

    // builder: rendering_control::get_volume("Master".to_string()).build()?
    // source:  sonos-api-0.5.2/src/services/rendering_control/operations.rs:400
    //          pub use get_volume_operation as get_volume;
    //          fn get_volume_operation(channel: String) -> OperationBuilder<GetVolumeOperation>
    // response type: GetVolumeResponse { current_volume: u8 }
    let get_vol_op = rendering_control::get_volume("Master".to_string())
        .build()
        .expect("get_volume build");
    let vol_result = client.execute_enhanced(&ip, get_vol_op);
    print_result("GetVolume(channel=Master)", &vol_result);
    let current_volume: u8 = match &vol_result {
        Ok(r) => r.current_volume,
        Err(_) => 20, // fallback so the write round-trip still runs
    };

    // builder: rendering_control::get_mute("Master".to_string()).build()?
    // source:  sonos-api-0.5.2/src/services/rendering_control/operations.rs:163
    //          pub use get_mute_operation as get_mute;
    //          fn get_mute_operation(channel: String) -> OperationBuilder<GetMuteOperation>
    // response type: GetMuteResponse { current_mute: bool }  (decoded from "0"/"1")
    let get_mute_op = rendering_control::get_mute("Master".to_string())
        .build()
        .expect("get_mute build");
    let mute_result = client.execute_enhanced(&ip, get_mute_op);
    print_result("GetMute(channel=Master)", &mute_result);
    let current_mute: bool = match &mute_result {
        Ok(r) => r.current_mute,
        Err(_) => false,
    };

    // builder: av_transport::get_transport_info().build()?
    // source:  sonos-api-0.5.2/src/services/av_transport/operations.rs:730
    //          pub use get_transport_info_operation as get_transport_info;
    // response type: GetTransportInfoResponse {
    //     current_transport_state: String,  (PLAYING/PAUSED_PLAYBACK/STOPPED/…)
    //     current_transport_status: String,
    //     current_speed: String,
    // }
    let get_ti_op = av_transport::get_transport_info()
        .build()
        .expect("get_transport_info build");
    let ti_result = client.execute_enhanced(&ip, get_ti_op);
    print_result("GetTransportInfo(InstanceID=0)", &ti_result);

    // builder: av_transport::get_position_info().build()?
    // source:  sonos-api-0.5.2/src/services/av_transport/operations.rs:722
    //          pub use get_position_info_operation as get_position_info;
    // response type: GetPositionInfoResponse {
    //     track: u32,
    //     track_duration: String,
    //     track_meta_data: String,   ← raw DIDL-Lite XML string (Q2: needs oto-wire parsing)
    //     track_uri: String,
    //     rel_time: String,
    //     abs_time: String,
    //     rel_count: i32,
    //     abs_count: i32,
    // }
    let get_pi_op = av_transport::get_position_info()
        .build()
        .expect("get_position_info build");
    let pi_result = client.execute_enhanced(&ip, get_pi_op);
    print_result("GetPositionInfo(InstanceID=0)", &pi_result);
    // Q2 probe: print the raw track_meta_data so we can see whether
    // the library decoded it or returned raw DIDL-Lite XML.
    if let Ok(ref pi) = pi_result {
        println!(
            "\n--- Q2 track_meta_data raw value (check for DIDL-Lite XML) ---\n{}",
            pi.track_meta_data
        );
    }

    // -----------------------------------------------------------------------
    // ROUND-TRIP WRITES (back to read value — net-zero effect)
    // -----------------------------------------------------------------------

    // builder: rendering_control::set_volume("Master".to_string(), desired_volume: u8).build()?
    // source:  sonos-api-0.5.2/src/services/rendering_control/operations.rs:402
    //          pub use set_volume_operation as set_volume;
    //          fn set_volume_operation(channel: String, desired_volume: u8) -> OperationBuilder<SetVolumeOperation>
    // validation: desired_volume > 100 → ValidationError::RangeError (Q4: range is 0–100, u8)
    // response: () (empty on success)
    let set_vol_op = rendering_control::set_volume("Master".to_string(), current_volume)
        .build()
        .expect("set_volume build");
    let set_vol_result = client.execute_enhanced(&ip, set_vol_op);
    print_result(
        &format!("SetVolume(channel=Master, desired_volume={current_volume})"),
        &set_vol_result,
    );

    // builder: rendering_control::set_mute("Master".to_string(), desired_mute: bool).build()?
    // source:  sonos-api-0.5.2/src/services/rendering_control/operations.rs:193
    //          pub use set_mute_operation as set_mute;
    //          fn set_mute_operation(channel: String, desired_mute: bool) -> OperationBuilder<SetMuteOperation>
    // Sonos wire encodes: desired_mute=true → "1", false → "0"
    // response: ()
    let set_mute_op = rendering_control::set_mute("Master".to_string(), current_mute)
        .build()
        .expect("set_mute build");
    let set_mute_result = client.execute_enhanced(&ip, set_mute_op);
    print_result(
        &format!("SetMute(channel=Master, desired_mute={current_mute})"),
        &set_mute_result,
    );

    // -----------------------------------------------------------------------
    // TRANSPORT COMMANDS (Pause then immediately Play to restore state)
    // -----------------------------------------------------------------------

    // builder: av_transport::pause().build()?
    // source:  sonos-api-0.5.2/src/services/av_transport/operations.rs:716
    //          pub use pause_operation as pause;
    //          fn pause_operation() -> OperationBuilder<PauseOperation>
    // payload: <InstanceID>0</InstanceID>  (macro-generated; InstanceID always 0)
    // response: ()
    // NOTE: will SOAP-fault with code 701 if transport is STOPPED — expected.
    let pause_op = av_transport::pause().build().expect("pause build");
    let pause_result = client.execute_enhanced(&ip, pause_op);
    print_result("Pause(InstanceID=0)", &pause_result);

    // builder: av_transport::play("1".to_string()).build()?
    // source:  sonos-api-0.5.2/src/services/av_transport/operations.rs:715
    //          pub use play_operation as play;
    //          fn play_operation(speed: String) -> OperationBuilder<PlayOperation>
    // speed: "1" is the standard value (Sonos ignores other speeds)
    // response: ()
    let play_op = av_transport::play("1".to_string())
        .build()
        .expect("play build");
    let play_result = client.execute_enhanced(&ip, play_op);
    print_result("Play(InstanceID=0, speed=\"1\")", &play_result);

    // -----------------------------------------------------------------------
    // NEXT / PREVIOUS (queue navigation — last, most disruptive)
    // -----------------------------------------------------------------------

    // builder: av_transport::next().build()?
    // source:  sonos-api-0.5.2/src/services/av_transport/operations.rs:714
    //          pub use next_operation as next;
    //          fn next_operation() -> OperationBuilder<NextOperation>
    // payload: <InstanceID>0</InstanceID>
    // response: ()
    let next_op = av_transport::next().build().expect("next build");
    let next_result = client.execute_enhanced(&ip, next_op);
    print_result("Next(InstanceID=0)", &next_result);

    // builder: av_transport::previous().build()?
    // source:  sonos-api-0.5.2/src/services/av_transport/operations.rs:717
    //          pub use previous_operation as previous;
    //          fn previous_operation() -> OperationBuilder<PreviousOperation>
    // response: ()
    let prev_op = av_transport::previous().build().expect("previous build");
    let prev_result = client.execute_enhanced(&ip, prev_op);
    print_result("Previous(InstanceID=0)", &prev_result);

    // -----------------------------------------------------------------------
    // Summary for Q3: ApiError shape
    // -----------------------------------------------------------------------
    println!("\n=== ApiError variant recap (Q3) ===");
    println!("ApiError variants from sonos-api-0.5.2/src/error.rs:");
    println!("  NetworkError(String)     — TCP/connect failure");
    println!("  ParseError(String)       — XML/response-parse failure");
    println!("  SoapFault(u16)           — device returned a SOAP fault code");
    println!("  InvalidParameter(String) — validation rejected a parameter");
    println!("  SubscriptionError(String)");
    println!("  DeviceError(String)");
    println!("\n=== spike done ===");
}
