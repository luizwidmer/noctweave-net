# Protocol Workbench

Noctweave Net has no stable object format yet. This directory will hold normative
schemas, canonical encodings, and interoperability vectors once the following
surfaces are agreed.

## Candidate surfaces

### Capsule object profile

- canonical object encoding;
- domain-separated object ID;
- publisher signatures and head continuity;
- public and encrypted payload profiles;
- capability-link attenuation and expiry;
- strict size, depth, link-count, and media-type bounds.

### Noctweave transport profile

Standard relays should reuse supported Noctweave modules directly, especially
opaque routes and bounded encrypted blobs. Noctweave Net must specify which
Noctweave module versions are compatible; it must not duplicate their wire
formats under new names.

### Passthrough module

The provisional `nw.net-passthrough@1` module carries one `forward` request.
The relay accepts a bounded opaque body for one operator-allow-listed public
HTTPS Noctweave endpoint and returns the bounded opaque response. Redirects are
disabled and recursive passthrough is not selected by the relay.

It is not a general-purpose proxy API.

### Host module

The provisional `nw.net-host@1` module supports:

- `put`: store an immutable SHA-256-addressed object;
- `get`: fetch exact bytes and a signed hosting receipt;
- `has`: check current bounded retention;
- `release`: remove a commitment with its object-scoped capability.

Publisher-head finality is not a host method. It belongs behind the consensus
adapter.

### Consensus adapter profile

Each supported profile must define finalized head and locator records, finality
proof verification, epochs, reorganization behavior, bounds, and deterministic
vectors.

### Relay-scoped namespace profile

The canonical named-site base URL is
`noct://<site>.<relay-suffix>/`. A namespace relay is a host relay with either
a consensus-allocated custom suffix or the profile's deterministic
`r-<hash>` fallback derived from a dedicated namespace public key. The profile
must define canonical label syntax,
normalization, fallback derivation, allocation authorization, record bounds,
and conflict behavior.

Consensus enforces global suffix uniqueness and unique site labels within each
suffix. Name records bind to publication-scoped publisher identifiers, not to
hosting accounts or current content locations. Current content hosts remain
replaceable through finalized locator records.

## Compatibility rule

No document may claim Noctweave Net interoperability until:

1. canonical bytes are defined;
2. strict decoders reject unknown and out-of-bounds fields as specified;
3. positive and negative cross-language vectors exist;
4. capability discovery advertises the exact implemented versions;
5. persistence and restart behavior pass conformance tests;
6. the security status names all unaudited components.
