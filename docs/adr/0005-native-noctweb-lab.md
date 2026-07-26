# ADR 0005: Ship Noctweb Lab only as a native macOS application

- Status: Accepted
- Date: 2026-07-25

## Context

Noctweb Lab holds publication authority, verifies signed heads and immutable
objects, simulates relay faults, and renders the result. Delivering that product
as an ordinary hosted application would make a web origin and hosting provider
part of the application lifecycle and would confuse the test platform with a
Noctweb website.

## Decision

Noctweb Lab is a native macOS SwiftUI application distributed as a signed
`.app` bundle.

- There is no hosted Lab endpoint or OpenAI Sites project configuration in the
  repository.
- There is no PWA, browser authentication adapter, Electron shell, or
  remote-origin WebView application shell.
- Publication private keys are stored in the macOS Keychain.
- The native Design/Code/Preview editor works with ordinary website files.
  Visual blocks generate normal HTML, CSS, and JavaScript; Code mode and folder
  import accept agent-authored projects and self-contained production builds.
- The `noctweb-lab-v1` runtime accepts only bounded canonical website bundles
  after publisher and object verification. It renders those files with WebKit
  under a publication-scoped custom origin, a non-persistent store, no native
  message bridge, and no website access to external network resources.
- Client-side JavaScript and compiled framework code are supported. Node.js,
  SSR, backend APIs, development servers, hot-module replacement, remote CDN
  dependencies, and service workers are not.
- The packaged app uses the macOS App Sandbox with read-only user-selected file
  access. WebKit's networking process requires the network-client entitlement;
  the verified custom-scheme loader, content security policy, navigation
  delegate, and WebRTC guard enforce the website-level network boundary.
- Network and consensus behavior is accessed through replaceable native
  adapters. The initial adapters are deterministic local simulations.
- A future browser extension may hand off `noct://` links, but cannot own keys,
  consensus verification, capabilities, or execution.

## Consequences

- The Lab has an explicit macOS 14 or later platform boundary.
- A local package build can produce a launchable application without a web
  server, browser, or network connection.
- WebKit is a bounded website-execution component inside the verified native
  product; it does not make the Lab a hosted web app or browser wrapper.
- Native code signing and Keychain identity must remain stable across releases.
- Browser-based conformance clients, if added later, are separate test tools and
  are not the Noctweb Lab product.
