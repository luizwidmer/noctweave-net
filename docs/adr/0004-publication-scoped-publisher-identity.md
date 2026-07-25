# ADR 0004: Require a publication-scoped publisher identity

- Status: Accepted
- Date: 2026-07-25

## Context

A content digest proves that retrieved bytes match an object ID. It does not
prove who is authorized to advance a mutable publication head. Hostnames,
hosting accounts, relays, and consensus participants must not silently become
publisher authority.

Noctweave Net also rejects global protocol accounts. Reusing one public identity
across unrelated publications would create unnecessary correlation and would
blur the boundary between public publication continuity and private Noctweave
relationships.

## Decision

Every Noctweb publication has a cryptographic publisher identity from its first
head. A valid mutable head must bind:

- the publication-scoped publisher identifier;
- the publisher public key or a verifiable reference to it;
- the current root object ID;
- revision and continuity data required by the active profile;
- the publisher signature;
- the consensus finality evidence required by the active profile.

Publisher identity is scoped to one publication by default. It is not a global
user account, hosting credential, Noctweave relationship key, recovery
authority, or proof of a real-world person. Explicit cross-publication linking
requires a separate signed statement and is never inferred by a relay.

The publisher private key remains client-side. Host, passthrough, and standard
relays never receive it. Consensus sees only the bounded public commitment
defined by its profile.

Noctweb Lab implements this invariant with a locally generated Ed25519 key held
in an IndexedDB-backed non-extractable `CryptoKey` vault and a signed `lab-v0`
head. Ed25519 and the lab head encoding are temporary test mechanisms, not a
stable suite or wire-format promise.

## Consequences

- A host cannot replace a site by returning different bytes or advancing a head.
- Consensus finality cannot substitute for publisher authorization.
- Moving between hosts preserves both object and publisher identity.
- Separate sites are unlinkable by key unless the publisher explicitly links
  them.
- Key backup, rotation, delegation, revocation, and recovery require future
  profile work before production use.
