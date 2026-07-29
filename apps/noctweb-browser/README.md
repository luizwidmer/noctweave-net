# Noctweb Browser for macOS

Noctweb Browser is the authoritative native browsing runtime for Noctweave
Net. It opens `noct://` links, binds each resolution to an explicit local
network profile, verifies publisher and object evidence, applies the routing
authority hierarchy, and renders verified website files inside an isolated
WebKit runtime.

It is a native SwiftUI application. It does not bundle Chromium, embed a hosted
application shell, depend on a browser extension, or grant rendered websites a
native message bridge.

## Current MVP

The first implementation provides:

- operating-system registration for `noct://` and `.noctlink`;
- strict Noctweb navigation URL and access-descriptor parsing;
- local network profiles and visible trust-domain selection;
- a per-tab visitor route preference evaluated after federation, host, and
  publisher policy;
- threshold verification of byte-identical ML-DSA-signed federation namespace
  snapshots;
- authenticated suffix-to-relay resolution and home-relay forwarding of signed
  name and immutable object reads;
- deterministic signed fixture resolution for isolated development;
- tabs, address navigation, bookmarks, history, and verification states;
- a trust panel exposing publisher, trust domain, route, and verification
  evidence; and
- a publication-scoped, non-persistent WebKit renderer with external network,
  navigation, service worker, native bridge, and WebRTC access denied.

The fixture resolver is a test profile, not consensus finality. Federation
profiles pin bootstrap endpoints, relay IDs, ML-DSA public keys, a federation
name, and a namespace threshold. Manual profiles default to unanimity.
DHT/PEX-discovered relays are candidates only and never become namespace
authorities implicitly. Broader publisher-head and locator consensus remains
behind the same `NoctwebResolving` boundary.

## Build and test

```sh
swift build --package-path apps/noctweb-browser
swift test --package-path apps/noctweb-browser
```

Run the executable from SwiftPM:

```sh
swift run --package-path apps/noctweb-browser NoctwebBrowser
```

Package a signed application bundle:

```sh
apps/noctweb-browser/scripts/package-app.sh
```

By default the package script uses ad-hoc signing. Set
`NOCTWEB_BROWSER_CODESIGN_IDENTITY` to a Developer ID or development identity
when required.

Non-ad-hoc identities use the hardened runtime and a secure timestamp.
Notarization remains a separate release step.

The result is:

```text
apps/noctweb-browser/dist/Noctweb Browser.app
```

## Security boundary

The browser resolves and verifies before rendering. A host, TLS certificate,
relay suffix, `.noctlink` bootstrap hint, or hosting receipt cannot substitute
for a publisher signature or supported finality evidence. Hosted previews and
fixture resolutions remain visibly distinct from production Finalized state.

Local history and bookmarks retain the routing trust-domain identifier with the
canonical address so the same URL cannot silently change meaning between
profiles. Capability-bearing links are not eligible for ordinary history or
telemetry.

Until the capability URL grammar is frozen, the MVP conservatively excludes
every address containing a query or fragment from bookmarks and history.
