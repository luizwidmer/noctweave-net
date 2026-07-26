# ADR 0009: Make the native Noctweb Browser the primary access path

- Status: Accepted
- Date: 2026-07-26
- Amends: ADR 0003

## Context

ADR 0003 selected a dedicated native runtime, while ADR 0008 added a bounded
relay-hosted authoring and preview surface. The product still needs one
unambiguous answer for how visitors open a site, how a `noct://` URL reaches the
correct routing trust domain, what an extension may do, and how pre-consensus
Hosted previews differ from finalized browsing.

A conventional browser origin cannot safely become the authority for consensus
verification, publisher continuity, capability storage, permissions, or active
content origins. A full browser-engine fork is also unnecessary for the first
runtime because Noctweb needs verified object resolution and an isolated
renderer, not compatibility with the server-authoritative HTTP origin model.

## Decision

**Noctweb Browser**, a dedicated native application, is the authoritative
end-user access path.

The first Browser implementation is a macOS SwiftUI application that reuses an
extracted `NoctwebRuntimeCore` and the verified WebKit sandbox boundary proven
by Noctweb Lab. It is not a hosted website, PWA, Electron application, browser
extension, or full browser-engine fork.

The Browser registers the `noct` URL scheme with the operating system. Users
may paste a `noct://` URL, click one from another application, or open a bounded
`.noctlink` descriptor. A conventional browser extension is optional and may
only recognize or hand links to the native Browser. It cannot own publisher
keys, capability authority, consensus verification, permissions, origins, or
execution.

Every named resolution occurs inside an explicit local
`NoctwebNetworkProfile`. A profile binds the browser to one routing trust
domain, consensus profile and verification material, bounded bootstrap
endpoints, supported epochs, and a default visitor route preference. It is
local resolver configuration, not an account, global identity, device
registration, or recovery authority.

A bare `noct://` URL is resolved only when an installed profile proves its
finalized suffix claim. Unknown suffixes remain unresolved. Conflicting claims
require an explicit user choice and visible trust-domain fingerprint; a default
profile never silently changes the meaning of a textual URL. Tabs, bookmarks,
and history retain the trust-domain identifier together with the canonical
URL.

A `.noctlink` descriptor may carry a canonical URL, routing trust-domain
identifier, optional expected publisher identifier, and bounded bootstrap
hints. It is a launch hint, not authority. Consensus finality, publisher
signatures, object digests, and route-policy verification remain mandatory.
Its exact encoding stays provisional until the stable object and consensus
profiles freeze.

The canonical namespace record continues to use
`noct://<site>.<relay-suffix>/`. A later navigation profile may add a path,
query, and fragment, but those components are publication-local and cannot
select another publisher, trust domain, or host.

Before rendering, the Browser:

1. selects and verifies the network profile;
2. resolves finalized namespace, publisher-head, and locator state;
3. applies federation, host-operator, signed-publisher, then visitor routing
   priority;
4. fetches directly or through one bounded passthrough;
5. verifies finality, publisher continuity, signatures, digests, bounds, and
   route evidence; and
6. renders under a publication-scoped internal origin with no ambient native or
   relay authority.

The Browser UI distinguishes **Finalized**, **Hosted preview**, **Stale**,
**Offline verified cache**, and **Blocked**. A host receipt alone can never
produce Finalized.

Until a production consensus profile exists, visitors may use the implemented
relay HTTPS viewer as a **Hosted preview**. It verifies exact bytes and the
publisher signature but remains relay-dependent and unfinalized. No central
Noctweave gateway or mandatory redirect service is introduced.

Noctweb Lab remains the native developer, authoring, inspection, and fault
injection application. Noctweb Publisher remains the basic relay-hosted
authoring surface. Neither is the everyday authoritative Browser.

## Consequences

- The security boundary is the installed native Browser, not an extension or
  relay website.
- `noct://` links work through normal operating-system application handoff.
- Users can install multiple network profiles without silently conflating trust
  domains.
- The first Browser can reuse audited resolver and renderer components instead
  of forking a general-purpose browser engine.
- Hosted previews provide an immediate access path without overstating
  consensus or naming guarantees.
- Search, profile distribution, capability-link encoding, cross-platform app
  packaging, and extension packaging remain separate protocol or product work.
