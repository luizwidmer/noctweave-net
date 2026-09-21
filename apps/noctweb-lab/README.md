<p align="center">
  <img src="Packaging/NoctwebLabIcon.svg" alt="Noctweb Lab icon" width="112">
</p>

<a id="noctweb-lab-for-macos"></a>

<h1 align="center">Noctweb Lab</h1>

<p align="center"><strong>Build, sign, publish, and inspect a Noctweb site from your Mac.</strong></p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#features">Features</a> ·
  <a href="#security-and-privacy">Security</a> ·
  <a href="#documentation">Documentation</a>
</p>

## Overview

Noctweb Lab is a native SwiftUI workspace for ordinary HTML, CSS, JavaScript,
and compiled web assets. Design or edit locally, preview the verified bundle,
and publish through an authenticated Noctweave host relay.

| Detail | At a glance |
| --- | --- |
| Platform | macOS 14+ |
| Built with | Swift 6 · SwiftUI · WebKit · Keychain |
| License | [AGPL-3.0-or-later](../../LICENSE) |

> **Status:** The experimental noctweb-lab-v3 profile supports live hosting. Local simulation and hosted verification do not establish production publication consensus or independent audit assurance.

<a id="run-from-source"></a>

## Quick start

Run commands from the **noctweave-net repository root** with Swift 6.
Use the pinned public dependency, or set `NOCTWEAVE_PACKAGE_PATH` to a local
`NoctweaveCore` checkout.

```sh
swift run --package-path apps/noctweb-lab NoctwebLab
```

### Package the application

```sh
apps/noctweb-lab/scripts/package-app.sh
open "apps/noctweb-lab/dist/Noctweb Lab.app"
```

The packaging script creates and verifies an ad-hoc signed application bundle
with the Lab's App Sandbox entitlements.
Set `NOCTWEB_CODESIGN_IDENTITY` to a Developer ID certificate name when a
distribution-signed build is required.

<a id="website-workflow"></a>

## Features

The site editor treats a Noctweb site as an ordinary website project:

- **Design** provides a visual block editor for Lab-managed pages. Its output is
  normal HTML, CSS, and JavaScript rather than a private rendering format.
- **Code** exposes the project's file tree and source files for direct editing
  or for files produced by an agent.
- **Preview** runs the exact current website bundle in the same isolated
  website runtime used after resolution.
- **Import Build Folder** accepts a self-contained production output directory,
  such as `dist`, with `index.html` as its entry point.

Imported projects remain normal files. The Lab does not attempt to round-trip
arbitrary HTML through the visual block model.

Source files, visual blocks, sites, and workspaces have explicit destructive
workflows. Site and workspace removal can either retain publication keys or
destroy them first; the latter is irreversible and is recorded durably before
the Keychain item is deleted. Neither option claims to erase immutable
revisions that have already reached a host or cache.

## JavaScript and framework compatibility

The verified runtime supports conventional client-side HTML, CSS, JavaScript,
ES modules, images, fonts, media, and compiled framework assets stored in the
bundle. Self-contained production builds from React and Vite, and equivalent
static outputs from Vue, Svelte, or other browser frameworks, are the intended
compatibility boundary.

The native test suite loads a production-style bundle in a real `WKWebView`
and verifies a static ES-module import, dynamic chunk import, CSS, a
same-publication JSON fetch, SPA entry fallback, blocked external fetch, and
the WebRTC guard.

The Lab is not a Node.js host or application server. It does not provide an npm
build pipeline, a framework development server, hot-module replacement, SSR,
server actions, backend APIs, or service workers. Remote navigation, network
fetches, and CDN-hosted scripts are blocked in Preview and Runtime, so
dependencies and assets must be included in the imported build.

## Signed website bundles and compatibility

A `noctweb-lab-v3` object carries a canonical website bundle with:

- one normalized relative entry path;
- at most 512 files;
- at most 16 MiB of exact file bytes in total;
- a media type for every file; and
- no absolute, traversing, duplicate, or case-conflicting paths.

The bundle and publisher route directive are covered by the content digest and
publication-scoped publisher signature. Host and passthrough modules can move
or retain the bytes, but cannot alter a file or routing directive without
failing verification.

Existing `noctweb-lab-v2` relay-namespace publications remain verifiable and
may be upgraded to v3. Already signed `noctweb-lab-v1` publications remain
legacy read-only; the Lab does not rewrite their signed history.

Each publication receives its own Ed25519 publisher key. Private key material
is stored in the macOS Keychain and marked non-synchronizable. Workspace
drafts, topology, revisions, and test runs are stored locally in Application
Support. Standard, passthrough, and host module families remain independent
even when one simulated relay advertises more than one module. The Lab reports
integrity, publisher authority, routing-policy authority, and mock-consensus
finality as separate evidence.

## Public retrieval policy

