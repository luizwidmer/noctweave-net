# Consensus Boundary

Capsule Net delegates shared coordination to a consensus system but does not
select or implement that system in the first milestone.

## Adapter contract

The eventual `ConsensusAdapter` must provide deterministic, bounded operations
equivalent to:

```text
submitPublisherHead(proposal)
resolveFinalizedHead(publisherID)
submitHostLocators(update)
resolveFinalizedLocators(objectID)
currentProtocolEpoch()
```

Names are conceptual until schemas and test vectors freeze them.

Every response must identify the consensus profile, network or trust domain,
finality evidence, protocol epoch, and bounded validity window needed for
independent verification.

## Consensus may finalize

- publisher head ordering and continuity commitments;
- bounded public host locator sets;
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
- which retrieval path a client should choose.

Publisher signatures, object hashes, runtime policy, and local capability
checks remain mandatory after consensus verification.

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
- replay, expiry, and clock assumptions;
- denial-of-service costs and admission policy;
- privacy leakage of queries and submissions;
- upgrade and emergency-stop semantics;
- deterministic conformance vectors.

Until then, consensus integration remains an interface and research task.
