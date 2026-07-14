//! The relay transport, backed by `nostr-sdk`'s relay pool.
//!
//! Thin on purpose, and shaped by the Dart interface above it
//! (`NostrRelayBackend`): connect, subscribe, publish to **one** relay and
//! report what *that relay* said. Reliability — the outbox, per-relay
//! convergence, the resend sweep — stays in Dart, where it was won (PRs #77,
//! #78). This module must never quietly acquire an opinion about any of it.
//!
//! The one thing worth understanding here is [`relay_publish`]: it asks a
//! single relay to take the event and reports whether **that** relay accepted.
//! `nostr-sdk`'s relay handle hands us that verdict structured — an `OK: false`
//! surfaces as its own error, distinct from a socket that simply never answered
//! — precisely what the hand-rolled transport had to grow OK-tracking to learn.
//! Flattening it back into a pool-wide "it worked" would resurrect the
//! stale-scoreboard bug.

use std::sync::OnceLock;

use nostr_sdk::prelude::*;
use tokio::sync::broadcast;

use crate::api::crypto::{to_event, to_signed_data, SignedEventData};
use crate::frb_generated::StreamSink;

/// One pool for the process. The app has exactly one identity and one set of
/// relays; handing Dart an opaque handle to pass back and forth would buy
/// nothing but ceremony.
static CLIENT: OnceLock<Client> = OnceLock::new();

fn client() -> &'static Client {
    CLIENT.get_or_init(Client::default)
}

/// Relay status changes, fanned into one channel.
///
/// `nostr-sdk` reports status per relay, not pool-wide, so each relay's
/// notifications are forwarded here as it is added.
///
/// Both directions are reported, not just connections. The caller keeps its own
/// view of who is up — it has to, because it decides where to publish — and a
/// stream that only ever said "connected" would leave that view drifting
/// permanently optimistic: it would keep publishing into a relay that left.
static STATUS: OnceLock<broadcast::Sender<RelayStatusData>> = OnceLock::new();

fn status_tx() -> &'static broadcast::Sender<RelayStatusData> {
    STATUS.get_or_init(|| broadcast::channel(64).0)
}

/// A relay went up, or went down.
#[derive(Clone)]
pub struct RelayStatusData {
    pub url: String,
    pub connected: bool,
}

/// A NIP-01 `REQ` filter. Empty vectors and `None` mean "unconstrained" — the
/// same shape the Dart `Filter` has, so the mapping stays honest.
pub struct FilterData {
    pub kinds: Vec<u16>,
    pub authors: Vec<String>,
    pub ids: Vec<String>,
    pub since: Option<i64>,
    pub until: Option<i64>,
    pub limit: Option<u32>,
}

