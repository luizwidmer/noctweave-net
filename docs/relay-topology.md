# Relay Topology

Capsule Net recognizes exactly three relay roles. Additional behavior belongs
in a client, host service, or consensus adapter—not in a fourth relay type.

## Standard relay

A standard relay is the existing Noctweave opaque transport role.

It may:

- create, renew, tear down, append to, synchronize, and commit bounded opaque
  routes using the supported Noctweave surface;
- carry encrypted Capsule Net control or collaboration events;
- store encrypted blobs when the operator enables the bounded blob module;
- expose exact health and capability information.

It must not:

- resolve publisher identities;
- index capsule semantics;
- forward traffic to other relays as federation;
- vote in Capsule Net consensus merely by operating a relay;
- decrypt private payloads or log ciphertext bodies and bearer capabilities.

Standard relays remain direct client submission endpoints. Existing
Noctweave federation is not part of the Capsule Net topology.

## Passthrough relay

A passthrough relay forwards one bounded opaque exchange to one explicit next
hop chosen by the client. Its purpose is path indirection and transport
compatibility, not discovery, routing intelligence, or durable delivery.

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

The v0 profile permits at most one passthrough hop. Multi-hop privacy designs
require a separate threat model and are out of scope.

## Host relay

A host relay stores and serves content-addressed capsule objects. A person may
self-host one, and a provider may operate it as a hosting service.

It may:

- accept bounded objects whose bytes match their declared object IDs;
- return immutable objects by object ID;
- issue bounded signed hosting receipts;
- enforce tenant, storage, bandwidth, retention, and abuse policy;
- mirror public objects when policy permits;
- advertise expiring public retrieval endpoints through the consensus profile.

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
- finalize publisher heads;
- possess private capsule keys by protocol requirement;
- turn hosting credentials into a global Capsule Net account.

## Co-located roles

One process or operator may enable multiple roles, but capability discovery
must list them independently. Each role requires separate rate limits,
credentials, policy, storage lifetime, and audit boundaries.

A failure or compromise in one role must not silently grant authority in
another. In particular:

- passthrough authorization does not grant host write access;
- host tenancy does not grant standard-route read authority;
- standard relay administration does not grant consensus signing authority.

## Topology examples

Self-hosted publication:

```text
publisher runtime -> own host relay
                  -> consensus adapter (head + locators)
reader runtime    -> own host relay
```

Hosted publication:

```text
publisher runtime -> hosting provider's host relay
                  -> consensus adapter (head + locators)
reader runtime    -> selected host relay
```

Indirect retrieval:

```text
reader runtime -> passthrough relay -> host relay
```

Private collaboration:

```text
sender runtime -> recipient's standard Noctweave relay -> recipient runtime
```
