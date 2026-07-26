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

The protocol retains exactly three relay/module families: standard,
passthrough, and host. Module advertisements are not exclusive. A `solo`
standard relay may also advertise `nw.net-host@1` and directly host and serve
content. Each co-located module requires separate credentials, rate limits,
policy, storage lifetime, and audit boundaries.

### Passthrough module

The provisional `nw.net-passthrough@1` module carries one `forward` request.
The relay accepts a bounded opaque body for one operator-allow-listed public
HTTPS Noctweave endpoint and returns the bounded opaque response. Redirects are
disabled and recursive passthrough is not selected by the relay.

It is not a general-purpose proxy API.

The passthrough module is optional. V0 retrieval uses either a direct host
request or one bounded passthrough followed by the host; it never requires a
standard-to-passthrough-to-host chain.

### Host module

The provisional `nw.net-host@1` module supports:

- `put`: store an immutable SHA-256-addressed object;
- `get`: fetch exact bytes and a signed hosting receipt;
- `has`: check current bounded retention;
- `release`: remove a commitment with its object-scoped capability.

Publisher-head finality is not a host method. It belongs behind the consensus
adapter.

Hosting does not require passthrough, federation forwarding, a consensus
retrieval hop, or ownership or advertisement of a namespace.

### Hierarchical retrieval-policy profile

Every routing layer supplies one directive: `open`, `direct`, or
`passthrough`. The effective hard directive is the first non-`open` value in
strict authority order:

1. authenticated federation policy for the Noctweave Net routing trust domain;
2. authenticated host-relay operator advertisement;
3. signed publisher directive; and
4. visitor preference.

All-open defaults deterministically to direct. A lower layer cannot weaken or
widen a higher directive. A required passthrough that is unavailable fails
closed rather than silently downgrading to direct.

“Federation policy” is product terminology for a routing
trust-domain/control-plane constraint. The record is not a fourth relay role,
relay forwarding, `nw.federation` discovery, a consensus retrieval hop, or
content authority. Existing consensus may finalize or share the selected
record.

Experimental `noctweb-lab-v3` covers the publisher directive with the
publication signature. V2 relay-namespace publications remain verifiable and
upgradeable; v1 remains legacy read-only. The Lab's operator and
federation-policy adapters are deterministic local models. Production profiles
must authenticate those records and bind them to a trust domain and validity
window.

### Consensus adapter profile

Each supported profile must define finalized head and locator records, finality
proof verification, selected federation-policy records, epochs, reorganization
behavior, bounds, and deterministic vectors.

### Relay-scoped namespace profile

The canonical named-site base URL is
`noct://<site>.<relay-suffix>/`. The namespace function is an optional
advertisement by a relay with the host module, with either a
consensus-allocated custom suffix or the profile's deterministic `r-<hash>`
fallback derived from a dedicated namespace public key. The profile must
define canonical label syntax,
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
6. policy vectors cover authority ordering, directive stripping, stale or
   forged operator/federation policy, unavailable passthrough, and truthful
   route evidence; and
7. the security status names all unaudited components.
