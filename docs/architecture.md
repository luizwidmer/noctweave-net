# Noctweave Net Architecture

## 1. Layering

```text
Noctweave Net applications and local runtime
            │
Signed object graph and capability semantics
            │
ConsensusAdapter        Host and retrieval adapters
            │                       │
finalized public state      Noctweave transport boundary
                                    │
                 standard / passthrough / host relays
```

Noctweave Net owns object semantics, publisher continuity, capability links,
resolution, and local rendering. Noctweave owns the reusable transport
primitives and their cryptographic and operational boundaries. The selected
consensus profile owns only finalized public coordination state.

## 2. Data model

The first protocol revision must define canonical encodings and bounds for:

- `CapsuleObject`: immutable content, media type, links, and policy metadata;
- `ObjectID`: domain-separated digest of canonical object bytes;
- `PublisherHead`: signed pointer from a publisher authority to a root object
  and previous finalized head;
- `CapabilityLink`: an optional confidential reference carrying only the
  delegated authority needed for an operation;
- `HostLocator`: a signed, expiring statement that an object may be fetched
  from a host relay;
- `HostingReceipt`: a bounded host-signed acknowledgement of accepted storage.

Private capsule payloads and confidential link material are encrypted before
they reach any relay. Public capsule objects may remain readable so they can be
mirrored and indexed, but their authenticity still comes from object digests,
publisher signatures, and finalized head state—not from TLS or a host name.

The exact canonical format, signature suite, encryption suite, and digest
suite remain open until test vectors are added. Provisional documents must not
claim wire compatibility.

## 3. Publish flow

1. The local runtime constructs a bounded canonical object graph.
2. Private portions are encrypted locally.
3. The publisher signs a candidate head.
4. Objects are uploaded to one or more host relays, directly or through a
   passthrough relay.
5. The client verifies hosting receipts and submits only the bounded public
   head and locator commitments required by the consensus profile.
6. After finality, resolvers may treat the new head as current.

Uploading an object does not publish it. A hosting receipt does not establish
publisher authority, consensus finality, or permanent availability.

## 4. Resolve flow

1. The runtime asks its `ConsensusAdapter` for the finalized publisher head
   and permitted public locators.
2. It chooses a host and retrieval path locally.
3. It fetches the root and referenced objects directly or through a
   passthrough relay.
4. It verifies object IDs, signatures, version links, bounds, and policy.
5. It decrypts authorized private portions locally.
6. It renders or executes only within the runtime's sandbox and permission
   model.

A relay response is untrusted input. HTTPS protects the connection to an
endpoint; it does not replace capsule verification.

## 5. Private interaction

Private messages, invitations, collaborative updates, and capability delivery
use standard Noctweave opaque routes. Noctweave Net must not introduce a global
mailbox keyed by publisher identity.

Public publication continuity and private relationship continuity are separate
authorities. A consensus-visible publisher key must never be silently reused
as a Noctweave relationship or group key.

## 6. Failure model

- Missing host object: retry another finalized locator or surface unavailable.
- Hash or signature mismatch: reject the object and quarantine bounded
  metadata without executing or rendering it.
- Consensus unavailable: serve only explicitly cached finalized state within
  its policy; never guess a newer head.
- Passthrough failure: retry another client-selected path without changing
  object or publisher identity.
- Host equivocation: object IDs make immutable-byte equivocation detectable;
  mutable publication authority still depends on finalized head ordering.
- Stale locator: treat it as a retrieval failure, not an identity change.

## 7. Privacy claim

Noctweave Net aims for semantic opacity to infrastructure carrying encrypted
private traffic. It does not claim endpoint invisibility or global anonymity.
Relays and network observers can still learn some combination of endpoint
addresses, timing, sizes, request frequency, host selection, and topology.
