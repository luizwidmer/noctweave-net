# Consensus Boundary

Noctweave Net separates the implemented federation namespace quorum from the
broader publication consensus boundary. The former allocates relay suffixes;
the latter remains replaceable and is not selected here.

## Implemented federation namespace

Each relay has a persistent ML-DSA-65 identity. Federation members maintain a
durable suffix ledger and sign deterministic snapshots of it. A local Browser
profile pins eligible relay IDs and keys plus a threshold. Only byte-identical,
cryptographically valid snapshots satisfying that threshold are accepted.

- Manual federation defaults to all configured signers.
- Curated federation uses the configured coordinator signer quorum.
- Open federation uses an explicit threshold signer set.
- DHT and PEX discover candidate endpoints only; they confer no voting power.

The ledger is append-only for ownership: offline relays retain their suffix,
double-signed key rotation retains it, and signed release permanently
tombstones it. Competing partition snapshots do not produce two accepted
owners; resolution fails closed until the configured authorities agree.

This is signed-state quorum, not a claim of global Byzantine consensus. It
does not order publisher heads, hide network metadata, or guarantee liveness
when required signers are unavailable.

## Adapter contract

The broader `ConsensusAdapter` must provide deterministic, bounded operations
equivalent to:

```text
submitPublisherHead(proposal)
resolveFinalizedHead(publisherID)
submitHostLocators(update)
resolveFinalizedLocators(objectID)
submitFederationPolicy(record)
resolveFinalizedFederationPolicy(routingTrustDomain)
claimRelaySuffix(claim)
registerNoctwebName(record)
resolveFinalizedNoctwebName(site, relaySuffix)
currentProtocolEpoch()
```

Names are conceptual until schemas and test vectors freeze them.

Every response must identify the consensus profile, network or trust domain,
finality evidence, protocol epoch, and bounded validity window needed for
independent verification.

Noctweb Browser consumes this adapter only through an explicit local
`NoctwebNetworkProfile`. The profile supplies the routing trust-domain and
consensus verification context; it does not grant authority to its bootstrap
endpoints. Unknown or conflicting suffix claims remain unresolved. A default
profile must never silently change the meaning of a textual `noct://` URL.

## Consensus may finalize

- publisher head ordering and continuity commitments;
- bounded public host locator sets;
- the selected authenticated federation-policy record for a Noctweave Net
  routing trust domain;
- any future transfer or governance state beyond the implemented permanent
  relay-suffix ownership ledger;
- unique site-label bindings within each suffix;
- protocol epochs and supported mandatory suite identifiers;
- explicit public revocations defined by a future profile;
- governance state required to interpret those records.

## Consensus must never receive

- private capsule plaintext or content keys;
- confidential capability links;
- Noctweave route IDs or append/read/renew/teardown capabilities;
- relationship, group, ratchet, or rendezvous secrets;
- private contact graphs;
- arbitrary browsing history;
- hosting-provider credentials.

## Authority separation

Consensus finality answers, "Which valid public proposal is current under this
profile?" It does not answer:

- whether an object is safe to execute;
- whether a host will remain available;
- whether a relay observed or delivered a private message;
- whether a publisher is a real-world person;
- whether two publisher keys belong to the same person;
- whether content is authentic merely because a routing policy selected its
  path.

Publisher signatures, object hashes, runtime policy, and local capability
checks remain mandatory after consensus verification.

Consensus may finalize or share the selected federation-policy record, which
is the highest-authority routing input. “Federation policy” means an
authenticated Noctweave Net routing trust-domain/control-plane constraint. It
is not a fourth relay role, relay forwarding, `nw.federation` discovery, a
consensus retrieval hop, or content authority.

The effective route directive is the first non-`open` value in strict
federation-policy, host-operator, signed-publisher, then visitor order. If all
are open, direct is the deterministic default. Consensus finality for the top
record cannot be used by a lower layer to weaken or widen it, and required
passthrough must fail closed when unavailable.

A finalized `noct://<site>.<relay-suffix>/` record selects a
publication-scoped publisher identifier. It does not authorize the suffix
operator to sign publisher heads and does not require the namespace relay to
serve current content. Consensus resolves independently finalized host
locators after resolving the name.

Bookmarks, history, open tabs, and portable `.noctlink` descriptors retain the
routing trust-domain identifier together with the canonical URL. The descriptor
is a bounded launch hint; every included endpoint, publisher expectation, and
profile hint remains untrusted until this adapter and the publisher/object
verification pipeline validate it.

Noctweb Lab now stores the immutable object before requesting a strict
relay-signed site binding. Noctweb Browser resolves the suffix through the
implemented namespace quorum and verifies that signed binding. This
authenticates the federation-local name but does not finalize a global
publisher-head history or guarantee continued hosting.

## Availability

Consensus records locators, not replicas. A host receipt is evidence of a
bounded storage acknowledgement, not a proof of continuing availability.
Clients may use multiple host relays, mirrors, caches, and local storage.

The consensus layer must not embed full capsule bodies as a shortcut for data
availability.

## Profile requirements

Before a consensus profile can be called supported, it must specify:

- publication-head and host-locator finality and reorganization behavior;
- light-client or equivalent verification;
- validator or membership transition rules;
- maximum record sizes and locator counts;
- any future suffix transfer or revocation semantics beyond permanent burn;
- replay, expiry, and clock assumptions;
- authentication, trust-domain binding, freshness, and replacement rules for
  federation-policy and host-operator records;
- exact `open`, `direct`, and `passthrough` directive semantics, including
  first-non-open authority resolution and fail-closed unavailability;
- denial-of-service costs and admission policy;
- privacy leakage of queries and submissions;
- upgrade and emergency-stop semantics;
- deterministic conformance vectors.

Until then, broader publication consensus remains an interface and research
task. Federation suffix resolution is implemented independently.
