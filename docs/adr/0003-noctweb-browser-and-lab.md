# ADR 0003: Use a dedicated Noctweb runtime and shared Lab

- Status: Accepted
- Date: 2026-07-25

## Context

Noctweave Net needs a client that can resolve publisher state, fetch from
replaceable hosts, verify every object, hold capability authority, and isolate
active content. A conventional extension can provide useful navigation hooks
but does not provide a consistent cross-browser origin, lifecycle, or storage
authority.

The protocol also needs a runnable test surface before its stable object and
consensus profiles exist.

## Decision

The user-facing product is **Noctweb**.

- **Noctweb Browser** is the authoritative runtime and browser experience. Its
  first desktop implementation may wrap a system WebView; it is not a browser
  engine fork.
- **Noctweb Lab** is the shared publisher, browser, inspector, deterministic
  testnet, and fault-injection surface.
- A conventional browser extension may later recognize links, preview bounded
  public content, and hand navigation to Noctweb Browser. It never becomes the
  publisher-key, capability, consensus, or execution authority.
- Internal Noctweb addresses may use `noct://` while portable external-link
  handling remains a separate compatibility decision.

The first Lab profile is named `lab-v0`. It is explicitly incompatible,
static-only, scriptless, and backed by deterministic mock consensus. Stable
protocol formats replace it rather than inherit compatibility from it.

## Consequences

- Runtime and test tooling share the same verification path.
- Host failover and invalid-byte rejection can be demonstrated before selecting
  consensus.
- Extension constraints cannot silently weaken key or origin boundaries.
- Active content remains disabled until origin isolation, permissions,
  capability APIs, resource limits, and lifecycle rules are specified and
  tested.
