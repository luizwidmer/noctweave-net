# ADR 0001: Use Noctweave as a transport dependency

- Status: Accepted
- Date: 2026-07-25

## Context

Noctweave Net needs encrypted private delivery, opaque bounded routes, strict
relay envelopes, explicit transports, and self-hostable infrastructure.
Noctweave already supplies these as public protocol and tooling surfaces.

Noctweave Net also needs object identity, hosting, resolution, capability links,
and consensus-finalized publication state. Those are web semantics, not
Noctweave relationship semantics.

## Decision

Noctweave Net is a separate repository and application protocol layered above
Noctweave's public transport surface.

It will reuse supported Noctweave components through package, client, or wire
interfaces. It will not fork Noctweave, import proprietary clients, reuse
relationship keys as publisher keys, or redefine Noctweave personas as global
accounts.

## Consequences

- Noctweave upgrades can be evaluated as dependency upgrades.
- Capsule object and consensus versions evolve independently.
- Private collaboration inherits Noctweave's route and local-state rules.
- Noctweave Net must define its own interoperability vectors and runtime safety.
