# ADR 0002: Limit Noctweave Net to three relay roles

- Status: Accepted
- Date: 2026-07-25
- Clarified by: ADR 0007

## Context

Combining delivery, forwarding, hosting, discovery, coordination, execution,
and identity in a generic relay would create unclear authority and a large
attack surface.

## Decision

Noctweave Net defines exactly three relay/module families:

1. `standard`: Noctweave opaque-route transport;
2. `passthrough`: non-durable bounded forwarding to an explicit next hop;
3. `host`: durable content-addressed capsule storage and retrieval.

One relay process may advertise more than one module family. In particular, a
`solo` standard relay may also advertise `nw.net-host@1` and directly host and
serve content. Hosting does not require a passthrough, federation forwarding, a
consensus retrieval hop, or a namespace advertisement.

Shared coordination comes from a separately selected consensus profile.
Noctweave relay federation and coordinator roles are not part of the
Noctweave Net retrieval topology. ADR 0007 permits an authenticated federation
policy to constrain routing and permits existing consensus to finalize or share
that record; neither refinement adds a fourth role or a federation relay hop.

## Consequences

- Operators can reason about storage, metadata, credentials, and abuse per
  role.
- A process may co-locate modules but must advertise and enforce them
  separately, with distinct credentials, rate limits, and audit boundaries.
- New behavior must fit a client, one of these roles, a host service, or the
  consensus adapter; it cannot casually introduce another relay kind.
- Co-locating passthrough and host modules can collapse metadata separation and
  must be represented accurately.
- Passthrough and host modules require dedicated threat models and conformance
  tests.
