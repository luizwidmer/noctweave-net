# Noctweb end-user access

Noctweb has one authoritative browsing product and two deliberately narrower
compatibility surfaces.

| Surface | Purpose | May resolve and execute finalized sites? |
| --- | --- | --- |
| **Noctweb Browser** | Everyday navigation, verification, permissions, and rendering | Yes |
| **Noctweb Lab** | Native authoring, inspection, deterministic testnet, and fault injection | Only its explicit experimental profiles |
| **Noctweb Publisher** | Basic relay-hosted authoring and hosted-preview links | No consensus-backed named resolution |
| **Browser extension** | Optional `noct://` recognition and native-app handoff | No |

Noctweb Browser is a dedicated native application. The first implementation is
a macOS SwiftUI application using the same verified WebKit rendering boundary
as Noctweb Lab. It is not a hosted website, PWA, Electron shell, browser
extension, or full Chromium/WebKit fork.

## What a user opens

The canonical named-site base remains:

```text
noct://<site>.<relay-suffix>/
```

A later navigation profile may extend that base with a path, query, and
fragment:

```text
noct://<site>.<relay-suffix>/<path>?<query>#<fragment>
```

Only the canonical authority selects the finalized namespace record. A path,
query, or fragment is publication-local navigation state and can never select
another publisher, routing trust domain, or host. The exact normalization and
encoding rules must be frozen with conformance vectors before they become a
stable protocol promise. The current Lab remains base-address-only.

A user reaches a site in one of four ways:

1. Paste or type a `noct://` URL into Noctweb Browser.
2. Click a `noct://` link. The operating system opens the registered Noctweb
   Browser application.
3. Open a bounded `.noctlink` access descriptor when the link must also identify
   a routing trust domain or carry bootstrap hints.
4. Open a relay HTTPS **Hosted preview** link. This is the current compatibility
   path before consensus naming exists and is never presented as finalized
   Noctweb navigation.

There is no mandatory central redirector, Noctweave-operated gateway, account,
or globally operated default relay.

An enabled host relay should eventually advertise its optional absolute
Publisher launch URL in its authenticated capability document. That URL is a
convenience entry point to authoring and Hosted previews, not a namespace or
resolution endpoint.

## Network profiles

Resolving a `noct://` name requires an explicit local
`NoctwebNetworkProfile`. A profile conceptually contains:

- a version and local display name;
- the routing trust-domain identifier;
- the consensus profile identifier and verification material;
- bounded bootstrap endpoints;
- supported protocol epochs and suites; and
- the visitor's default `open`, `direct`, or `passthrough` preference.

A network profile is resolver configuration, not a user identity, account,
device registration, publisher key, or recovery authority. The browser may
hold multiple profiles.

The browser selects a profile by a finalized suffix claim. If no installed
profile proves the suffix, resolution stops and the user may import a profile.
If multiple profiles claim the same textual name, the browser shows the
conflict and requires an explicit choice. It never silently resolves the same
`noct://` text under a different trust domain.

Bookmarks, history, and open tabs retain both the canonical URL and the routing
trust-domain identifier. The address bar always exposes the active profile.
The Browser also exposes the visitor's per-tab `open`, `direct`, or
`passthrough` preference; it cannot weaken a higher policy layer.

## Portable access descriptors

A `.noctlink` descriptor is a bounded launch object containing:

- its format version;
- a canonical `noct://` URL;
- a routing trust-domain identifier;
- an optional expected publisher identifier; and
- bounded consensus or relay bootstrap hints.

The descriptor and every bootstrap endpoint are untrusted hints. They cannot
override consensus finality, a publisher signature, federation policy, host
operator policy, or object verification. Importing a previously unknown
network profile requires explicit user confirmation and a visible trust-domain
fingerprint.

The deterministic Browser profile deliberately ignores bootstrap hints.
Production network adapters must re-resolve and reject unsafe public endpoint
targets, require an explicit local-profile opt-in for loopback or private
targets, and enforce an expected publisher pin before downloading publication
objects.

The exact descriptor encoding and any signing profile remain provisional until
the object and consensus suites freeze.

## Browser resolution pipeline

Noctweb Browser performs these steps before rendering:

1. Parse and canonicalize the URL.
2. Select an explicit network profile and routing trust domain.
3. Verify the finalized suffix and site-label binding to a
   publication-scoped publisher identifier.
