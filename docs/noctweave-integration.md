# Noctweave Integration

Noctweave Net runs behind Noctweave's exact relay envelope. It does not define
a parallel listener, discovery service, account system, or transport framing.

## Role and module matrix

Noctweave Net retains exactly three relay/module families. A role label does
not make module advertisements mutually exclusive: one process may advertise
more than one family.

| Module family | Advertised application module | Noctweave Net use |
| --- | --- | --- |
| `standard` | `nw.opaque-route@2` and enabled standard modules | Private invitations, collaboration, capability delivery, and control events |
| `passthrough` | `nw.net-passthrough@1` | One bounded authenticated forward to one operator-allow-listed public HTTPS Noctweave endpoint |
| `host` | `nw.net-host@1` | Content-addressed object storage, retrieval, presence, and capability-protected release |

Every relay process also advertises `nw.core@2` for health, information, and
exact capability discovery. In particular, a `solo` standard relay may also
advertise `nw.net-host@1` and directly host and serve content. Advertising the
host module does not require the passthrough module, federation forwarding, a
consensus retrieval hop, or a namespace advertisement.

Every advertised module keeps separate credentials, rate limits, policy,
storage lifetime, and audit boundaries. A module advertisement grants no
implicit capability in another module.

## Host object contract

`nw.net-host@1` addresses every payload by the lowercase hexadecimal SHA-256
digest of its exact bytes.

- `put` verifies the digest before storage and accepts bounded TTL,
  idempotency, and a client-generated release-capability digest.
- `get` returns the exact bytes plus an Ed25519-signed hosting receipt.
- `has` reports current presence and expiry without proving future
  availability.
- `release` requires the 32-byte capability whose domain-separated digest was
  committed by `put`.

The relay signs storage receipts, not publisher heads. A host signature proves
only that the host acknowledged those exact bytes and bounds. `get` and `has`
are public by object ID; `put` and `release` require relay authentication.
Private hosted objects must already be encrypted by the client.
The host module does not require the relay to own or advertise a Noctweb
namespace.

## Passthrough contract

`nw.net-passthrough@1 forward` carries an opaque HTTP relay request and returns
the opaque response. The current operator boundary requires:

- relay authentication;
- explicit HTTPS destinations;
- exact allow-list membership;
- public-endpoint validation;
- one hop;
- no redirects;
- bounded request, response, and timeout.

A passthrough relay sees both adjacent endpoints, timing, and byte counts. It
is not an anonymity claim.

The exact Noctweave Net client and wire models are exposed by `NoctweaveCore`.
The operational passthrough and host runtimes are supplied by the Linux/Docker
`NoctweaveRelayServer`, not its smaller embedded Swift relay.

## Retrieval-policy contract

Public retrieval has exactly two v0 wire shapes:

```text
client -> nw.net-host@1
client -> nw.net-passthrough@1 -> nw.net-host@1
```

They are alternatives, not a required
standard-to-passthrough-to-host chain. The effective hard route directive is
the first non-`open` value in strict authority order:

1. authenticated federation policy for the routing trust domain;
2. authenticated host-operator advertisement;
3. signed publisher directive; and
4. visitor preference.

All-open resolves deterministically to direct. Lower layers cannot weaken or
widen higher requirements. If passthrough is required and unavailable, the
client fails closed rather than issuing a direct host request.

The product term “federation policy” refers only to an authenticated
Noctweave Net routing trust-domain/control-plane constraint. It does not invoke
`nw.federation`, discover a relay, add a forwarding or consensus hop, define a
fourth relay role, or authorize content. Existing consensus may finalize or
share the selected policy record.

Experimental `noctweb-lab-v3` includes the publisher directive in the signed
publication. V2 relay-namespace publications remain verifiable and upgradeable;
v1 is legacy read-only. Production operator advertisements and federation
policy require authentication; the Lab substitutes deterministic local
adapters.

## Consensus boundary

Noctweave relay federation and `nw.federation` discovery are not retrieval
topology for Noctweave Net. Publisher heads, locator ordering, the selected
federation-policy record, and other shared coordination enter through the
separate consensus adapter described in
[consensus-boundary.md](consensus-boundary.md).

Consensus never receives Noctweave route capabilities, host release
capabilities, private capsule keys, or relationship state.
