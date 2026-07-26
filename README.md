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
- Consensus finalizes shared public head and locator state.
- Host relays store and serve capsule bytes.
- Standard relays carry private Noctweave traffic.
- Passthrough relays forward bounded opaque exchanges to an explicit next hop.
- Clients verify, decrypt, resolve capabilities, and render locally.

Location is replaceable. A host or passthrough relay can disappear without
changing a capsule object's identity.

## Relay topology

Noctweave Net has exactly three relay roles:

| Role | Durable payload storage | Function |
| --- | --- | --- |
| Standard relay | Bounded route storage | Existing Noctweave opaque-route messaging and control transport |
| Passthrough relay | No | Bounded forwarding to one client-selected, policy-valid next hop |
| Host relay | Yes | Store and serve content-addressed capsule objects for self-hosters or hosting providers |

A deployment may run more than one role in one process, but each enabled role
must advertise and enforce its own capabilities, limits, credentials, storage,
and logs. Co-location must not blur trust boundaries.

See [relay topology](docs/relay-topology.md).

The transport integration is implemented by Noctweave's provisional
`nw.net-passthrough@1` and `nw.net-host@1` modules. See the
[Noctweave integration contract](docs/noctweave-integration.md).

## Consensus boundary

Consensus replaces relay federation, discovery coordination, and shared
publication ordering for Noctweave Net. It finalizes only bounded public
commitments such as publisher heads, host locators, protocol epochs, and
revocations defined by the eventual consensus profile.

Consensus does not:

- transport capsule bodies or private messages;
- store decryption keys or capability secrets;
- receive Noctweave relationship or route authority;
- prove that a host will remain available;
- turn a publisher key into a global user account;
- choose a hidden relay route for a client.

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

The ADRs under [`docs/adr`](docs/adr/) record the rationale.

## Non-goals for the first implementation

- a blockchain or consensus algorithm;
- global search;
- traffic-analysis resistance or guaranteed anonymity;
- arbitrary server-side capsule execution;
- browser compatibility without a Noctweave Net runtime;
- migration compatibility with pre-release object formats;
- a global account, device, or recovery system.

## Status

The provisional host and passthrough relay modules are implemented in
Noctweave. This repository documents their integration contract; Noctweb Lab
currently exercises matching deterministic in-process adapters rather than
connecting to operator relay endpoints. The Lab is a runnable native macOS
application for the explicitly incompatible
`noctweb-lab-v1` website-bundle profile. It edits ordinary HTML, CSS,
JavaScript, and asset files; imports production builds from tools such as React
and Vite; publishes with publication-scoped Keychain identities; simulates all
three relay roles; and resolves through direct or passthrough paths. Verified
client-side sites run in a publication-scoped, network-isolated WebKit canvas
inside the App Sandbox. Project, workspace, source-file, visual-block, and
publisher-key deletion all require explicit destructive confirmation.
The stable object graph, consensus profile, production runtime, and
cross-language conformance suite remain pre-protocol. No security audit or
production readiness is claimed.
