# Noctweb Lab

Noctweb Lab is the first runnable development surface for Noctweave Net sites.
It is intentionally local-first and uses an incompatible `lab-v0` object
profile with deterministic mock consensus.

The current slice can:

- author and publish a bounded static site;
- store exact canonical bytes on two simulated hosts;
- finalize a mock publisher head;
- resolve directly or through one simulated passthrough hop;
- verify SHA-256 object IDs before rendering;
- fall back across host locators;
- inject offline and corrupt-host failures;
- render HTML and CSS inside a scriptless, originless iframe sandbox.

It is not a production browser, consensus implementation, or stable wire
format.

```sh
npm install
npm run dev
npm test
```
