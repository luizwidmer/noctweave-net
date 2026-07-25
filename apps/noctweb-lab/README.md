# Noctweb Lab for macOS

Noctweb Lab is the native macOS development environment for building, signing,
publishing, resolving, and testing Noctweb sites. It is a SwiftUI application,
not a website, progressive web app, browser wrapper, Electron bundle, or
WebView shell.

The Lab currently implements the explicitly incompatible `lab-v0` profile. It
is a local protocol simulator and product-development surface; it does not
claim production consensus or wire-format compatibility.

## What is native

- The entire product interface is built with SwiftUI.
- Site previews are rendered from validated structured site fields using
  native SwiftUI views. HTML, JavaScript, and Markdown are never executed.
- Each publication receives its own Ed25519 publisher key. Private key
  material is stored in the macOS Keychain and marked non-synchronizable.
- Workspace drafts, topology, revisions, and test runs are stored locally in
  Application Support.
- Standard, passthrough, and host relay roles are represented independently.
- Integrity, publisher authority, and mock-consensus finality are reported as
  separate trust evidence.

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

The packaging script creates and verifies an ad-hoc signed application bundle.
Set `NOCTWEB_CODESIGN_IDENTITY` to a Developer ID certificate name when a
distribution-signed build is required.

## Security boundary

A publisher identity belongs to one publication, never to an application
account or person. If the recorded private key for an existing publication is
missing, publishing fails closed; the Lab does not silently replace that
identity. Relays receive public signed commitments and content bytes only.
They never receive the private publisher key.
