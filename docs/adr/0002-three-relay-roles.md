# ADR 0002: Limit Capsule Net to three relay roles

- Status: Accepted
- Date: 2026-07-25

## Context

Combining delivery, forwarding, hosting, discovery, coordination, execution,
and identity in a generic relay would create unclear authority and a large
attack surface.

## Decision

Capsule Net defines exactly three relay roles:

1. `standard`: Noctweave opaque-route transport;
2. `passthrough`: non-durable bounded forwarding to an explicit next hop;
3. `host`: durable content-addressed capsule storage and retrieval.

Shared coordination comes from a separately selected consensus profile. Relay
federation and coordinator roles are not part of the Capsule Net topology.

## Consequences

- Operators can reason about storage, metadata, credentials, and abuse per
  role.
- A process may co-locate roles but must advertise and enforce them separately.
- New behavior must fit a client, one of these roles, a host service, or the
  consensus adapter; it cannot casually introduce another relay kind.
- Passthrough and host modules require new threat models and conformance tests
  before implementation.
