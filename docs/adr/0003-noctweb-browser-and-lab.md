# ADR 0003: Use dedicated native Noctweb applications

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

- **Noctweb Browser** is the future authoritative runtime and browsing
  experience. It is a dedicated native application, not a hosted website or a
  browser extension.
- **Noctweb Lab** is the native macOS publisher, structured-content runtime,
  inspector, deterministic testnet, and fault-injection product. Its interface
  and preview renderer use SwiftUI. It is not a web application, PWA, Electron
  shell, hosted service, or WebView wrapper.
- A conventional browser extension may later recognize links, preview bounded
  public content, and hand navigation to Noctweb Browser. It never becomes the
  publisher-key, capability, consensus, or execution authority.
- Internal Noctweb addresses may use `noct://` while portable external-link
  handling remains a separate compatibility decision.

The first Lab profile is named `lab-v0`. It is explicitly incompatible,
static-only, scriptless, and backed by deterministic mock consensus. Every lab
publication still requires its own local publisher identity and signed head;
the lab signature suite and head encoding remain temporary. Stable protocol
formats replace `lab-v0` rather than inherit compatibility from it.

The Lab persists private publisher keys only in the macOS Keychain and renders
the exact verified structured snapshot directly with native controls. It does
not parse or execute HTML, JavaScript, or Markdown.

## Consequences

- Runtime and test tooling share the same verification path.
- Host failover and invalid-byte rejection can be demonstrated before selecting
  consensus.
- Extension constraints cannot silently weaken key or origin boundaries.
- Active content remains disabled until origin isolation, permissions,
  capability APIs, resource limits, and lifecycle rules are specified and
  tested.
- The Lab is distributed as a signed `.app` bundle and has no public deployment
  URL.
