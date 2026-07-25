# Roadmap

## Phase 0: Architecture freeze

- Review the three relay roles and consensus boundary.
- Choose terminology for publisher IDs, heads, objects, and capabilities.
- Decide whether public mutable naming is in the first protocol profile.
- Record accepted changes as ADRs.

Exit gate: architecture review accepts the trust boundaries and non-goals.

## Phase 1: Object core

- Select canonical encoding, digest, signature, and encryption suites.
- Implement strict object, head, capability, locator, and receipt models.
- Add positive and adversarial test vectors in at least two languages.
- Build an in-memory publish and resolve demo.

Exit gate: deterministic cross-language vectors and bounded-decoder tests pass.

## Phase 2: Standard relay adapter

- Pin supported Noctweave module versions.
- Carry private Noctweave Net events over opaque routes.
- Store larger encrypted private objects only through the bounded blob surface.
- Add retry, cursor, restart, and capability-leak tests.

Exit gate: a two-client private exchange survives restart without plaintext
relay storage.

## Phase 3: Host relay

- Implement immutable put/get/has and hosting receipts.
- Add quotas, expiry, tenant isolation, exact-byte retrieval, and disk-pressure
  behavior.
- Support both self-hosted and provider-operated configurations.

Exit gate: publish on one host, mirror to another, remove the first, and resolve
the same verified object ID.

## Phase 4: Passthrough relay

- Implement one-hop bounded forwarding.
- Enforce destination and DNS-rebinding protections.
- Add redirect, timeout, response-size, disconnect, and abuse tests.

Exit gate: retrieval works through one passthrough hop and fails closed for
private or disallowed destinations.

## Phase 5: Consensus profile

- Select the first consensus system.
- Implement finality-proof verification behind `ConsensusAdapter`.
- Add head conflict, reorganization, stale epoch, locator expiry, and offline
  cache tests.

Exit gate: two independent clients resolve the same finalized head and reject
non-final or invalid alternatives.

## Phase 6: Runtime

- Resolve graphs, verify content, decrypt capabilities, and render locally.
- Define a sandbox and permissions for active content.
- Add browser-extension, dedicated-runtime, or PWA feasibility work without
  weakening origin or key boundaries.

Exit gate: a capsule site moves between hosts without changing publisher or
object identity.
