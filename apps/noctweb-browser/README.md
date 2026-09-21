<p align="center">
  <img src="Packaging/NoctwebBrowserIcon.svg" alt="Noctweb Browser icon" width="112">
</p>

<a id="noctweb-browser-for-macos"></a>

<h1 align="center">Noctweb Browser</h1>

<p align="center"><strong>A native browser that verifies a publication before opening it.</strong></p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#features">Features</a> ·
  <a href="#security-and-privacy">Security</a> ·
  <a href="#documentation">Documentation</a>
</p>

## Overview

Noctweb Browser opens `noct://` addresses inside an explicit network
profile, verifies the publisher and signed namespace, and renders verified
website bytes in an isolated WebKit runtime. The SwiftUI app exposes trust and
routing evidence alongside tabs, bookmarks, and history.

| Detail | At a glance |
| --- | --- |
| Platform | macOS 14+ |
| Built with | Swift 6 · SwiftUI · WebKit |
| License | [AGPL-3.0-or-later](../../LICENSE) |

> **Status:** MVP. The fixture resolver is for development; broader publication finality remains a separate protocol boundary.

<a id="build-and-test"></a>

## Quick start

Run commands from the **noctweave-net repository root**. Swift 6 is required.
The package resolves its pinned public Noctweave dependency unless
`NOCTWEAVE_PACKAGE_PATH` selects a local `NoctweaveCore` checkout.

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

<a id="current-mvp"></a>

## Features

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
- forgiving address-bar entry: `site.relay` and `noct://site.relay` are
  normalized to the canonical `noct://site.relay/` form;
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

<a id="security-boundary"></a>

## Security and privacy

The browser resolves and verifies before rendering. A host, TLS certificate,
relay suffix, `.noctlink` bootstrap hint, or hosting receipt cannot substitute
for a publisher signature or supported finality evidence. Hosted previews and
fixture resolutions remain visibly distinct from production Finalized state.

Local history and bookmarks retain the routing trust-domain identifier with the
canonical address so the same URL cannot silently change meaning between
profiles. Capability-bearing links are not eligible for ordinary history or
telemetry.

Only direct address-bar input receives the scheme/root-path convenience.
Persisted state, `.noctlink` descriptors, history, bookmarks, and protocol
objects continue through the strict canonical parser; foreign or ambiguous
schemes are rejected rather than rewritten.

Until the capability URL grammar is frozen, the MVP conservatively excludes
every address containing a query or fragment from bookmarks and history.

## Documentation

| Read | For |
| --- | --- |
| [Project overview](../../README.md) | Network architecture and status |
| [Access profile](../../docs/noctweb-access.md) | Addresses, profiles, and runtime expectations |
| [Native runtime decision](../../docs/adr/0009-native-noctweb-browser-access.md) | Verification and permission boundaries |
| [Release guide](APP_STORE_RELEASE.md) | Distribution requirements |

## License

Part of Noctweave Net, licensed under [AGPL-3.0-or-later](../../LICENSE).
