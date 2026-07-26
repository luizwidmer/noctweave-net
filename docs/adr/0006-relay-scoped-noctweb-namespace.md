# ADR 0006: Use a relay-scoped Noctweb namespace

- Status: Accepted
- Date: 2026-07-25

## Context

Publisher identifiers and object digests provide cryptographic identity, but
they are not convenient public addresses. A human-readable namespace must not
turn a relay operator, hosting account, or familiar label into publication
authority. It also must preserve replaceable content hosting and the accepted
three-role relay topology.

A single flat global site-label namespace would create unnecessary contention.
Binding names directly to current content hosts would make location part of
identity and weaken host failover.

## Decision

The canonical public base URL for a named Noctweb site is:

```text
noct://<site>.<relay-suffix>/
```

Each relay suffix belongs to one namespace relay. A namespace relay is an
ordinary `host` relay with a namespace capability; this decision does not add a
fourth relay role.

An operator may request a custom suffix. If it does not, the active profile
derives a deterministic `r-<hash>` fallback from the relay's dedicated
namespace public key. The profile must define canonical suffix and site-label
syntax,
normalization, hash domain separation, digest suite, encoding, length, and
collision handling.

Consensus owns the global allocation rules:

- every relay suffix is globally unique in one consensus trust domain;
- every site label is unique within its relay suffix;
- the same site label may be allocated under different suffixes;
- only the authorization defined for an allocated suffix may create or update
  its name records.

A finalized name record binds the canonical name to a
publication-scoped publisher identifier. The publisher's cryptographic
identity remains the authority that signs and advances publication heads.
Suffix ownership, name allocation, hosting credentials, and relay
administration never substitute for that signature.

The namespace relay is the host relay associated with the suffix, but it is not
required to be the publication's current content host. Current content
locations remain independently finalized, replaceable host locators. A client
resolves the name to publisher state, selects a current host, and verifies the
publisher head and exact object bytes regardless of which relay serves them.

Noctweb Lab implements this decision in the experimental `noctweb-lab-v2`
profile. Its signed object and publisher-head transcript commit both the
canonical address and the full namespace identifier. The fallback suffix uses
the first 80 bits of a domain-separated SHA-256 namespace-key commitment,
encoded as 16 lowercase base32 characters after `r-`. That short suffix is a
display identifier; the full 256-bit namespace identifier remains the security
comparison, and consensus must reject a visible-suffix collision.

Unpublished legacy drafts may be assigned a v2 namespace. Already signed
`noctweb-lab-v1` publications are preserved as legacy read-only records because
rewriting their address would invalidate their object and head commitments.

## Consequences

- Names remain recognizable while publisher identity and content location stay
  separate.
- Operators can choose a custom suffix without forcing every site label into
  one flat global namespace.
- A deterministic fallback gives every eligible host relay a stable suffix
  without a naming auction or operator choice.
- Compromise of a namespace relay or suffix credential cannot forge a valid
  publisher update, though it can affect namespace operations allowed by the
  consensus profile.
- Namespace allocations are public coordination metadata and may expose
  operator and publication associations.
- The consensus profile must define allocation, renewal, transfer, revocation,
  expiry, conflict, and reorganization behavior before interoperability is
  claimed.
