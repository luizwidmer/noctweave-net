# Security

Noctweave Net is pre-protocol and unaudited. Do not use it for production
confidentiality, identity, or code execution.

## Security boundaries

- Clients create keys, encrypt private data, verify objects, and enforce
  capabilities.
- Standard relays provide bounded Noctweave transport, not identity.
- Passthrough relays provide path indirection, not anonymity.
- Host relays provide storage and retrieval, not publication authority.
- Consensus finalizes bounded public coordination state, not content safety or
  availability.

## Known metadata

Depending on the path, operators and network observers may see endpoint
addresses, timing, traffic sizes, request frequency, host selection, storage
tenancy, retention, and topology. Noctweave Net does not currently provide cover
traffic, a mix network, or a global anonymity claim.

## Mandatory implementation properties

- canonical and domain-separated hashes and signatures;
- strict bounded decoding;
- client-side encryption for private content;
- no plaintext, token, capability, or ciphertext-body logging;
- explicit relay role and version discovery;
- separate credentials and policy for co-located roles;
- public-endpoint and DNS-rebinding defenses for passthrough;
- digest verification before host storage acknowledgement;
- sandboxed active content;
- fail-closed consensus and suite upgrades.

## Reporting

Until a private reporting channel is published, do not include live secrets,
capabilities, private capsule content, or exploit payloads in public issues.