4. Verify the finalized publisher head, protocol epoch, and current host
   locators.
5. Authenticate federation policy and host-operator policy, then apply the
   first non-`open` directive in federation, host operator, signed publisher,
   visitor order.
6. Fetch through exactly one permitted shape: directly to a host or through one
   bounded passthrough and then the host.
7. Verify finality evidence, publisher continuity, object digests, bundle
   bounds, signatures, and the route actually used.
8. Assign a publication-scoped internal origin and render in a non-persistent,
   capability-limited sandbox.

No document receives a visible verified page state until every required check
passes. HTTPS protects endpoint transport; it does not establish publisher or
content authority.

## Browser chrome and trust state

The minimum browser UI contains:

- an address bar and back, forward, reload, and stop controls;
- tabs, local bookmarks, and local history;
- a network-profile selector;
- a trust panel showing publisher identifier, finalized head, trust domain,
  selected route, host, and verification time;
- explicit **Finalized**, **Hosted preview**, **Stale**, **Offline verified
  cache**, and **Blocked** states; and
- per-publication permission controls.

The suffix operator and content host are displayed as infrastructure, not as
publisher identity. A hosting receipt may produce **Hosted preview**, never
**Finalized**.

History, bookmarks, permissions, and capability secrets stay local. Capability
URLs are excluded from ordinary history and telemetry by default.
Until capability syntax is frozen, the native MVP treats every query- or
fragment-bearing address as potentially capability-bearing and excludes it
from bookmarks and history.

## Conventional-browser bridge

Ordinary web pages may use a normal link such as:

```html
<a href="noct://site.relay-suffix/">Open in Noctweb</a>
```

The operating system launches Noctweb Browser when it is installed. An optional
extension may additionally recognize typed links, offer an omnibox shortcut,
and hand the exact URL or `.noctlink` descriptor to the native application.

The extension:

- does not resolve consensus;
- does not fetch or render Noctweb sites;
- does not store publisher keys or capability authority;
- does not receive decrypted site content or browsing history from the app;
- does not downgrade a failed native verification into a web preview; and
- remains unnecessary when the operating-system protocol handler is sufficient.

## Hosted preview compatibility

Noctweb Publisher currently produces relay HTTPS links that identify an exact
hosted object. Its viewer verifies the host receipt, object digest, and
publisher signature before sandboxed rendering.

That mode is useful for testing and sharing before the production browser and
consensus profile exist, but it has weaker claims:

- the relay may disappear;
- the displayed `noct://` name is provisional;
- no namespace record, publisher head, or locator is consensus-finalized; and
- the HTTPS origin is a compatibility surface, not the site's Noctweb origin.

Noctweb Browser may later import the same exact hosted-preview evidence and
display it in an explicitly unfinalized mode.

## First implementation sequence

1. Extract a reusable `NoctwebRuntimeCore` from Noctweb Lab's address parser,
   resolver boundary, verification pipeline, routing policy, and isolated
   renderer contract.
2. Add `apps/noctweb-browser/` as a signed native macOS application.
3. Register `noct` URLs and `.noctlink` documents with the operating system.
4. Implement local network-profile import, conflict handling, and trust display.
5. Ship address-bar navigation against the deterministic test profile, then the
   selected production `ConsensusAdapter`.
6. Add local tabs, bookmarks, history, permission state, and verified offline
   cache.
7. Assess the optional extension only after native handoff and fail-closed
   verification are complete.

The native MVP now completes the application shell, OS registration, strict
URL and descriptor decoding, deterministic-profile navigation, local tabs,
bookmarks and history, visible fixture verification, routing-policy evaluation,
and the publication-scoped renderer. It intentionally does not claim the
production portions of steps 4–6: profile import, consensus finality,
host/passthrough retrieval, permissions, and verified offline cache remain.

## Acceptance gates

- Clicking and pasting a `noct://` URL opens the native Browser.
- Two clients with the same profile resolve the same finalized publisher and
  head.
- Unknown, ambiguous, stale, reorganized, or forged trust-domain evidence fails
  closed before rendering.
- A site survives host replacement without changing its canonical name,
  publisher identity, or verified object identity.
- Direct and one-passthrough retrieval obey the authority hierarchy exactly.
- A Hosted preview is never labeled Finalized.
- The extension can be removed without losing browser identity, keys,
  bookmarks, permissions, or the ability to open OS-registered links.
