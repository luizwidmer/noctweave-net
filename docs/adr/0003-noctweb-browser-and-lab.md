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
- **Noctweb Lab** is the native macOS publisher, website editor, verified
  runtime, inspector, deterministic testnet, and fault-injection product. Its
  application interface uses SwiftUI. It is not a web application, PWA,
  Electron shell, hosted service, or remote-origin WebView wrapper.
- A conventional browser extension may later recognize links, preview bounded
  public content, and hand navigation to Noctweb Browser. It never becomes the
  publisher-key, capability, consensus, or execution authority.
- Internal Noctweb addresses may use `noct://` while portable external-link
  handling remains a separate compatibility decision.

The current Lab profile is named `noctweb-lab-v1`. It is explicitly
incompatible and backed by deterministic mock consensus. Its signed object
contains a bounded canonical bundle of ordinary website files. This supports
Lab-generated HTML, CSS, and JavaScript as well as self-contained production
builds from client-side frameworks such as React and Vite. Every lab
publication still requires its own local publisher identity and signed head;
the lab signature suite and head encoding remain temporary. Stable protocol
formats replace `noctweb-lab-v1` rather than inherit compatibility from it.

The Lab persists private publisher keys only in the macOS Keychain and renders
only an exact publisher-authenticated website bundle. The website runs in
WebKit under a publication-scoped custom origin, a non-persistent data store,
and a content security policy. The runtime exposes no native message bridge
and blocks external navigation and network access. Server-side rendering,
backend execution, development servers, hot-module replacement, remote CDN
dependencies, and service workers remain outside this profile.

## Consequences

- Runtime and test tooling share the same verification path.
- Host failover and invalid-byte rejection can be demonstrated before selecting
  consensus.
- Extension constraints cannot silently weaken key or origin boundaries.
- Client-side active content is usable for realistic website testing without
  gaining ambient native-app or external-network authority.
- Imported dependencies must be bundled into the signed site; ordinary remote
  CDN references do not work.
- The Lab is distributed as a signed `.app` bundle and has no public deployment
  URL.
