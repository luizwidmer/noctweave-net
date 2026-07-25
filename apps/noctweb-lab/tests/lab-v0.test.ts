import assert from "node:assert/strict";
import test from "node:test";
import {
  LAB_ADDRESS,
  canonicalizeSite,
  createHosts,
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

test("publishes to online hosts and resolves verified bytes", async () => {
  const published = await publishSite(
    site,
    1,
    createHosts(),
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
  }
});

test("rejects corrupt host bytes and falls back without changing identity", async () => {
  const published = await publishSite(site, 1, createHosts());
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
    assert.ok(result.trace.some((entry) => entry.message.includes("digest mismatch")));
  }
});

test("fails closed when every locator is invalid or offline", async () => {
  const published = await publishSite(site, 1, createHosts());
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
