# Roadmap

## Phase 0: Architecture freeze

- Review the three relay roles and consensus boundary.
- Choose terminology for publisher IDs, heads, objects, and capabilities.
- Preserve the accepted invariant that every publication has a distinct
  cryptographic publisher identity; choose its stable suite and rotation rules.
- Specify the accepted relay-scoped namespace, including canonical labels,
  suffix allocation, finalized records, and deterministic vectors.
- Specify direct versus one-hop retrieval and the strict federation-policy,
  host-operator, signed-publisher, then visitor authority order.
- Record accepted changes as ADRs.

Exit gate: architecture review accepts the trust boundaries and non-goals.

## Phase 1: Object core

- Select canonical encoding, digest, signature, and encryption suites.
- Implement strict object, head, capability, locator, and receipt models.
- Add positive and adversarial test vectors in at least two languages.
- Build an in-memory publish and resolve demo.

Exit gate: deterministic cross-language vectors and bounded-decoder tests pass.

### Noctweb Lab track

Noctweb Lab begins during Phase 1 with the explicitly incompatible
`noctweb-lab-v3` website-bundle, signed publisher-routing, and relay-scoped
namespace profile. It is a native macOS SwiftUI application with a
Design/Code/Preview editor, mock consensus, independently modeled standard,
passthrough, and host modules, canonical `noct://` name allocation, direct and
one-hop retrieval, and publication-scoped Keychain identity. Its deterministic
local adapters model authenticated operator and federation-policy inputs;
production profiles must authenticate those records. V2 relay-namespace
publications remain verifiable and upgradeable, while v1 remains legacy
read-only. Ordinary static and client-side website files run only after
verification in an isolated, publication-scoped WebKit canvas. The Lab is the
continuous test surface for every later phase; temporary lab objects never
become protocol compatibility promises. The Lab itself must not be deployed as
a website or PWA.

## Phase 2: Standard relay adapter

- Pin supported Noctweave module versions.
- Carry private Noctweave Net events over opaque routes.
- Store larger encrypted private objects only through the bounded blob surface.
- Verify that one process can advertise standard and host modules without
  merging their credentials, rate limits, or authorization.
- Add retry, cursor, restart, and capability-leak tests.

Exit gate: a two-client private exchange survives restart without plaintext
relay storage.

## Phase 3: Host relay

- Implement immutable put/get/has and hosting receipts.
- Add quotas, expiry, tenant isolation, exact-byte retrieval, and disk-pressure
  behavior.
- Support both self-hosted and provider-operated configurations.
- Authenticate operator route advertisements and keep namespace advertisement
  optional for every content host.

Exit gate: publish on one host, mirror to another, remove the first, and resolve
the same verified object ID directly, without requiring passthrough,
federation forwarding, a consensus hop, or namespace ownership.

## Phase 4: Passthrough relay

- Implement one-hop bounded forwarding.
- Enforce destination and DNS-rebinding protections.
- Resolve the first non-open directive in strict federation-policy,
  host-operator, signed-publisher, then visitor order.
- Add directive-stripping, downgrade, redirect, timeout, response-size,
  disconnect, metadata-collapse, and abuse tests.

Exit gate: direct-to-host and one-passthrough-to-host retrieval both work as
alternative v0 shapes; a required but unavailable passthrough fails closed.

## Phase 5: Consensus profile

- Select the first consensus system.
- Implement finality-proof verification behind `ConsensusAdapter`.
- Finalize or share the authenticated federation-policy record selected for
  each Noctweave Net routing trust domain.
- Add head conflict, reorganization, stale epoch, locator expiry, and offline
  cache tests, including stale or forged federation-policy rejection.

Exit gate: two independent clients resolve the same finalized head and reject
non-final or invalid alternatives.

## Phase 6: Runtime

- Resolve graphs, verify content, decrypt capabilities, and render locally.
- Define a sandbox and permissions for active content.
- Extract `NoctwebRuntimeCore` from the Lab's resolver, verification, routing,
  address, and isolated-renderer boundaries.
- Ship the native macOS Noctweb Browser with address-bar navigation, tabs,
  local bookmarks and history, network-profile selection, trust state, and
  operating-system registration for `noct://` and `.noctlink`.
- Resolve names only inside explicit local network profiles; unknown or
  conflicting trust-domain claims fail closed before rendering.
- Distinguish Finalized, Hosted preview, Stale, Offline verified cache, and
  Blocked in browser chrome.
- Assess an optional link-handoff browser extension only after native URL
  handling works, without weakening origin or key boundaries.
- Keep publisher keys, capability authority, and verification in the native
  runtime; an extension is never the authoritative client.

Exit gate: an OS-opened `noct://` link resolves the same finalized publisher on
two independent clients, rejects ambiguous or forged trust-domain evidence,
and survives host replacement without changing publisher or object identity.
