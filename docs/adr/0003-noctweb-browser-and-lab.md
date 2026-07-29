# ADR 0003: Use dedicated native Noctweb applications

- Status: Accepted
- Date: 2026-07-25
- Amended by: ADR 0008, ADR 0009, and ADR 0010

## Context

Noctweave Net needs a client that can resolve publisher state, fetch from
replaceable hosts, verify every object, hold capability authority, and isolate
active content. A conventional extension can provide useful navigation hooks
but does not provide a consistent cross-browser origin, lifecycle, or storage
authority.

The protocol also needs a runnable authoring and verification surface before
its stable object and consensus profiles exist.

## Decision

The user-facing product is **Noctweb**.

- **Noctweb Browser** is the future authoritative runtime and browsing
  experience. It is a dedicated native application, not a hosted website or a
  browser extension.
- **Noctweb Lab** is the native macOS publisher, website editor, verified
  runtime, and inspector. Its
  application interface uses SwiftUI. It is not a web application, PWA,
  Electron shell, hosted service, or remote-origin WebView wrapper.
- **Noctweb Publisher** is the distinct basic relay-hosted browser authoring
  surface accepted by ADR 0008. It does not replace Noctweb Browser as the
  authoritative runtime or turn Noctweb Lab into a hosted application.
- A conventional browser extension may later recognize links and hand
  navigation to Noctweb Browser. It never resolves or renders Noctweb content
  and never becomes the publisher-key, capability, consensus, permission, or
  execution authority.
- Internal Noctweb addresses may use `noct://` while portable external-link
  handling follows ADR 0009: the operating system launches the native Browser,
  an optional extension performs handoff only, and bounded `.noctlink`
  descriptors carry explicit trust-domain context without becoming authority.

The original Lab profile was named `noctweb-lab-v1`. The relay-scoped address
work in ADR 0006 superseded it with `noctweb-lab-v2`, which is still explicitly
experimental and backed by deterministic mock consensus. Its signed object
contains a bounded canonical bundle of ordinary website files. This supports
Lab-generated HTML, CSS, and JavaScript as well as self-contained production
builds from client-side frameworks such as React and Vite. Every lab
publication still requires its own local publisher identity and signed head;
the lab signature suite and head encoding remain temporary. Stable protocol
formats may replace the Lab profiles rather than inherit compatibility from
them. The native app preserves signed v1 publications without silently
rewriting their committed addresses; only unpublished v1 drafts migrate.
ADR 0010 replaces the product's deterministic network with real
`nw.net-host@1` connections while retaining mock consensus only in tests.

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
