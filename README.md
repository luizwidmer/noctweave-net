# Noctweave Net

Noctweave Net is a cryptographically addressed web built behind the public
Noctweave transport layer. It treats existing network infrastructure as
replaceable delivery and storage while clients retain authority over identity,
verification, permissions, decryption, and rendering.

This repository is an architecture seed, not a compatible protocol release.
The first milestone is to freeze a small, testable boundary before choosing a
consensus implementation or shipping the production Noctweb runtime.

## Core model

A Noctweave Net publication is a signed, versioned object graph:

```text
publisher key
    └── finalized head
          └── root capsule
                ├── content-addressed object
                ├── content-addressed object
                └── capability link
```

- Immutable objects are addressed by a digest of canonical bytes.
- A publisher key signs proposed publication heads.
- Consensus finalizes shared public head, locator, namespace, and selected
  federation-policy state.
- Host relays store and serve capsule bytes.
- Standard relays carry private Noctweave traffic.
- Passthrough relays forward bounded opaque exchanges to an explicit next hop.
- Clients verify, decrypt, resolve capabilities, and render locally.

Location is replaceable. A host or passthrough relay can disappear without
changing a capsule object's identity.

## Noctweb namespace

The intended canonical public base URL for a named site is:

```text
noct://<site>.<relay-suffix>/
```

The suffix belongs to a namespace-capable host relay. An operator may configure
the suffix. When it does not, the current Noctweb Publisher derives a
deterministic provisional suffix from the public key that verifies that host's
hosting receipts. Site-label allocation is scoped to one suffix, so the same
label may exist under different suffixes without conflict.

The eventual consensus profile finalizes global suffix allocation and each unique
`(<site>, <relay-suffix>)` mapping. The mapping identifies a
publication-scoped publisher authority; it does not make the suffix operator
the publisher. The namespace relay is also not required to be a publication's
current content host. Readers use finalized host locators and still verify the
publisher head and exact object bytes.

No consensus naming profile exists yet. The current Publisher therefore labels
every displayed `noct://` name as provisional. An operator-set suffix or a
receipt-key-derived suffix is a local hosting namespace hint, not proof of
global uniqueness, allocation, finality, or portable resolution.

## Relay topology

Noctweave Net has exactly three relay/module families:

| Role | Durable payload storage | Function |
| --- | --- | --- |
| Standard relay | Bounded route storage | Existing Noctweave opaque-route messaging and control transport |
| Passthrough relay | No | Bounded forwarding to one client-selected, policy-valid next hop |
| Host relay | Yes | Store and serve content-addressed capsule objects for self-hosters or hosting providers |

A deployment may advertise more than one module family from one relay process.
In particular, a `solo` standard relay may also advertise `nw.net-host@1` and
directly host and serve content. Hosting does not require a passthrough hop,
federation forwarding, a consensus hop, or ownership of a namespace.
Namespace advertisement remains optional.

Each enabled module must advertise and enforce its own capabilities, limits,
credentials, rate limits, storage, and logs. Co-location must not blur trust or
metadata boundaries.

See [relay topology](docs/relay-topology.md).

The transport integration is implemented by Noctweave's provisional
`nw.net-passthrough@1` and `nw.net-host@1` modules. See the
[Noctweave integration contract](docs/noctweave-integration.md).

## Accessing Noctweb

The authoritative visitor product is the native **Noctweb Browser**. It
registers `noct://` with the operating system, resolves inside an explicit local
network profile, verifies finalized publisher and object state, applies the
routing authority hierarchy, and renders under a publication-scoped sandbox.
It is not a hosted website or browser extension.

An optional extension may recognize or hand links to the native Browser, but it
never owns keys, capabilities, consensus verification, permissions, or
execution. Before production consensus-backed resolution exists, the relay
HTTPS viewer remains a clearly labeled **Hosted preview** compatibility path.
There is no mandatory central gateway.

See [Noctweb end-user access](docs/noctweb-access.md) and
[ADR 0009](docs/adr/0009-native-noctweb-browser-access.md).

## Noctweb Publisher

**Noctweb Publisher** is the initial public authoring surface. It is a simple
browser page served from the same origin as an opted-in host endpoint. The
endpoint may be a dedicated host relay or a `solo` standard relay process that
also advertises `nw.net-host@1`; the page is not a fourth relay role and the
standard module alone does not gain hosting authority.

