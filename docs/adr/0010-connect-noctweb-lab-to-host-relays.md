# ADR 0010: Connect Noctweb Lab to real host relays

- Status: Accepted
- Date: 2026-07-28
- Amends: ADR 0003 and ADR 0005

## Context

The first Lab implementation used an in-process relay topology and mock
consensus so the object, signature, and renderer boundaries could be exercised
before a host API existed. Presenting that topology in the product became
misleading once `nw.net-host@1` was available.

## Decision

The native Noctweb Lab product connects directly to operator host relays.

- The operator enters an HTTP loopback or remote HTTPS endpoint.
- The Lab discovers the relay namespace and signed-receipt key from
  `/noctweb/config.json`.
- Hosting submits a publisher-signed `HostedCapsuleEnvelope` to `/relay`.
- The Lab immediately fetches the retained object again, verifies exact bytes,
  the object digest, publisher signature, and relay hosting receipt, then
  records the endpoint and object identifier in its local workspace.
- Hosted preview resolves every already-known routing requirement before the
  direct host request. A signed cached publication may supply the publisher
  directive only when its envelope digest matches the saved hosted object ID;
  an edited draft cannot override the visitor's route. When that signed local
  envelope is unavailable, the publisher route is treated conservatively as
  passthrough unless a known higher-priority federation or host-operator
  directive forces direct.
  The active workspace's selected host endpoint is matched to exactly one
  configured host relay before using its operator directive; missing or
  duplicate matches fail closed unless federation explicitly forces direct.
  A hosted address is resolved only from the
  active workspace, preferring its selected site when drafts share an address.
  Switching workspaces can therefore make an otherwise saved hosted revision
  unavailable until its host is configured in the active workspace. The
  fetched signed publication is checked again with the host operator policy
  before rendering. An unsupported required passthrough route fails without
  contacting the host.
- Restoring a live workspace does not discover host relays or preview a saved
  site automatically. Saved online state is cleared on launch. Connect &
  Verify and Check directly are explicit control-plane requests; they contact
  the host only when federation, host-operator, and visitor routing permit a
  direct path. Publishing is an explicit direct write to the selected host.
- The optional host configuration is bounded before its retention values are
  used. Invalid values, including an upper limit below the minimum, are
  rejected as configuration errors.
- Publisher authorization is held in memory only and cleared after each
  operation.
- The native Browser's local development resolver may read that workspace,
  re-fetch the object from the recorded relay, and independently perform the
  same envelope and receipt verification before showing **Hosted preview**.
- A host receipt never becomes consensus finality, global naming authority, or
  a continued-availability claim.

`MockConsensus`, deterministic relay topology, and fault injection remain
bounded test fixtures. They are not the shipping Lab network or publication
path and are not exposed in product navigation.

## Consequences

- Running the Lab now requires an enabled `nw.net-host@1` relay for hosting and
  retrieval.
- Loopback HTTP remains useful for local development; non-loopback endpoints
  require HTTPS.
- Product evidence describes hosting and independent verification, not mock
  replication or finality.
- Deterministic unit tests remain available without granting simulated state
  product authority.
