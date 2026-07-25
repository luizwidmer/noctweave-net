# Noctweave Integration

Noctweave Net runs behind Noctweave's exact relay envelope. It does not define
a parallel listener, discovery service, account system, or transport framing.

## Role and module matrix

| Relay role | Advertised application modules | Noctweave Net use |
| --- | --- | --- |
| `standard` | `nw.opaque-route@2` and enabled standard modules | Private invitations, collaboration, capability delivery, and control events |
| `passthrough` | `nw.net-passthrough@1` | One bounded authenticated forward to one operator-allow-listed public HTTPS Noctweave endpoint |
| `host` | `nw.net-host@1` | Content-addressed object storage, retrieval, presence, and capability-protected release |

Every role also advertises `nw.core@2` for health, information, and exact
capability discovery. Passthrough and host relays do not advertise standard
messaging, federation, open-discovery, rendezvous, attachment, or experimental
privacy modules.

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

## Consensus boundary

Noctweave relay federation is not used by Noctweave Net. Publisher heads,
locator ordering, and other shared coordination enter through the separate
consensus adapter described in [consensus-boundary.md](consensus-boundary.md).

Consensus never receives Noctweave route capabilities, host release
capabilities, private capsule keys, or relationship state.
