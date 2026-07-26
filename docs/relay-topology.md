# Relay Topology

Noctweave Net recognizes exactly three relay/module families: standard,
passthrough, and host. Additional behavior belongs in a client, one of those
modules, a host service, or a consensus adapter—not in a fourth relay type.
Role labels describe boundaries; they do not make module advertisements
exclusive. One relay process may advertise multiple modules.

## Standard relay

A standard relay is the existing Noctweave opaque transport role.

Its current private-delivery dependency is `nw.opaque-route@2`.

It may:

- create, renew, tear down, append to, synchronize, and commit bounded opaque
  routes using the supported Noctweave surface;
- carry encrypted Noctweave Net control or collaboration events;
- store encrypted blobs when the operator enables the bounded blob module;
- expose exact health and capability information.

It must not:

- resolve publisher identities;
- index capsule semantics;
- forward traffic to other relays as federation;
- vote in Noctweave Net consensus merely by operating a relay;
- decrypt private payloads or log ciphertext bodies and bearer capabilities.

Standard relays remain direct client submission endpoints. Existing
Noctweave federation forwarding is not part of the Noctweave Net topology.

A `solo` standard relay may also advertise `nw.net-host@1`. In that
configuration the same process can directly host and serve content, but the
standard and host modules retain separate authorization and limits. Hosting
does not become a standard-module operation. Such a deployment may serve the
same-origin Noctweb Publisher page only as part of its separately opted-in host
surface.

## Passthrough relay

A passthrough relay forwards one bounded opaque exchange to one explicit next
hop chosen by the client. Its purpose is path indirection and transport
compatibility, not discovery, routing intelligence, or durable delivery.

Its current wire surface is `nw.net-passthrough@1 forward`.

It may:

- accept an authenticated, size-bounded forwarding request;
- connect to a policy-valid public next hop;
- stream a bounded response back to the requester;
- retain short-lived operational counters that contain no bodies, tokens, or
  capability material.

It must:

- avoid durable request or response body storage;
- reject loopback, private, link-local, multicast, ambiguous, and disallowed
  destinations unless an operator explicitly configures an isolated trust
  domain;
- prevent DNS rebinding and validate the resolved destination through the
  connection lifecycle;
- enforce time, byte, concurrency, redirect, and hop limits;
- bind authorization to the requested forwarding class;
- advertise that it is not an anonymity service.

It must not:

- discover the next hop on the client's behalf;
- accept an unbounded proxy or general-purpose `CONNECT`;
- create recursive relay chains by default;
- cache or mutate capsule objects;
- claim delivery after merely accepting a transient forwarding request.

The v0 profile permits at most one passthrough hop. Public retrieval is either
direct to a host or through one passthrough and then the host. Those are
alternatives, never a required standard-to-passthrough-to-host chain. Multi-hop
privacy designs require a separate threat model and are out of scope.

## Host relay

A host relay stores and serves content-addressed capsule objects. A person may
self-host one, and a provider may operate it as a hosting service.

Its current wire surface is `nw.net-host@1` with `put`, `get`, `has`, and
`release`.

It may:

- accept bounded objects whose bytes match their declared object IDs;
- return immutable objects by object ID;
- issue bounded signed hosting receipts;
- serve the simple Noctweb Publisher page and its upload API from one origin
  when the operator explicitly enables that surface;
- enforce tenant, storage, bandwidth, retention, and abuse policy;
- mirror public objects when policy permits;
- advertise expiring public retrieval endpoints through the consensus profile;
- optionally advertise the namespace function for one consensus-allocated
  suffix, including a custom operator suffix or the profile's deterministic
  `r-<hash>` fallback.

It must:

- verify an object's digest before acknowledging storage;
- keep publisher authority separate from hosting authorization;
- treat private objects as opaque ciphertext;
- return exact stored bytes;
- make retention and deletion semantics explicit;
- expose no claim stronger than the storage commitment it actually provides.

It must not:

- become authoritative because it serves an object;
- rewrite, render, or execute hosted capsule code;
- sign a publisher head or present a hosting receipt as consensus finality;
- finalize publisher heads;
- possess private capsule keys by protocol requirement;
- turn hosting credentials into a global Noctweave Net account.

