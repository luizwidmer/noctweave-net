# ADR 0007: Use hierarchical public-retrieval policy

- Status: Accepted
- Date: 2026-07-25
- Supersedes: only prior statements that federation has no routing-policy input

## Context

Public retrieval needs a deterministic answer when a routing trust domain, the
selected host operator, the publisher, and the visitor express different path
requirements. Treating the visitor as the sole route selector would let a
lower-authority preference bypass operator or trust-domain policy. Treating
federation as a relay hop would contradict the accepted three-role topology and
confuse routing control with content transport.

The policy must also preserve simple self-hosting. A standard relay process may
serve content itself by advertising the host module; it must not be forced
through passthrough, federation forwarding, consensus, or namespace allocation
to do so.

## Decision

V0 public retrieval permits exactly two alternative shapes:

```text
visitor -> host
visitor -> passthrough -> host
```

There is no mandatory standard-to-passthrough-to-host chain. Multi-hop
retrieval remains outside v0.

Each routing authority supplies one hard `RouteDirective`: `open`, `direct`,
or `passthrough`. The effective directive is the first non-`open` value in this
strict authority order:

1. federation policy for the authenticated Noctweave Net routing trust domain;
2. authenticated host-relay operator advertisement;
3. signed publisher directive; and
4. visitor preference.

When all four directives are `open`, direct retrieval is the deterministic
default. A lower authority cannot weaken or widen a higher requirement.
Therefore a required passthrough that is unavailable fails closed; it never
silently downgrades to direct. A direct requirement likewise cannot be widened
into a passthrough route.

Product surfaces call the top layer “federation policy.” It is an
authenticated Noctweave Net routing trust-domain/control-plane constraint. It
is not:

- a fourth relay role;
- a relay-forwarding or consensus hop;
- `nw.federation` discovery; or
- authority over publisher signatures, object bytes, or content safety.

Existing consensus may finalize or share the selected federation-policy record
for a routing trust domain. Consensus does not carry the corresponding
retrieval traffic.

Noctweave Net still has exactly three relay/module families: standard,
passthrough, and host. One process may advertise multiple modules. A `solo`
standard relay may advertise `nw.net-host@1` and directly host and serve
content. Namespace advertisement is optional and is not a hosting
prerequisite.

The experimental `noctweb-lab-v3` publication signs its publisher directive.
V2 relay-namespace publications remain verifiable and upgradeable; v1 remains
legacy read-only. Production federation-policy records and host-operator
advertisements must be authenticated, fresh, and bound to their routing trust
domain. Noctweb Lab uses deterministic local adapters to model those inputs.

## Supersession scope

This ADR supersedes only statements, including interpretations of ADR 0002,
that exclude federation policy as an input to Noctweave Net routing. It retains
ADR 0002's decisions that exactly three relay/module families exist and that
federation is not a relay role or forwarding hop. It does not enable
`nw.federation` discovery or forwarding in the retrieval path.

## Consequences

- Clients must preserve and authenticate every higher-authority directive and
  expose the effective authority and actual route in UI and audit evidence.
- Directive stripping, stale or forged operator/federation policy, UI that
  claims direct while using passthrough, and silent downgrade are protocol
  failures.
- A relay advertising both passthrough and host modules can correlate both
  sides of the nominal hop. Implementations must describe that metadata
  collapse accurately.
- Every co-located module requires separate credentials, rate limits, policy,
  storage lifetime, and audit boundaries.
- Conformance vectors must cover all-open defaulting, every authority winning,
  lower-layer conflicts, required-passthrough unavailability, and authenticated
  policy replacement.
