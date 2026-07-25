# Capsule Net Agent Guide

## Project state

Capsule Net is pre-protocol. Preserve the architectural boundaries in
`docs/` and record intentional changes as ADRs before treating them as wire
compatibility.

## Dependency boundary

Capsule Net is an application protocol above Noctweave's public transport
surface. Integrate only through:

- `NoctweaveCore`;
- `NoctweaveRelayServer`;
- `NoctweaveJS`;
- published Noctweave protocol and operations documentation.

Do not depend on proprietary Noctweave client or GUI relay sources. Do not
copy Noctweave source into this repository.

## Security invariants

- Capsule publishers are cryptographic authorities; relays are not.
- Private capsule content is encrypted before relay submission.
- Relay roles are exactly `standard`, `passthrough`, and `host`.
- Consensus coordinates public shared state but never receives private
  content, content keys, Noctweave route capabilities, or relationship keys.
- A passthrough relay is not an anonymity guarantee.
- A host relay stores and serves bytes; it does not execute hosted code or
  become the authority for a publication.
- No global user account, recovery authority, device registry, plaintext
  logging, silent downgrade, or implicit key escrow.

## Change discipline

Keep wire formats canonical, bounded, versioned, and strictly decoded. Add
test vectors before claiming interoperability. Update the relevant ADR and
threat model when changing a trust boundary.
