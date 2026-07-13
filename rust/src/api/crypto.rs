//! Nostr cryptography, backed by the `nostr` crate.
//!
//! This is the whole Rust surface the app is allowed to see: a handful of
//! functions, not a re-export of the SDK. Keeping it thin is deliberate —
//! it bounds the binary, and an upstream API change lands in one file
//! instead of across the Dart codebase.
//!
//! Phase 1 exposes only [`verify_event`], enough to prove the toolchain
//! links and runs. Keys, NIP-19 and signing arrive in Phase 3.

use nostr::prelude::*;

/// Whether `event_json` is a well-formed Nostr event whose id and Schnorr
/// signature both check out.
///
/// Returns `Err` only when the input does not parse as an event; an event
/// that parses but fails verification is `Ok(false)`.
#[flutter_rust_bridge::frb(sync)]
pub fn verify_event(event_json: String) -> Result<bool, String> {
    let event = Event::from_json(&event_json).map_err(|e| e.to_string())?;
    Ok(event.verify().is_ok())
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A real signed event: the id and signature must both hold.
    fn signed_event() -> String {
        let keys = Keys::generate();
        EventBuilder::text_note("choke")
            .sign_with_keys(&keys)
            .expect("signing a note with generated keys cannot fail")
            .as_json()
    }

    #[test]
    fn accepts_a_correctly_signed_event() {
        assert_eq!(verify_event(signed_event()), Ok(true));
    }

    #[test]
    fn rejects_an_event_whose_content_was_tampered_with() {
        // Flip the content after signing: the id no longer matches its event.
        let tampered = signed_event().replace(r#""content":"choke""#, r#""content":"choked""#);
        assert_eq!(verify_event(tampered), Ok(false));
    }

    #[test]
    fn errors_on_input_that_is_not_an_event() {
        assert!(verify_event("{\"not\":\"an event\"}".to_string()).is_err());
    }
}
