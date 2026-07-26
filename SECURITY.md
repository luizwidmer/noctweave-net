# Security

Noctweave Net is pre-protocol and unaudited. Do not use it for production
confidentiality, identity, or code execution.

## Security boundaries

- Clients create keys, encrypt private data, verify objects, and enforce
  capabilities.
- Every publication has its own publisher identity and every mutable head must
  verify under that authority. Publisher keys are not global accounts and must
  not be reused as Noctweave relationship or group keys.
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

## Noctweb Lab active-content boundary

The experimental Lab executes publisher-authenticated client-side JavaScript,
but a valid publisher signature does not make that code safe. Before WebKit
receives any bytes, the Lab canonicalizes and verifies the complete bounded
website bundle and assigns it a publication-scoped custom origin. The runtime
uses a non-persistent data store, exposes no native message bridge, and applies
a content security policy, navigation policy, and WebRTC guard that deny
website access to external network resources.

The packaged app uses the macOS App Sandbox and grants read-only access only to
a build directory chosen through the system import panel. WebKit requires the
network-client entitlement for its separate networking process, so the
website-level denial is a runtime boundary, not a claim that the process lacks
network authority. This profile remains an unaudited test platform and is not a
production sandbox for hostile code.

Build imports reject symbolic links, non-regular files, ambiguous paths, more
than 512 files, and more than 16 MiB before unbounded allocation. Publisher-key
destruction is journaled before the irreversible Keychain deletion and retried
after restart when interrupted.

## Mandatory implementation properties

- canonical and domain-separated hashes and signatures;
- publisher-identity derivation and signed-head verification before rendering;
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
