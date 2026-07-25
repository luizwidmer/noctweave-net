# Protocol Workbench

No Capsule Net wire format is stable yet. This directory will hold normative
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
opaque routes and bounded encrypted blobs. Capsule Net must specify which
Noctweave module versions are compatible; it must not duplicate their wire
formats under new names.

### Passthrough module

A future versioned module will describe a single bounded opaque request and
response forwarded to a client-selected public endpoint. Its schema must make
destination policy, redirect behavior, request correlation, response bounds,
timeouts, and failure classes exact.

It is not a general-purpose proxy API.

### Host module

A future versioned module will minimally support:

- store immutable object;
- fetch immutable object;
- check object presence;
- remove or release an authorized storage commitment;
- obtain a bounded signed hosting receipt;
- report exact host limits and capabilities.

Publisher-head finality is not a host method. It belongs behind the consensus
adapter.

### Consensus adapter profile

Each supported profile must define finalized head and locator records, finality
proof verification, epochs, reorganization behavior, bounds, and deterministic
vectors.

## Compatibility rule

No document may claim Capsule Net interoperability until:

1. canonical bytes are defined;
2. strict decoders reject unknown and out-of-bounds fields as specified;
3. positive and negative cross-language vectors exist;
4. capability discovery advertises the exact implemented versions;
5. persistence and restart behavior pass conformance tests;
6. the security status names all unaudited components.