/// Register a relay with the pool and dial it.
pub async fn relay_add(url: String) -> Result<(), String> {
    client().add_relay(&url).await.map_err(|e| e.to_string())?;

    // Watch this relay's status so the caller learns when it (re)connects.
    let relay = client().relay(&url).await.map_err(|e| e.to_string())?;
    let mut notifications = relay.notifications();
    let relay_url = url.clone();
    tokio::spawn(async move {
        loop {
            match notifications.recv().await {
                Ok(RelayNotification::RelayStatus { status }) => {
                    // No receivers yet is not an error: Dart may not have
                    // opened the stream, and the relay's status is what it is
                    // regardless.
                    let _ = status_tx().send(RelayStatusData {
                        url: relay_url.clone(),
                        connected: status == RelayStatus::Connected,
                    });
                }
                Ok(_) => {}
                // Fell behind and skipped notifications. `while let Ok` here
                // used to KILL the watcher — and a dead watcher is a Dart-side
                // connection view frozen until the process restarts. Report
                // the status we may have skipped past, and keep watching.
                Err(broadcast::error::RecvError::Lagged(_)) => {
                    let _ = status_tx().send(RelayStatusData {
                        url: relay_url.clone(),
                        connected: relay.status() == RelayStatus::Connected,
                    });
                }
                // The relay was removed from the pool; the watch is over.
                Err(broadcast::error::RecvError::Closed) => break,
            }
        }
    });

    // Connect this relay alone, so adding one later does not disturb the rest.
    client()
        .connect_relay(&url)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub async fn relay_remove(url: String) -> Result<(), String> {
    client().remove_relay(&url).await.map_err(|e| e.to_string())
}

/// Connect every registered relay.
pub async fn relay_connect() {
    client().connect().await;
}

pub async fn relay_disconnect() {
    client().disconnect().await;
}

/// Drop every socket and dial again.
///
/// The pool reconnects on its own eventually, but "eventually" is measured in
/// TCP timeouts. When the app resumes we already know the sockets are suspect —
/// the OS kills them without a close frame — and the referee's next tap must
/// not wait for the kernel to work that out.
///
/// ## Why this rebuilds the relays instead of calling disconnect + connect
///
/// `nostr-sdk` 0.44's revival races its own teardown, and losing that race
/// **strands the relay permanently**. `disconnect()` stores a termination
/// permit (a tokio `Notify`) and returns with the status already `Terminated`;
/// `connect()` then flips it to `Pending` and spawns a task — which sees the
/// OLD task still registered and declines. The old task meanwhile wakes from
/// `connect_and_run`, reads `Pending` (not terminated, so it keeps going),
/// marks the relay `Disconnected`, and dies in its backoff sleep by consuming
/// the stored permit. End state: status `Disconnected`, **no task**, and
/// `connect()` is a no-op on `Disconnected` — nothing dials again until the
/// process restarts. That is the app's "no connection until I kill it" bug,
/// reproduced by the `resume never strands the transport` drill.
///
/// Nudging stragglers back to life with more disconnect/connect pairs just
/// re-enters the same race (the drill stayed red under a 20-round nudge loop).
/// The only sequence that cannot lose it is the one with no revival in it at
/// all: **remove the relay and add it back**. A removed relay's watcher ends
/// (its channel closes), and `relay_add` builds a fresh `Relay` — new `Notify`
/// with no stored permit, no zombie task, a new watcher — and dials. Pool
/// subscriptions survive by design: a newly added relay inherits them
/// (`nostr-relay-pool` inherits pool subscriptions on `add_relay`).
pub async fn relay_reconnect_all() {
    let urls = relay_urls().await;

    for url in &urls {
        let _ = client().remove_relay(url).await;
    }
    for url in urls {
        // Re-registers the status watcher too. If an add fails outright the
        // relay is gone from the pool; the caller's own relay list still holds
        // it, and the next resume retries the add.
        let _ = relay_add(url).await;
    }
}

/// Publish to **one** relay and report that relay's verdict.
///
/// `true` = this relay accepted it. `false` = it rejected it (rate limits, an
/// invalid event, policy). `Err` = we never heard from it at all.
///
/// Publishing one relay at a time, rather than fanning out inside the pool, is
/// deliberate: the caller's convergence bookkeeping is per relay, and a
/// pool-level "it worked" would flatten exactly the distinction that matters.
pub async fn relay_publish(url: String, event: SignedEventData) -> Result<bool, String> {
    let event = to_event(&event)?;

    // Send to this one relay and wait for its verdict. Going through the relay
    // directly, rather than the pool's `send_event_to`, is what keeps that
    // verdict *structured*: the pool flattens every per-relay failure into an
    // opaque string in `Output.failed`, so a dead socket and an explicit `OK
    // false` would arrive indistinguishable — and collapsing "never answered"
    // into "refused" is exactly the confusion the caller's convergence
    // bookkeeping cannot survive (#78). Resolving the relay also fails cleanly
    // when it was never added, which is the honest answer to that call.
    let relay = client().relay(&url).await.map_err(|e| e.to_string())?;

    match relay.send_event(&event).await {
        // The relay accepted it.
        Ok(_) => Ok(true),
        // The relay answered, and its answer was no: an `OK: false`. This — a
        // rate limit, an invalid event, a policy refusal — is the *only* thing
        // that reads as a rejection.
        Err(nostr_sdk::pool::relay::Error::RelayMessage(_)) => Ok(false),
        // Anything else — not connected, timed out — means we never heard a
        // verdict at all, and the caller must be told so rather than shown a
        // refusal the relay never gave.
        Err(e) => Err(e.to_string()),
    }
}

pub async fn relay_subscribe(subscription_id: String, filter: FilterData) -> Result<(), String> {
    let mut f = Filter::new();

    if !filter.kinds.is_empty() {
        f = f.kinds(filter.kinds.into_iter().map(Kind::from));
    }
    if !filter.authors.is_empty() {
        let authors: Result<Vec<PublicKey>, String> = filter
            .authors
            .iter()
            .map(|a| PublicKey::parse(a).map_err(|e| e.to_string()))
            .collect();
        f = f.authors(authors?);
    }
    if !filter.ids.is_empty() {
        let ids: Result<Vec<EventId>, String> = filter
            .ids
            .iter()
            .map(|i| EventId::from_hex(i).map_err(|e| e.to_string()))
            .collect();
        f = f.ids(ids?);
    }
    if let Some(since) = filter.since {
        f = f.since(Timestamp::from(since.max(0) as u64));
    }
    if let Some(until) = filter.until {
        f = f.until(Timestamp::from(until.max(0) as u64));
    }
    if let Some(limit) = filter.limit {
        f = f.limit(limit as usize);
    }

    client()
        .subscribe_with_id(SubscriptionId::new(subscription_id), f, None)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub async fn relay_unsubscribe(subscription_id: String) {
    client()
        .unsubscribe(&SubscriptionId::new(subscription_id))
        .await;
}

/// Every registered relay, connected or not. Convergence is measured against
/// this list, so it must not quietly drop the relays that are currently down.
pub async fn relay_urls() -> Vec<String> {
    client()
        .relays()
        .await
        .keys()
        .map(|url| url.to_string())
        .collect()
}

/// The subset currently connected.
pub async fn relay_connected() -> Vec<String> {
    client()
        .relays()
        .await
        .iter()
        .filter(|(_, relay)| relay.status() == RelayStatus::Connected)
        .map(|(url, _)| url.to_string())
        .collect()
}

/// Every event arriving from any relay.
///
/// Deliberately built on the pool's raw `Message` notifications rather than its
/// de-duplicated `Event` ones: those drop events this client sent itself, and
/// events it has seen before. The app needs the relay's echo of its own matches
/// — that echo is how a second device learns the score. Filtering (NIP-40
/// expiry, addressable replacement) is the caller's job either way.
pub async fn relay_event_stream(sink: StreamSink<SignedEventData>) {
    let mut notifications = client().notifications();

    loop {
        match notifications.recv().await {
            Ok(RelayPoolNotification::Message {
                message: RelayMessage::Event { event, .. },
                ..
            }) => {
                if sink.add(to_signed_data(&event)).is_err() {
                    // Dart dropped the stream; nobody is listening any more.
                    break;
                }
            }
            Ok(_) => {}
            // Skipped events are tolerable — subscriptions redeliver and the
            // resend sweep converges — but a dead stream is forever.
            Err(broadcast::error::RecvError::Lagged(_)) => {}
            Err(broadcast::error::RecvError::Closed) => break,
        }
    }
}

/// Fires whenever a relay goes up or down.
///
/// A connection is the caller's cue to push state that relay missed while it
/// was away; a disconnection is its cue to stop counting on it.
pub async fn relay_status_stream(sink: StreamSink<RelayStatusData>) {
    let mut status = status_tx().subscribe();

    loop {
        match status.recv().await {
            Ok(change) => {
                if sink.add(change).is_err() {
                    break;
                }
            }
            // Missed some transitions. The per-relay watchers re-report after
            // their own lag, and the reconnect verifier re-nudges stragglers —
            // what must not happen here is the stream dying and taking Dart's
            // connection view with it.
            Err(broadcast::error::RecvError::Lagged(_)) => {}
            Err(broadcast::error::RecvError::Closed) => break,
        }
    }
}
