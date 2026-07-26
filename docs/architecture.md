# Noctweave Net Architecture

## 1. Layering

```text
Noctweave Net applications and local runtime
            │
Signed object graph and capability semantics
            │
Routing-policy resolver
            │
ConsensusAdapter        Host and retrieval adapters
            │                       │
finalized public state      Noctweave transport boundary
                                    │
              standard / passthrough / host modules
```

Noctweave Net owns object semantics, publisher continuity, capability links,
resolution, and local rendering. Noctweave owns the reusable transport
primitives and their cryptographic and operational boundaries. The selected
consensus profile owns only finalized public coordination state. Exactly three
relay/module families remain, but one process may advertise more than one. A
`solo` standard relay may also advertise `nw.net-host@1` and directly host and
serve content.

## 2. Relay-hosted Noctweb Publisher

Noctweb Publisher is a simple browser authoring page served from the same
origin as an opted-in hosting endpoint. A deployment is either:

- a `solo` standard relay process that separately advertises
  `nw.net-host@1`; or
- a dedicated host relay.

The Publisher page is a product surface over the host capability, not a relay
role, transport hop, consensus component, or server-side execution service.
Exactly three roles remain `standard`, `passthrough`, and `host`.

Publisher resources and capability- or authentication-bearing host operations
are served only over direct loopback or through an operator-declared trusted
TLS reverse proxy. Remote plaintext HTTP fails closed. The browser therefore
gets the secure context required for its nonextractable signing key, WebCrypto
verification, and encrypted local release state, while the relay password does
not traverse plaintext transport.

The editor accepts HTML, CSS, JavaScript, assets, and browser-ready static
output already compiled by tools such as React and Vite. It does not ask the
relay to install dependencies, compile React source, run a development server,
or provide a server-side application runtime.

For each publication, the browser creates and retains a distinct local signing
key. It canonicalizes and signs the bounded bundle before upload. The private
key is never submitted to the relay, reused as a hosting credential, or treated
as a global account or Noctweave relationship authority.

The host module treats the signed bundle as opaque exact bytes. It may validate
bounds and object IDs needed by the host contract, but it does not rewrite the
bundle, sign the publisher head, or interpret content as relay code. Its only
signature is a bounded hosting receipt for accepted bytes.

The UI reports a successfully verified receipt as **Hosted**. That state is
deliberately weaker than published or finalized: no head, locator, or name is
consensus-finalized merely because a relay accepted storage. A locally cached
receipt is reverified together with current relay presence before Hosted is
restored.

Each hosted revision keeps an independently AES-GCM-protected release
capability in a bounded browser-local ledger. Unhost-all attempts every tracked
release and preserves failed entries for retry, preventing a newer revision
from stranding older hosted copies. The host sees a capability only in the
explicit release request for that object.

The Publisher application and upload API share an origin, but hosted active
content does not inherit that origin's authority. A client verifies the bundle
digest and publication-scoped publisher signature before loading active
content into a sandbox with no ambient Publisher-origin credentials or relay
authority.

## 3. Data model

The first protocol revision must define canonical encodings and bounds for:

- `CapsuleObject`: immutable content, media type, links, and policy metadata;
- `ObjectID`: domain-separated digest of canonical object bytes;
- `PublisherHead`: signed pointer from a publisher authority to a root object
  and previous finalized head;
- `CapabilityLink`: an optional confidential reference carrying only the
  delegated authority needed for an operation;
- `HostLocator`: a signed, expiring statement that an object may be fetched
  from a host relay;
- `HostingReceipt`: a bounded host-signed acknowledgement of accepted storage;
- `NamespaceRecord`: a consensus-finalized binding from one canonical
  relay-scoped Noctweb name to a publication-scoped publisher identifier;
- `RouteDirective`: one of `open`, `direct`, or `passthrough`;
- `FederationPolicy`: an authenticated, trust-domain-bound top-level routing
  constraint that consensus may finalize or share; and
- `HostOperatorAdvertisement`: an authenticated, fresh module and routing
  statement from the selected host relay.

Private capsule payloads and confidential link material are encrypted before
they reach any relay. Public capsule objects may remain readable so they can be
mirrored and indexed, but their authenticity still comes from object digests,
publisher signatures, and finalized head state—not from TLS or a host name.

The exact canonical format, signature suite, encryption suite, and digest
suite remain open until test vectors are added. Provisional documents must not
claim wire compatibility.

## 4. Relay-scoped Noctweb namespace

The canonical base URL for a named site is:

```text
noct://<site>.<relay-suffix>/
```

A namespace advertisement is an optional capability of a relay process that
advertises the host module. It is not a fourth relay role and is not required
to host or serve content. An operator may set the displayed relay suffix. If
it does not, Noctweb Publisher derives a deterministic provisional
`r-<hash>` fallback from the public key that verifies the host's signed
receipts. A future consensus profile must define the exact normalization,
digest input, encoding, allocation, and collision handling before
interoperability is claimed.

Site labels are allocated within a suffix. Consensus enforces global suffix
uniqueness and uniqueness of each `(<site>, <relay-suffix>)` pair; the same
site label may be allocated under another suffix.