A host can store and directly serve content without a passthrough module,
federation forwarding, a consensus retrieval hop, or namespace ownership.

Signed publication bundles remain opaque relay payloads. Browser clients must
verify their object digest and publication-scoped publisher signature before
rendering active content in a sandbox that does not inherit the Publisher
page's same-origin authority.

### Publisher surface

Noctweb Publisher does not add a topology role. It is served by a dedicated
host relay or by a standard relay process that has separately enabled the host
module. A standard-only relay cannot host the page or accept publication
bundles.

The editor accepts HTML, CSS, JavaScript, assets, and browser-ready compiled
React bundles. Compilation, package installation, server-side rendering, and
development servers remain client tooling rather than relay services.

One browser-local signing key is created per publication and never sent to the
relay. The host signs only a bounded receipt for the exact accepted bundle.
The resulting UI state is **Hosted**, not consensus-finalized. Continued
availability and name allocation remain separate claims.

### Namespace function

The namespace function is an optional advertisement by a relay with the host
module, not a fourth relay role and not a prerequisite for hosting. Consensus
eventually owns global suffix uniqueness and unique site-label allocation
within each suffix. An operator may configure a suffix; otherwise Noctweb
Publisher derives its provisional `r-<hash>` fallback from the public key that
verifies the host's signed receipts.

The namespace relay is the host relay associated with the suffix. It is not
automatically the current content host for every publication under that suffix.
A finalized name record binds the canonical
`noct://<site>.<relay-suffix>/` URL to a publication-scoped publisher
identifier; independently finalized locators identify current content hosts.
Neither suffix control nor name allocation grants authority to sign or advance
the publication head.

No consensus naming profile is implemented yet. Current Publisher displays of
`noct://` names are provisional namespace hints, even when the suffix is
operator-configured. They do not prove global uniqueness, finality, or portable
resolution.

## Retrieval-policy authority

The only v0 public retrieval shapes are:

```text
visitor -> host
visitor -> passthrough -> host
```

The effective hard route directive is the first non-`open` value in this strict
authority order:

1. federation policy for the authenticated routing trust domain;
2. host-relay operator advertisement;
3. signed publisher directive; and
4. visitor preference.

If all layers are open, direct is the deterministic default. A higher
requirement cannot be weakened or widened by a lower layer. Required
passthrough fails closed when unavailable and never silently downgrades to
direct.

“Federation policy” is product terminology for an authenticated Noctweave Net
routing trust-domain/control-plane constraint. It is not a fourth relay role,
a forwarding hop, `nw.federation` discovery, or content authority. Existing
consensus may finalize or share the selected policy record; consensus is still
not a retrieval hop.

Experimental `noctweb-lab-v3` signs the publisher directive. V2
relay-namespace publications remain verifiable and upgradeable, while v1 is
legacy read-only. Operator advertisements and federation-policy records require
authentication in production; the Lab uses deterministic local adapters.

## Co-located modules

One process or operator may enable multiple modules, but capability discovery
must list them independently. Each module requires separate rate limits,
credentials, policy, storage lifetime, and audit boundaries.

A failure or compromise in one module must not silently grant authority in
another. In particular:

- passthrough authorization does not grant host write access;
- host tenancy does not grant standard-route read authority;
- standard relay administration does not grant consensus signing authority.

Co-locating passthrough and host modules also collapses the intended metadata
separation: one operator can correlate both sides of the nominal hop. UI and
audit records must report that topology accurately. Separate module
credentials and rate limits remain mandatory even though they cannot prevent
operator-level traffic correlation.

## Topology examples

Solo self-hosted publication and direct retrieval:

```text
Publisher browser -> solo standard relay + nw.net-host@1
                  -> opaque signed bundle + hosting receipt
                  -> consensus adapter (head + locators)
visitor runtime   -> same relay's nw.net-host@1
```

Hosted publication:

```text
publisher runtime -> selected content host relay(s)
                  -> optional namespace function (suffix + name request)
                  -> consensus adapter (name + head + locators)
reader runtime    -> selected current content host relay
```

One-hop retrieval alternative:

```text
reader runtime -> passthrough relay -> host relay
```

Neither example includes federation forwarding or a consensus retrieval hop.

Private collaboration:

```text
sender runtime -> recipient's standard Noctweave relay -> recipient runtime
```
