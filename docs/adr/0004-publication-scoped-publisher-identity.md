# ADR 0004: Require a publication-scoped publisher identity

- Status: Accepted
- Date: 2026-07-25
- Amended by: ADR 0008

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

Noctweb Publisher implements the same boundary with one browser-local signing
key per publication. The relay receives the public verification material and
signed bundle, never the private key. Browser storage is not a hosting account,
global identity, or recovery authority; backup, rotation, and recovery remain
future profile work.

Noctweb Lab implements this invariant with one locally generated Ed25519 key
per publication. Its raw private representation is protected at rest by a
non-synchronizable generic-password item in the user's macOS Keychain, under a
dedicated Noctweb Lab service name. The key is not Secure Enclave-backed and is
not described as non-extractable. A missing or malformed key for an established
publication blocks publishing instead of silently minting a replacement.

The publisher identifier is the full SHA-256 digest of a domain-separated
public-key commitment. The signed `noctweb-lab-v2` head uses a strict versioned
binary transcript rather than relying on ordinary JSON serialization and also
commits the full relay namespace identity from ADR 0006. That namespace
commitment does not replace the publisher signature. Ed25519 and the lab head
encoding are temporary test mechanisms, not a stable suite or wire-format
promise. Signed `noctweb-lab-v1` publications remain legacy read-only inputs.

Deleting a local site or workspace does not implicitly delete its publisher
key. Key destruction is a separate explicit operation because it permanently
removes the local authority to advance that publication. Neither local project
deletion nor key destruction erases immutable revisions already replicated to
hosts or caches. The deletion UI also offers a combined destroy-key-and-remove
operation so a key is not accidentally stranded when its project handle
disappears. Before deleting a Keychain item, the Lab persists a destruction
marker and reconciles incomplete destruction at startup.

## Consequences

- A host cannot replace a site by returning different bytes or advancing a head.
- Consensus finality cannot substitute for publisher authorization.
- Moving between hosts preserves both object and publisher identity.
- Separate sites are unlinkable by key unless the publisher explicitly links
  them.
- Project deletion, key destruction, and host-retention controls are distinct
  operations with different consequences.
- Key backup, rotation, delegation, revocation, and recovery require future
  profile work before production use.