The finalized name record binds the URL to a publication-scoped publisher
identifier. It does not transfer cryptographic authority to the namespace
operator. The relay associated with a suffix is not required to be the current
content host: object retrieval follows the publication's independently
finalized host locators.

Until a consensus naming profile exists, Noctweb Publisher displays
`noct://<site>.<relay-suffix>/` only as a provisional name. Neither an
operator-configured suffix nor a receipt-key-derived fallback establishes
global uniqueness, allocation, finality, or portable resolution.

## 5. Publish flow

1. The local runtime constructs a bounded canonical object graph.
2. Private portions are encrypted locally.
3. The publisher signs a candidate head. In experimental `noctweb-lab-v3`,
   that signature also covers the publisher route directive.
4. Objects are uploaded to one or more host relays, directly or through a
   passthrough relay.
5. The client verifies hosting receipts and submits only the bounded public
   head, locator, and selected routing-policy commitments required by the
   consensus profile.
6. For a named publication, an authorized suffix allocation submits the
   canonical site-label binding to the publisher identifier.
7. After finality, resolvers may treat the name binding and new head as
   current.

Uploading an object does not publish it. A hosting receipt does not establish
publisher authority, consensus finality, or permanent availability.
Publishing and hosting never require passthrough, relay federation forwarding,
a consensus retrieval hop, or a namespace advertisement.

For the current Noctweb Publisher surface, the implemented flow stops after the
browser verifies the hosting receipt and reports **Hosted**. Consensus
submission and finalized naming remain later profile work.

## 6. Resolve flow

1. For a named URL, the runtime canonicalizes the address and asks its
   `ConsensusAdapter` for the finalized publisher binding.
2. It resolves the finalized publisher head and permitted public locators.
3. It chooses a current content host; this need not be the namespace relay.
4. It authenticates the federation-policy record for the routing trust domain
   and the selected host's operator advertisement, then verifies the signed
   publisher directive where the publication profile supplies one.
5. It selects the first non-`open` directive in strict federation-policy,
   host-operator, signed-publisher, then visitor order. If all are `open`,
   direct is the deterministic default.
6. It fetches the root and referenced objects through exactly one of the two v0
   shapes: directly from the host, or through one bounded passthrough and then
   the host.
7. It verifies namespace and policy finality evidence, publisher signature,
   object IDs, version links, bounds, and the actual route used.
8. It decrypts authorized private portions locally.
9. It renders or executes only within the runtime's sandbox and permission
   model. Hosted active content must not inherit Publisher-page origin
   privileges.

A relay response is untrusted input. HTTPS protects the connection to an
endpoint; it does not replace capsule verification.

The two retrieval shapes are alternatives, never a mandatory
standard-to-passthrough-to-host chain. A lower authority cannot weaken or widen
a higher directive. Required passthrough fails closed when unavailable and
never silently downgrades to direct.

“Federation policy” is product terminology for an authenticated Noctweave Net
routing trust-domain/control-plane constraint. It is not a fourth relay role,
relay forwarding, `nw.federation` discovery, a retrieval hop, or content
authority. Existing consensus may finalize or share the selected policy record.

Experimental `noctweb-lab-v3` signs the publisher directive. V2
relay-namespace publications remain verifiable and upgradeable; v1 remains
legacy read-only. Production host-operator advertisements and federation
policy must be authenticated. The Lab's versions are deterministic local
adapters rather than production authentication.

## 7. Private interaction

Private messages, invitations, collaborative updates, and capability delivery
use standard Noctweave opaque routes. Noctweave Net must not introduce a global
mailbox keyed by publisher identity.

Public publication continuity and private relationship continuity are separate
authorities. A consensus-visible publisher key must never be silently reused
as a Noctweave relationship or group key.

## 8. Failure model

- Missing host object: retry another finalized locator or surface unavailable.
- Hash or signature mismatch: reject the object and quarantine bounded
  metadata without executing or rendering it.
- Consensus unavailable: serve only explicitly cached finalized state within
  its policy; never guess a newer head.
- Passthrough failure: if effective policy requires passthrough, retry only
  another policy-valid passthrough or report unavailable; never downgrade to
  direct.
- Host equivocation: object IDs make immutable-byte equivocation detectable;
  mutable publication authority still depends on finalized head ordering.
- Stale locator: treat it as a retrieval failure, not an identity change.
- Stripped directive or stale/forged operator or federation policy: reject the
  routing decision and do not fetch.
- Route evidence mismatch: never claim direct retrieval when policy selected
  passthrough.
- Unavailable namespace relay: retain the finalized name-to-publisher binding
  and try current content locators; do not treat relay reachability as
  publisher authority.
- Invalid hosting receipt: do not report **Hosted**, even if the upload request
  returned success.
- Unverified active bundle: reject it before creating or navigating the content
  sandbox.

## 9. Privacy claim

Noctweave Net aims for semantic opacity to infrastructure carrying encrypted
private traffic. It does not claim endpoint invisibility or global anonymity.
Relays and network observers can still learn some combination of endpoint
addresses, timing, sizes, request frequency, host selection, and topology.
When one relay advertises both passthrough and host modules, it can correlate
both sides of the nominal hop; the topology must not describe that as metadata
separation. Co-located modules require separate credentials, rate limits, and
audit boundaries even though co-location still permits operator correlation.
