# Noctweb Lab

Noctweb Lab is the first runnable development surface for Noctweave Net sites.
It is intentionally local-first and uses an incompatible `lab-v0` object
profile with deterministic mock consensus.

The current slice can:

- manage a persistent local workspace with publisher, browser, network, and
  inspector surfaces;
- author, preview, validate, and publish a bounded static site;
- create and retain a publication-scoped publisher identity in a local
  IndexedDB-backed key vault;
- sign every lab head and verify its publisher identity before rendering;
- store exact canonical bytes on two simulated hosts;
- finalize a mock publisher head;
- resolve directly or through one simulated passthrough hop;
- verify SHA-256 object IDs before rendering;
- fall back across host locators;
- run healthy, failover, passthrough, and outage scenarios;
- expose the standard, passthrough, and host relay boundaries without
  pretending every role participates in public retrieval;
- preserve draft and revision history in device-local storage;
- export a local diagnostic report;
- install as a standalone progressive web app;
- render HTML and CSS inside a scriptless, originless iframe sandbox.

Its Ed25519 publisher key and signed head are real lab checks, but their suite
and encoding are not stable protocol commitments. It is not a production
browser, consensus implementation, audited key manager, or stable wire format.

```sh
npm install
npm run dev
npm test
```