The Publisher and every capability- or authentication-bearing host operation
must be reached directly over loopback or through an operator-declared trusted
TLS reverse proxy. Remote plaintext HTTP fails closed: the relay password must
not cross it, and the browser signing, encrypted local storage, and WebCrypto
flows require a secure context.

The editor accepts ordinary HTML, CSS, and JavaScript projects. It can also
import browser-ready output compiled by tools such as React and Vite. The relay
does not install dependencies, run a React build, start a development server,
or execute server-side application code.

Each publication receives its own browser-local signing key. The private key
never becomes a relay credential, hosting account, global identity, or
Noctweave relationship key. The browser signs the bounded publication bundle;
the relay stores the exact signed bundle as opaque bytes and signs only a
bounded hosting receipt.

After a valid receipt, the upload status is **Hosted**. Hosted means that one
relay acknowledged the exact bytes under the receipt's stated bounds. It does
not mean that a publisher head, locator, or name is consensus-finalized, and it
does not promise continued availability. A restored local record is shown as
Hosted only after the Publisher revalidates both its signed receipt and current
relay presence.

Each hosted revision retains its own AES-GCM-protected release capability in a
bounded browser-local ledger. **Unhost all copies** attempts to release every
tracked revision and retains any failures for retry. A release capability is
never uploaded except when the publisher explicitly releases that object.

Hosted active content is fetched as untrusted input. The client verifies the
bundle digest and publisher signature before rendering it in a sandbox that
does not inherit the Publisher page's same-origin privileges. Relay storage or
HTTPS alone never authorizes execution.

## Public retrieval policy

Public retrieval has exactly two v0 shapes:

```text
visitor -> host
visitor -> passthrough -> host
```

They are alternatives. Noctweave Net does not require a
standard-to-passthrough-to-host chain.

Each authority supplies `open`, `direct`, or `passthrough`. The effective hard
directive is the first non-`open` value in this strict order:

1. federation policy for the authenticated routing trust domain;
2. host-relay operator advertisement;
3. signed publisher directive; and
4. visitor preference.

If all four leave the choice open, direct retrieval is the deterministic
default. A lower layer cannot weaken or widen a higher requirement. In
particular, required passthrough retrieval fails closed when no policy-valid
passthrough is available; it never silently downgrades to direct.

“Federation policy” is product terminology for an authenticated Noctweave Net
routing trust-domain/control-plane constraint. It is not a fourth relay role,
a relay-forwarding hop, `nw.federation` discovery, or content authority.
Existing consensus may finalize and share the selected federation-policy
record without carrying retrieval traffic.

## Consensus boundary

Consensus supplies shared publication ordering and may finalize the selected,
authenticated federation-policy record for a Noctweave Net routing trust
domain. It finalizes only bounded public commitments such as namespace
allocations, publisher heads, host locators, routing policy, protocol epochs,
and revocations defined by the eventual consensus profile. This policy input
does not enable Noctweave relay federation, discovery, or forwarding.

Consensus does not:

- transport capsule bodies or private messages;
- store decryption keys or capability secrets;
- receive Noctweave relationship or route authority;
- prove that a host will remain available;
- turn a publisher key into a global user account;
- become a retrieval hop or silently weaken a hard route directive.

The initial codebase will depend on a narrow `ConsensusAdapter` interface so a
consensus profile can be selected independently. See
[consensus boundary](docs/consensus-boundary.md).

## Repository map

```text
docs/
  architecture.md          System model and publish/resolve flows
  relay-topology.md        The three relay roles and their invariants
  consensus-boundary.md    What consensus may and may not coordinate
  noctweave-integration.md Exact relay roles, modules, and deployment boundary
  adr/                     Architecture decisions
apps/
  noctweb-lab/             Native macOS publisher, runtime, inspector, and testnet
  noctweb-browser/         Native visitor browser, verifier, and isolated renderer
spec/
  README.md                Candidate protocol surfaces and versioning rules
ROADMAP.md                 Implementation sequence and acceptance gates
SECURITY.md                Threat model summary and reporting policy
```

## Current decisions

1. Noctweave Net is a separate protocol repository, not a Noctweave fork.
2. Noctweave supplies encrypted transport primitives, not Noctweave Net identity
   or consensus.
