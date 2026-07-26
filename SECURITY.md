# Security

Noctweave Net is pre-protocol and unaudited. Do not use it for production
confidentiality, identity, or code execution.

## Security boundaries

- Clients create keys, encrypt private data, verify objects, and enforce
  capabilities.
- Every publication has its own publisher identity and every mutable head must
  verify under that authority. Publisher keys are not global accounts and must
  not be reused as Noctweave relationship or group keys.
- Standard relays provide bounded Noctweave transport, not identity.
- Passthrough relays provide path indirection, not anonymity.
- Host relays provide storage and retrieval, not publication authority.
- Consensus finalizes bounded public coordination state, not content safety or
  availability.

## Routing-policy boundary

Public v0 retrieval is either direct to a host or through one bounded
passthrough and then to a host. Those are alternatives, not a required
standard-to-passthrough-to-host chain.

The effective hard route directive is the first non-`open` value in this
authority order: authenticated federation policy for the routing trust domain,
authenticated host-relay operator advertisement, signed publisher directive,
then visitor preference. If all layers are open, direct is the deterministic
default. Lower layers cannot weaken or widen a higher requirement. A required
passthrough that is unavailable must fail closed rather than silently use a
direct route.

“Federation policy” is a Noctweave Net routing trust-domain/control-plane
constraint. It is not a fourth relay role, a forwarding hop,
`nw.federation` discovery, or authority over content. Consensus may finalize or
share the selected authenticated policy record without transporting content.

## Namespace boundary

A canonical `noct://<site>.<relay-suffix>/` name is a consensus-finalized
public lookup key, not proof of publisher identity or content authenticity.
Clients must verify that the resolved head is signed by the publisher authority
bound to the name, then verify every fetched object. A namespace relay is an
ordinary host relay; controlling its suffix, hosting account, or endpoint does
not authorize a publication update.

The namespace relay need not serve the publication's current bytes. Host
selection follows independently finalized locator state, and every host
response remains untrusted. Consensus must reject duplicate global suffixes and
duplicate site labels within one suffix. The same site label under different
suffixes is intentionally a different name.

## Routing and metadata threats

Implementations must defend against:

- stripping a signed publisher directive or another higher-authority
  directive;
- accepting stale or forged host-operator advertisements or federation-policy
  records;
- presenting a route as direct in UI or audit output when effective policy
  selected passthrough;
- silently downgrading required passthrough to direct;
- silently widening required direct retrieval to use a passthrough; and
- metadata-boundary collapse when one relay advertises both passthrough and
  host modules.

Depending on the path, operators and network observers may see endpoint
addresses, timing, traffic sizes, request frequency, host selection, storage
tenancy, retention, and topology. Noctweave Net does not currently provide cover
traffic, a mix network, or a global anonymity claim.

A co-located process must use separate credentials and rate limits for each
advertised module. Co-location must not turn passthrough authorization into host
write access or allow combined logs to erase which module observed which
metadata.

## Noctweb Lab active-content boundary

The experimental `noctweb-lab-v3` profile signs the publisher route directive
with the publication. V2 relay-namespace publications remain verifiable and
upgradeable, while v1 remains legacy read-only. The Lab uses deterministic
local adapters for operator advertisements and federation policy; production
records require authentication, freshness, and trust-domain binding.

The Lab executes publisher-authenticated client-side JavaScript, but a valid
publisher signature does not make that code safe. Before WebKit receives any
bytes, the Lab canonicalizes and verifies the complete bounded website bundle
and assigns it a publication-scoped custom origin. The runtime uses a
non-persistent data store, exposes no native message bridge, and applies a
content security policy, navigation policy, and WebRTC guard that deny website
access to external network resources.

The packaged app uses the macOS App Sandbox and grants read-only access only to
a build directory chosen through the system import panel. WebKit requires the
network-client entitlement for its separate networking process, so the
website-level denial is a runtime boundary, not a claim that the process lacks
network authority. This profile remains an unaudited test platform and is not a
production sandbox for hostile code.

Build imports reject symbolic links, non-regular files, ambiguous paths, more
than 512 files, and more than 16 MiB before unbounded allocation. Publisher-key
destruction is journaled before the irreversible Keychain deletion and retried
after restart when interrupted.

## Mandatory implementation properties

- canonical and domain-separated hashes and signatures;
- canonical name parsing, deterministic fallback-suffix derivation, and
  consensus-proof verification;
- publisher-identity derivation and signed-head verification before rendering;
- strict bounded decoding;
- client-side encryption for private content;
- no plaintext, token, capability, or ciphertext-body logging;
- explicit relay module and version discovery, including every module
  advertised by a multi-module process;
- authenticated, fresh, trust-domain-bound host-operator and federation-policy
  records;
- signed v3 publisher directives and fail-closed legacy-version handling;
- deterministic first-non-open directive resolution with truthful route UI and
  audit evidence;
- separate credentials, rate limits, policy, and audit boundaries for each
  co-located module;
- public-endpoint and DNS-rebinding defenses for passthrough;
- digest verification before host storage acknowledgement;
- sandboxed active content;
- fail-closed consensus and suite upgrades.

## Reporting

Until a private reporting channel is published, do not include live secrets,
capabilities, private capsule content, or exploit payloads in public issues.
