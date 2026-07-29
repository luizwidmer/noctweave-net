# ADR 0008: Add the relay-hosted Noctweb Publisher surface

- Status: Accepted
- Date: 2026-07-26
- Amends: ADR 0003, ADR 0004, and ADR 0006
- Amended by: ADR 0009 and ADR 0011

## Context

Noctweave Net needs a minimal public publishing path that works in an ordinary
browser before the consensus naming and production Noctweb Browser profiles are
complete. Requiring the native Noctweb Lab for every basic upload would make
relay self-hosting harder to exercise. Turning the publisher into a new relay
role, a hosted account authority, or a server-side build service would violate
the existing topology and security boundaries.

The browser page and upload endpoint benefit from a same-origin deployment, but
hosted HTML and JavaScript cannot be allowed to inherit the publisher
application's origin authority. A successful relay upload also cannot be
presented as consensus publication or naming finality.

## Decision

The initial public authoring surface is **Noctweb Publisher**, a simple browser
page served from the same origin as an explicitly enabled host endpoint. It may
be served by:

- a `solo` standard relay process that also advertises and isolates
  `nw.net-host@1`; or
- a dedicated host relay.

Noctweb Publisher is a client/product surface over the host module. It does not
add a fourth role: the topology remains exactly `standard`, `passthrough`, and
`host`. A standard-only relay cannot serve the Publisher hosting API.

The Publisher surface and every capability- or authentication-bearing host
operation require direct loopback access or an operator-declared trusted TLS
reverse proxy. Remote plaintext HTTP fails closed. This protects the relay
password in transit and gives the browser the secure context needed for
WebCrypto, nonextractable publication signing keys, and encrypted local
release state.

The editor supports ordinary HTML, CSS, JavaScript, and assets. It may import
browser-ready static bundles already compiled by tools such as React and Vite.
The relay does not install packages, compile React source, run a development
server, perform server-side rendering, or execute arbitrary hosted code.

Each new publication receives a distinct signing identity generated and
retained by the browser. The private signing key:

- remains browser-local;
- is scoped to one publication;
- is never uploaded to the relay;
- is not a relay login, hosting credential, global account, recovery
  authority, or Noctweave relationship key.

The browser signs the bounded publication bundle before upload. The relay
stores the exact signed bundle as opaque bytes. It may validate the bounds and
object identifier required by the host contract, but it signs only a bounded
hosting receipt. It never signs or advances a publisher head.

The Publisher verifies the hosting receipt before setting upload status to
**Hosted**. Hosted means only that the relay acknowledged the exact bundle
under the receipt's stated bounds. It does not establish consensus finality,
publisher authority, content endorsement, permanent availability, or a
globally allocated name. On reload, the Publisher revalidates the cached
receipt and current object presence before restoring Hosted status.

Each successfully hosted revision has an independent release capability. The
Publisher encrypts those capabilities with AES-GCM and keeps a bounded
browser-local ledger so replacing a revision does not abandon older hosted
copies. Unhost-all attempts every tracked release and retains failed entries
for retry. Release capabilities are disclosed to the host only in explicit
release requests.

For solo development, Publisher may derive a local fallback suffix from the
public key used to verify that host's signed receipts. ADR 0011 supersedes this
fallback for federation: every federated standard or host relay configures a
suffix and proves its ownership through threshold-verified signed namespace
snapshots.

Publisher application resources and the host upload API share an origin.
Hosted active content does not. A client must verify the bundle digest and
publication-scoped publisher signature before rendering the content in a
sandbox that receives no ambient Publisher-origin credentials or relay
authority. The host relay stores and serves bytes; it does not render or
execute them.

Noctweb Browser remains the future authoritative browsing runtime, and Noctweb
Lab remains the native macOS test and authoring application described by ADR
0003. Noctweb Publisher does not turn either native application into a hosted
web app.

The Publisher's `/noctweb/?object=<object-id>` HTTPS viewer is the temporary
cross-user **Hosted preview** path. It verifies the receipt, exact object bytes,
and publisher signature before sandboxed rendering, but it does not resolve the
displayed provisional `noct://` name. ADR 0009 defines the native Browser as the
authoritative finalized access path.

## Consequences

- A self-hoster can expose a basic authoring page from the same process that
  opts into standard and host modules without introducing another role.
- A provider can expose the same bounded surface from a dedicated host relay.
- Publisher identity survives host replacement only while the browser-local
  key remains available; host credentials cannot forge an update.
- Same-origin deployment simplifies the page-to-host API boundary, while
  verified active content still requires a separate sandbox boundary.
- React projects must arrive as browser-ready compiled output; build services
  remain outside the relay.
- Product UI and documentation must distinguish **Hosted** from any future
  finalized publication or name state.
- A relay HTTPS preview remains relay-dependent and is never the canonical
  Noctweb site origin.
- Backup, rotation, recovery, consensus submission, finalized naming, and
  production sandbox conformance remain later protocol work.