3. Relay roles are limited to standard, passthrough, and host.
4. Relay federation modules are outside the Noctweave Net topology.
5. Coordination is consumed through an abstract consensus boundary.
6. Clients remain the verification and execution boundary.
7. Noctweb Browser is the authoritative runtime; browser extensions are
   compatibility bridges rather than identity or capability authorities.
8. Every publication has a publication-scoped cryptographic publisher identity;
   it is never inferred from a host, relay, account, or private relationship.
9. Noctweb Lab is a native macOS application. It has no hosted web application,
   OpenAI Sites dependency, PWA shell, Electron runtime, or remote-origin app
   shell. Its verified website canvas uses an isolated WebKit runtime only after
   the Lab has resolved and authenticated a signed website bundle.
10. Canonical named sites use `noct://<site>.<relay-suffix>/`. Namespace relays
    are host relays, consensus owns global allocation, and publisher signatures
    remain the publication authority.
11. Public retrieval is either direct to a host or through one bounded
    passthrough. The first non-open directive in federation-policy, host
    operator, signed publisher, then visitor order is authoritative.
12. Noctweb Publisher is a relay-hosted same-origin authoring page over an
    opted-in host capability. Its publication keys stay browser-local, relays
    sign only hosting receipts, and hosted active content is verified before
    sandboxed rendering.
13. End users access finalized sites through the native Noctweb Browser and an
    explicit local network profile. The OS handles `noct://`; extensions only
    hand links off, and relay HTTPS viewers remain Hosted previews.

The ADRs under [`docs/adr`](docs/adr/) record the rationale.

## Non-goals for the first implementation

- a blockchain or consensus algorithm;
- global search;
- traffic-analysis resistance or guaranteed anonymity;
- arbitrary server-side capsule execution;
- browser compatibility without a Noctweave Net runtime;
- automatic migration compatibility with arbitrary pre-release object formats;
- a global account, device, or recovery system.

## Status

The provisional host and passthrough relay modules are implemented in
Noctweave. Noctweb Publisher is the initial implemented public surface: a basic
same-origin browser editor for HTML, CSS, JavaScript, and browser-ready compiled
React bundles, served by an opted-in standard-plus-host deployment or a
dedicated host relay. It keeps one signing key per publication in the browser
and reports a verified upload receipt as **Hosted**. Its displayed `noct://`
names remain provisional, and it does not claim consensus finality, naming
authority, continued availability, or an in-relay React build service.

The first native Noctweb Browser MVP is implemented under
`apps/noctweb-browser/`. It registers `noct://` and `.noctlink`, resolves inside
an explicit local profile, verifies a deterministic signed fixture through the
runtime core, applies the routing-authority hierarchy, keeps local tabs,
bookmarks, and history, exposes verification evidence, and renders verified
HTML, CSS, JavaScript, and browser-ready framework bundles in a
publication-scoped non-persistent WebKit process. It bundles no Chromium and is
not a hosted application.

The visitor can select `open`, `direct`, or `passthrough` per tab; that choice
is evaluated only after federation, host-operator, and signed publisher policy.
Query- or fragment-bearing addresses stay out of local history and bookmarks
until the capability URL grammar is frozen.

The built-in profile is deliberately labeled **Development fixture**, never
**Finalized**. Production consensus resolution, authenticated host and
passthrough retrieval adapters, network-profile import, permissions, and
verified offline cache remain. The current relay viewer remains a
Hosted-preview bridge until those production adapters and a selected consensus
profile exist.

This repository also documents the relay integration contract; Noctweb Lab
currently exercises matching deterministic in-process adapters rather than
connecting to operator relay endpoints. The Lab is a runnable native macOS
application for the explicitly incompatible `noctweb-lab-v3` profile, whose
publisher routing directive is signed with the publication. Existing v2
relay-namespace publications remain verifiable and upgradeable; v1 remains
legacy read-only. The Lab edits
ordinary HTML, CSS, JavaScript, and asset files; imports production builds from
tools such as React and Vite; publishes with publication-scoped Keychain
identities; simulates all three relay roles; allocates canonical `noct://`
names; and resolves through the effective direct or one-hop policy. Verified
client-side
sites run in a publication-scoped, network-isolated WebKit canvas
inside the App Sandbox. Project, workspace, source-file, visual-block, and
publisher-key deletion all require explicit destructive confirmation.
The stable object graph, consensus profile, production runtime, and
cross-language conformance suite remain pre-protocol. No security audit or
production readiness is claimed.
