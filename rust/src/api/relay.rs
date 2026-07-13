//! The relay transport, backed by `nostr-sdk`'s relay pool.
//!
//! Thin on purpose, and shaped by the Dart interface above it
//! (`NostrRelayBackend`): connect, subscribe, publish to **one** relay and
//! report what *that relay* said. Reliability — the outbox, per-relay
//! convergence, the resend sweep — stays in Dart, where it was won (PRs #77,
//! #78). This module must never quietly acquire an opinion about any of it.
//!
//! The one thing worth understanding here is [`relay_publish`]: it asks the
//! pool to send to a single relay and reports whether **that** relay accepted.
//! `nostr-sdk` hands us that verdict directly (`Output.success` / `.failed`) —
//! precisely what the hand-rolled transport had to grow OK-tracking to learn.
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
        while let Ok(notification) = notifications.recv().await {
            if let RelayNotification::RelayStatus { status } = notification {
                // No receivers yet is not an error: Dart may not have opened
                // the stream, and the relay's status is what it is regardless.
                let _ = status_tx().send(RelayStatusData {
                    url: relay_url.clone(),
                    connected: status == RelayStatus::Connected,
                });
            }
        }
    });

    // Connect this relay alone, so adding one later does not disturb the rest.
    client().connect_relay(&url).await.map_err(|e| e.to_string())?;
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
pub async fn relay_reconnect_all() {
    client().disconnect().await;
    client().connect().await;
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
    let relay_url = RelayUrl::parse(&url).map_err(|e| e.to_string())?;

    let output = client()
        .send_event_to([relay_url.clone()], &event)
        .await
        .map_err(|e| e.to_string())?;

    if output.success.contains(&relay_url) {
        return Ok(true);
    }

    // The relay answered, and its answer was no.
    if output.failed.contains_key(&relay_url) {
        return Ok(false);
    }

    // Neither accepted nor refused: silence.
    Err(format!("no answer from {url}"))
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

    while let Ok(notification) = notifications.recv().await {
        if let RelayPoolNotification::Message {
            message: RelayMessage::Event { event, .. },
            ..
        } = notification
        {
            if sink.add(to_signed_data(&event)).is_err() {
                // Dart dropped the stream; nobody is listening any more.
                break;
            }
        }
    }
}

/// Fires whenever a relay goes up or down.
///
/// A connection is the caller's cue to push state that relay missed while it
/// was away; a disconnection is its cue to stop counting on it.
pub async fn relay_status_stream(sink: StreamSink<RelayStatusData>) {
    let mut status = status_tx().subscribe();

    while let Ok(change) = status.recv().await {
        if sink.add(change).is_err() {
            break;
        }
    }
}
