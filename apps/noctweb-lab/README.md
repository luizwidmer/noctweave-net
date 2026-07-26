# Noctweb Lab for macOS

Noctweb Lab is the native macOS development environment for building, signing,
publishing, resolving, and testing Noctweb sites. The product shell, project
management, publisher authority, relay controls, and verification surfaces are
native SwiftUI. The Lab is not a hosted website, progressive web app, browser
extension, Electron bundle, or remote-origin WebView shell.

The Lab currently implements the explicitly incompatible `noctweb-lab-v2`
website-bundle and relay-scoped namespace profile. It is a local protocol
simulator and
product-development surface; it does not claim production consensus,
wire-format compatibility, or production sandboxing. Its deterministic relay
adapters model standard, passthrough, and host behavior but do not yet connect
the application to live Noctweave relay endpoints.

## Website workflow

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

## Signed website bundles

A `noctweb-lab-v2` object carries a canonical website bundle with:

- one normalized relative entry path;
- at most 512 files;
- at most 16 MiB of exact file bytes in total;
- a media type for every file; and
- no absolute, traversing, duplicate, or case-conflicting paths.

The bundle is covered by the content digest and the publication-scoped
publisher signature. Host and passthrough relays can move or retain the bytes,
but cannot alter a file without failing verification.

Each publication receives its own Ed25519 publisher key. Private key material
is stored in the macOS Keychain and marked non-synchronizable. Workspace
drafts, topology, revisions, and test runs are stored locally in Application
Support. Standard, passthrough, and host relay roles remain independent, and
the Lab reports integrity, publisher authority, and mock-consensus finality as
separate evidence.

## Relay-scoped names

The Lab models canonical public base URLs as:

```text
noct://<site>.<relay-suffix>/
```

Each namespace relay is one of the Lab's host relays, not a fourth relay role.
An operator may choose a custom suffix, or use the profile's deterministic
`r-<hash>` fallback derived from a dedicated namespace public key. Site labels
are unique only within one suffix, so two different suffixes may each allocate
the same label.

The Lab's deterministic topology rejects duplicate visible suffixes, and its
in-process finality model rejects a second publication claiming the same full
name. This is a local test stand-in: a production consensus profile must
finalize globally unique suffix allocations and unique site-label bindings
within each suffix. The binding resolves to the site's publication-scoped
publisher identity. The namespace relay does not gain the publisher key and
need not be the current content host; resolution uses current host locators and
verifies the publisher signature and exact bundle bytes.

## Verified website runtime

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

## Run from source

```sh
swift run --package-path apps/noctweb-lab NoctwebLab
```

## Build and test

```sh
swift build --package-path apps/noctweb-lab
swift test --package-path apps/noctweb-lab
```

## Package the application

```sh
apps/noctweb-lab/scripts/package-app.sh
open "apps/noctweb-lab/dist/Noctweb Lab.app"
```

The packaging script creates and verifies an ad-hoc signed application bundle
with the Lab's App Sandbox entitlements.
Set `NOCTWEB_CODESIGN_IDENTITY` to a Developer ID certificate name when a
distribution-signed build is required.

## Security boundary

A publisher identity belongs to one publication, never to an application
account or person. If the recorded private key for an existing publication is
missing, publishing fails closed; the Lab does not silently replace that
identity. Relays receive public signed commitments and content bytes only.
They never receive the private publisher key.

Removing a site or workspace removes that local Lab project and its local
runtime history. It does not unpublish already replicated immutable revisions,
release host storage, or delete the publication key from Keychain. **Destroy
Publisher Identity** is a separate irreversible operation: it deletes the
local private key and permanently removes this installation's ability to sign
another update under that publisher identity. Destroying the key still does
not erase revisions already held by hosts or other caches.
