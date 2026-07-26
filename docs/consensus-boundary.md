# Consensus Boundary

Noctweave Net delegates shared coordination to a consensus system but does not
select or implement that system in the first milestone.

## Adapter contract

The eventual `ConsensusAdapter` must provide deterministic, bounded operations
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

## Consensus may finalize

- publisher head ordering and continuity commitments;
- bounded public host locator sets;
- the selected authenticated federation-policy record for a Noctweave Net
  routing trust domain;
- globally unique relay-suffix allocations, including custom suffixes and the
  deterministic `r-<hash>` fallback defined by the active profile;
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

## Availability

Consensus records locators, not replicas. A host receipt is evidence of a
bounded storage acknowledgement, not a proof of continuing availability.
Clients may use multiple host relays, mirrors, caches, and local storage.

The consensus layer must not embed full capsule bodies as a shortcut for data
availability.

## Profile requirements

Before a consensus profile can be called supported, it must specify:

- finality and reorganization behavior;
- light-client or equivalent verification;
- validator or membership transition rules;
- maximum record sizes and locator counts;
- canonical site and suffix syntax, normalization, allocation, transfer,
  expiry, revocation, and conflict behavior;
- exact deterministic fallback-suffix derivation, encoding, length, and
  collision handling;
- replay, expiry, and clock assumptions;
- authentication, trust-domain binding, freshness, and replacement rules for
  federation-policy and host-operator records;
- exact `open`, `direct`, and `passthrough` directive semantics, including
  first-non-open authority resolution and fail-closed unavailability;
- denial-of-service costs and admission policy;
- privacy leakage of queries and submissions;
- upgrade and emergency-stop semantics;
- deterministic conformance vectors.

Until then, consensus integration remains an interface and research task.