The Lab models the only two v0 public retrieval shapes:

```text
visitor -> host
visitor -> passthrough -> host
```

They are alternatives; there is no mandatory
standard-to-passthrough-to-host chain. A standard relay may also
advertise `nw.net-host@1` and directly host and serve a publication.

Each layer may leave routing open, require direct retrieval, or require one
bounded passthrough hop. The first non-open directive wins in this strict
authority order:

1. federation policy;
2. host-relay operator;
3. signed publisher; and
4. visitor.

When all layers leave routing open, direct is the deterministic default. A
lower layer cannot weaken or widen a higher directive. If effective policy
requires one-hop retrieval and no eligible passthrough is available, the Lab
fails closed instead of silently choosing direct.

The UI calls the top layer “federation policy.” In this Lab it is a
deterministic local model of an authenticated Noctweave Net routing
trust-domain/control-plane constraint. It is not a fourth relay role,
`nw.federation` discovery, a relay-forwarding hop, or content authority.
Existing consensus may finalize or share the selected federation-policy record
without becoming part of the retrieval path. Production operator
advertisements and federation-policy records require authentication; the Lab's
adapters are test fixtures, not that authentication.

## Relay-scoped names

The Lab models canonical public base URLs as:

```text
noct://<site>.<relay-suffix>/
```

Federated standard and host relays advertise a persistent ML-DSA identity and
suffix. The Lab verifies that signed identity before publishing. It uploads the
immutable object first and requests the strict name binding only after the
hosting receipt succeeds.

Relay discovery does not require the optional embedded publisher UI. The Lab
uses `/noctweb/config.json` when an operator exposes it, then falls back to the
canonical `/relay` info request and derives the bounded host configuration only
from the verified relay identity and signed `nw.net-host@1` capability limits.
This supports reverse proxies that intentionally expose only the public relay
protocol endpoint without weakening relay-identity verification.

Site labels are unique only within one suffix, so two different suffixes may
each allocate the same label. The signed binding resolves to the site's
publication-scoped publisher identity, head, revision, and object. The relay
does not gain the publisher key; readers still verify the publisher signature
and exact bundle bytes.

<a id="verified-website-runtime"></a>

<a id="security-boundary"></a>

## Security and privacy

After resolution, the Lab authenticates the publisher head and exact bundle
bytes before passing them to WebKit. Every publication receives its own custom
origin. The runtime uses a non-persistent data store, exposes no JavaScript-to-
native message bridge, serves only files from the verified bundle, and blocks
external navigation and website network access with navigation policy, a
content security policy, and an early WebRTC API guard.

The packaged app uses the macOS App Sandbox. It grants read-only access only to
directories selected through the import panel. WebKit requires the app's
network-client entitlement to launch its separate networking process, so
website isolation is enforced by the verified custom-scheme loader and runtime
policy rather than by claiming that the process has no network entitlement.

JavaScript is active content even inside these boundaries. The Lab profile is
a test platform, not a claim that arbitrary untrusted scripts are harmless.

There is no OpenAI hosting configuration or hosted Lab endpoint in this
package.

A publisher identity belongs to one publication, never to an application
account or person. If the recorded private key for an existing publication is
missing, publishing fails closed; the Lab does not silently replace that
identity. Relays receive public signed commitments and content bytes only.
They never receive the private publisher key.

Routing also fails closed. The Lab must reject stripped publisher directives
and stale or forged policy evidence, report passthrough when policy selected
passthrough rather than claiming a direct route, and never silently downgrade a
required one-hop route. A simulated relay advertising both passthrough and host
modules retains separate credentials, rate limits, and audit evidence for each
module so co-location does not collapse metadata boundaries.

Removing a site or workspace removes that local Lab project and its local
runtime history. It does not unpublish already replicated immutable revisions,
release host storage, or delete the publication key from Keychain. **Destroy
Publisher Identity** is a separate irreversible operation: it deletes the
local private key and permanently removes this installation's ability to sign
another update under that publisher identity. Destroying the key still does
not erase revisions already held by hosts or other caches.

<a id="build-and-test"></a>

## Development

From the repository root:

```sh
swift build --package-path apps/noctweb-lab
swift test --package-path apps/noctweb-lab
```

## Documentation

| Read | For |
| --- | --- |
| [Project overview](../../README.md) | Network architecture and implementation status |
| [Relay integration](../../docs/noctweave-integration.md) | Host capabilities and authentication |
| [Host connection design](../../docs/adr/0010-connect-noctweb-lab-to-host-relays.md) | Live publishing and receipt verification |
| [Protocol workbench](../../spec/README.md) | Unfinished protocol and conformance work |
| [Release guide](APP_STORE_RELEASE.md) | Signing and distribution requirements |

## License

Part of Noctweave Net, licensed under [AGPL-3.0-or-later](../../LICENSE).
