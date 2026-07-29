# ADR 0011: Use authenticated relay identities and threshold namespace snapshots

## Status

Accepted and implemented for the pre-1.0 federation profile.

## Context

Noctweb addresses use `noct://<site>.<relay-suffix>/`. Portable resolution
therefore needs more than an operator-entered endpoint: clients must know which
relay legitimately owns a suffix, where that relay is reachable, and whether
the result belongs to the selected federation trust domain.

Endpoint discovery alone cannot answer those questions. DNS, DHT, PEX, reverse
proxies, and coordinator directories can all return candidates, but none should
be able to silently replace one relay with another. Downtime also cannot free a
name, because an attacker could wait for an operator outage and claim its
suffix.

The same authenticated relay graph should support opaque client traffic and
Noctweb retrieval across relays without turning the federation into a trusted
plaintext processor or adding a fourth relay role.

## Decision

Each standard or host relay owns a persistent ML-DSA-65 key pair. Its relay ID
is derived from that public key. A signed identity claim binds:

- relay ID and signing public key;
- monotonically increasing identity sequence;
- relay role and federation mode/name;
- advertised endpoints;
- one optional Noctweb suffix;
- host receipt key when hosting is enabled; and
- advertised protocol capabilities.

Every non-solo standard or host relay must configure a canonical suffix before
joining its federation.

Federation members maintain a durable append-only suffix ledger. The first
valid claim binds one suffix to one relay ID. The record is not leased:

- going offline does not release it;
- identity rotation requires a transition signed by both old and new keys and
  keeps the same suffix;
- explicit release requires the active key's signature; and
- release creates a permanent tombstone, so the suffix is never reused.

Relays expose deterministic ML-DSA-signed snapshots. A Browser network profile
pins the permitted relay IDs and signing public keys and declares a threshold.
The collector accepts only byte-identical valid snapshots meeting that policy.
Manual federation defaults to unanimity. Curated federation uses its configured
coordinator quorum. Open federation uses an explicit threshold signer set.
DHT and PEX may supply open-federation candidates, but never signer authority.

Site labels remain local to the suffix. After storing an immutable publication
object, Noctweb Lab asks the owner relay to sign a strict binding containing the
site label, suffix, publisher ID, head, revision, and object ID. Publisher
signatures and object hashes remain authoritative for content.

For cross-relay messaging, a home relay forwards only a bounded encrypted
append through `nw.federation-forward@1`. For Noctweb, it can proxy a signed
name read and immutable object read to the destination selected by the
namespace. The client verifies the destination relay identity and every
content-level proof.

## Consequences

- A relay cannot impersonate another without its ML-DSA private key.
- No accepted namespace snapshot can assign one suffix to two relay IDs.
- Offline ownership and permanent burns are deterministic.
- Clients can use one home relay while reaching users and Noctweb content on
  another relay.
- Relay federation remains a control plane and opaque transport path, not a
  content or identity authority.
- Open discovery remains permissionless without making arbitrary DHT peers
  namespace voters.

The current mechanism is a signed-state quorum, not global Byzantine
consensus. A partition can produce divergent local ledgers; clients then fail
closed because the required signers do not return byte-identical snapshots.
Strict thresholds can also reduce availability while signers are offline.
Publication-head ordering, locator finality, and governance remain behind the
separate consensus adapter.
