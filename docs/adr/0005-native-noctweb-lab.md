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
- There is no PWA, service worker, browser authentication adapter, Electron
  shell, or WebView.
- Publication private keys are stored in the macOS Keychain.
- The `lab-v0` preview accepts only bounded structured site fields and renders
  them directly with SwiftUI.
- Network and consensus behavior is accessed through replaceable native
  adapters. The initial adapters are deterministic local simulations.
- A future browser extension may hand off `noct://` links, but cannot own keys,
  consensus verification, capabilities, or execution.

## Consequences

- The Lab has an explicit macOS 14 or later platform boundary.
- A local package build can produce a launchable application without a web
  server, browser, or network connection.
- Native code signing and Keychain identity must remain stable across releases.
- Browser-based conformance clients, if added later, are separate test tools and
  are not the Noctweb Lab product.
