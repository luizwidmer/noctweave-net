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
A standard relay may also advertise `nw.net-host@1` and directly host and
serve content in any non-passthrough federation mode.

## 2. Relay-hosted Noctweb Publisher

Noctweb Publisher is a simple browser authoring page served from the same
origin as an opted-in hosting endpoint. A deployment is either:

- a standard relay process that separately advertises
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

## 3. End-user access

The authoritative visitor runtime is the native Noctweb Browser. The operating
system hands it `noct://` URLs; an optional extension may recognize and hand
links off but never resolves, stores authority, or executes a site.

Each named resolution uses an explicit local `NoctwebNetworkProfile` that binds
the request to one routing trust domain, consensus profile, verification
material, bounded bootstrap set, supported epoch, and visitor route preference.
Unknown suffixes stop for profile import. Conflicting finalized claims require
an explicit choice and visible trust-domain fingerprint. Tabs, bookmarks, and
history retain the trust-domain identifier with the URL.

A bounded `.noctlink` descriptor may carry the canonical URL, trust-domain
identifier, optional expected publisher, and bootstrap hints. It is untrusted
input and cannot replace finality, publisher, object, or route verification.

Before rendering, the Browser executes the resolve flow below and assigns a
publication-scoped internal origin. Its chrome distinguishes Finalized, Hosted
preview, Stale, Offline verified cache, and Blocked. The current relay HTTPS
viewer is only the Hosted-preview compatibility path; no central gateway is
required.

See [Noctweb end-user access](noctweb-access.md).

## 4. Data model

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

## 5. Relay-scoped Noctweb namespace

The canonical base URL for a named site is:

```text
noct://<site>.<relay-suffix>/
```

Every federated standard or host relay owns a persistent ML-DSA-65 identity and
an operator-configured suffix. A signed identity claim binds the relay ID,
suffix, endpoints, role, federation, and capabilities. This namespace
advertisement is a control-plane property, not a fourth relay role, and does
not require the relay to host every object named beneath its suffix.

Each federation maintains a durable suffix ledger. A first valid claim reserves
one suffix for one relay ID. Downtime does not release it. Identity rotation
requires signatures from both old and new keys and retains the suffix. Signed
release creates a permanent tombstone. No subsequent relay may claim a
tombstoned suffix.

Relays expose ML-DSA-signed snapshots of the canonical ledger. A Browser
network profile pins the eligible signer keys and threshold. It accepts only
byte-identical snapshots meeting that threshold: manual defaults to unanimity,
curated uses its configured coordinator quorum, and open uses an explicit
threshold signer set. DHT/PEX discovers candidates only. It never votes,
allocates, or overrides the signer policy. Divergent partition state therefore
fails closed.

Site labels are allocated within a suffix. The owner relay signs a binding from
`(<site>, <suffix>)` to the publication publisher ID, head, revision, and object
ID after that object is stored. The same site label may exist under another
suffix. Publisher signatures and object hashes remain mandatory; suffix
ownership does not grant publisher authority.

## 6. Publish flow

1. The local runtime constructs a bounded canonical object graph.
2. Private portions are encrypted locally.
3. The publisher signs a candidate head. In experimental `noctweb-lab-v3`,
   that signature also covers the publisher route directive.
4. Objects are uploaded to one or more host relays, directly or through a
   passthrough relay.
5. The client verifies the hosting receipt.
6. For a named publication, it asks the suffix owner to bind the canonical
   site label to the publisher identifier, head, revision, and stored object.
7. The client verifies the relay-signed name binding before reporting the
   publication as named.

Uploading an object does not publish it. A hosting receipt does not establish
publisher authority, consensus finality, or permanent availability.
Publishing and hosting never require passthrough, relay federation forwarding,
a consensus retrieval hop, or a namespace advertisement.

General publication-head consensus remains later profile work; the implemented
federation profile covers relay/suffix ownership and relay-signed local names.

## 7. Resolve flow

1. The runtime canonicalizes the address and queries its bootstrap relays for
   signed namespace snapshots.
2. It requires the local profile's threshold of byte-identical snapshots and
   resolves the suffix to one authenticated relay identity and endpoint.
3. It asks its home relay for the destination's signed site binding and object;
   the home relay forwards only a bounded opaque federation request.
4. It authenticates the federation-policy record for the routing trust domain
   and the selected host's operator advertisement, then verifies the signed
   publisher directive where the publication profile supplies one.
5. It selects the first non-`open` directive in strict federation-policy,
   host-operator, signed-publisher, then visitor order. If all are `open`,
   direct is the deterministic default.
6. It fetches the root and referenced objects through exactly one of the two v0
   shapes: directly from the host, or through one bounded passthrough and then
   the host.
7. It verifies namespace quorum evidence, destination relay identity, signed
   name, publisher signature, object IDs, version links, bounds, and the actual
   route used.
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

## 8. Private interaction

Private messages, invitations, collaborative updates, and capability delivery
use standard Noctweave opaque routes. Noctweave Net must not introduce a global
mailbox keyed by publisher identity.

Public publication continuity and private relationship continuity are separate
authorities. A consensus-visible publisher key must never be silently reused
as a Noctweave relationship or group key.

## 9. Failure model

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

## 10. Privacy claim

Noctweave Net aims for semantic opacity to infrastructure carrying encrypted
private traffic. It does not claim endpoint invisibility or global anonymity.
Relays and network observers can still learn some combination of endpoint
addresses, timing, sizes, request frequency, host selection, and topology.
When one relay advertises both passthrough and host modules, it can correlate
both sides of the nominal hop; the topology must not describe that as metadata
separation. Co-located modules require separate credentials, rate limits, and
audit boundaries even though co-location still permits operator correlation.
