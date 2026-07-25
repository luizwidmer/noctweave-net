import assert from "node:assert/strict";
import test from "node:test";
import {
  LAB_ADDRESS,
  LAB_RELAY_ROLES,
  canonicalizeSite,
  createHosts,
  createPublisherIdentity,
  publishSite,
  renderStaticSite,
  resolveSite,
  sha256Hex,
} from "../lib/lab-v0.ts";

const site = {
  title: "Quiet garden",
  subtitle: "A verified place",
  body: "First paragraph.\n\nSecond paragraph.",
  accent: "#6ee7bd",
};

test("lab-v0 canonical bytes and object IDs are deterministic", async () => {
  const canonical = canonicalizeSite(site);
  assert.equal(canonical, canonicalizeSite({ ...site }));
  assert.match(await sha256Hex(canonical), /^[0-9a-f]{64}$/);
});

test("exposes exactly the three Noctweave Net relay roles", () => {
  assert.deepEqual(
    LAB_RELAY_ROLES.map((role) => role.id),
    ["standard", "passthrough", "host"],
  );
  assert.deepEqual(
    LAB_RELAY_ROLES.map((role) => role.module),
    ["nw.opaque-route@2", "nw.net-passthrough@1", "nw.net-host@1"],
  );
});

test("publishes to online hosts and resolves verified bytes", async () => {
  const publisher = await createPublisherIdentity();
  const published = await publishSite(
    site,
    1,
    createHosts(),
    publisher,
    new Date("2026-07-25T12:00:00.000Z"),
  );
  const result = await resolveSite(
    LAB_ADDRESS,
    published.head,
    published.hosts,
    "direct",
  );

  assert.equal(result.status, "verified");
  if (result.status === "verified") {
    assert.equal(result.hostID, "host-a");
    assert.match(result.html, /Quiet garden/);
    assert.deepEqual(result.path, ["Noctweb Browser", "Bahia Origin"]);
  }
});

test("rejects corrupt host bytes and falls back without changing identity", async () => {
  const publisher = await createPublisherIdentity();
  const published = await publishSite(site, 1, createHosts(), publisher);
  const hosts = published.hosts.map((host) =>
    host.id === "host-a" ? { ...host, corrupt: true } : host,
  );
  const result = await resolveSite(
    LAB_ADDRESS,
    published.head,
    hosts,
    "passthrough",
  );

  assert.equal(result.status, "verified");
  if (result.status === "verified") {
    assert.equal(result.hostID, "host-b");
    assert.equal(result.objectID, published.head.objectID);
    assert.deepEqual(result.path, [
      "Noctweb Browser",
      "Passthrough relay",
      "Lisbon Mirror",
    ]);
    assert.ok(result.trace.some((entry) => entry.message.includes("digest mismatch")));
  }
});

test("fails closed when every locator is invalid or offline", async () => {
  const publisher = await createPublisherIdentity();
  const published = await publishSite(site, 1, createHosts(), publisher);
  const hosts = published.hosts.map((host) => ({
    ...host,
    corrupt: host.id === "host-a",
    online: host.id === "host-a",
  }));
  const result = await resolveSite(
    LAB_ADDRESS,
    published.head,
    hosts,
    "direct",
  );

  assert.equal(result.status, "rejected");
});

test("requires and verifies a publication-scoped publisher identity", async () => {
  const publisher = await createPublisherIdentity();
  const published = await publishSite(site, 1, createHosts(), publisher);
  assert.equal(published.head.publisherID, publisher.publisherID);
  assert.match(published.head.signature, /^[A-Za-z0-9_-]+$/);

  const next = await publishSite(
    { ...site, title: "Quiet garden, revised" },
    2,
    published.hosts,
    publisher,
  );
  assert.equal(next.head.publisherID, published.head.publisherID);
  assert.notEqual(next.head.signature, published.head.signature);

  const result = await resolveSite(
    LAB_ADDRESS,
    {
      ...published.head,
      publisherID: `${
        published.head.publisherID.startsWith("0") ? "1" : "0"
      }${published.head.publisherID.slice(1)}`,
    },
    published.hosts,
    "direct",
  );
  assert.equal(result.status, "rejected");
  assert.ok(
    result.trace.some((entry) =>
      entry.message.includes("Publisher identity or signed head"),
    ),
  );
});

test("static renderer escapes authored markup and disables scripts", () => {
  const html = renderStaticSite({
    ...site,
    title: "<script>alert(1)</script>",
    body: "<img src=x onerror=alert(1)>",
  });

  assert.doesNotMatch(html, /<script>/);
  assert.doesNotMatch(html, /<img src=x/);
  assert.match(html, /default-src 'none'/);
  assert.match(html, /&lt;script&gt;/);
});
