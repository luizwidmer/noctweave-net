export const LAB_PROFILE = "lab-v0";
export const LAB_ADDRESS = "noct://quiet-garden/";
export const MAX_FIELD_BYTES = 4_096;

export type LabSite = {
  title: string;
  subtitle: string;
  body: string;
  accent: string;
};

export type LabEnvelope = LabSite & {
  profile: typeof LAB_PROFILE;
};

export type LabHost = {
  id: "host-a" | "host-b";
  name: string;
  location: string;
  online: boolean;
  corrupt: boolean;
  objects: Record<string, string>;
};

export type LabHead = {
  address: string;
  objectID: string;
  revision: number;
  finalizedAt: string;
};

export type ResolutionTrace = {
  kind: "info" | "success" | "warning" | "failure";
  message: string;
};

export type LabResolution =
  | {
      status: "verified";
      hostID: LabHost["id"];
      route: "direct" | "passthrough";
      objectID: string;
      site: LabSite;
      html: string;
      trace: ResolutionTrace[];
    }
  | {
      status: "unavailable" | "rejected";
      route: "direct" | "passthrough";
      objectID: string | null;
      trace: ResolutionTrace[];
    };

const encoder = new TextEncoder();

function isSafeString(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.trim() === value &&
    value.length > 0 &&
    encoder.encode(value).byteLength <= MAX_FIELD_BYTES
  );
}

function isAccent(value: unknown): value is string {
  return typeof value === "string" && /^#[0-9a-f]{6}$/.test(value);
}

export function normalizeSite(site: LabSite): LabSite {
  return {
    title: site.title.trim().slice(0, 80),
    subtitle: site.subtitle.trim().slice(0, 160),
    body: site.body.trim().slice(0, 1_200),
    accent: site.accent.toLowerCase(),
  };
}

export function canonicalizeSite(site: LabSite): string {
  const normalized = normalizeSite(site);
  const envelope: LabEnvelope = {
    profile: LAB_PROFILE,
    title: normalized.title,
    subtitle: normalized.subtitle,
    body: normalized.body,
    accent: normalized.accent,
  };

  if (!isEnvelope(envelope)) {
    throw new Error("Site fields are empty, too large, or invalid.");
  }

  return JSON.stringify(envelope);
}

export function isEnvelope(value: unknown): value is LabEnvelope {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }

  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  const expected = ["accent", "body", "profile", "subtitle", "title"];

  return (
    keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]) &&
    record.profile === LAB_PROFILE &&
    isSafeString(record.title) &&
    isSafeString(record.subtitle) &&
    isSafeString(record.body) &&
    isAccent(record.accent)
  );
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function escapeHTML(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;",
      })[character] ?? character,
  );
}

export function renderStaticSite(site: LabSite): string {
  const safe = normalizeSite(site);
  const paragraphs = safe.body
    .split(/\n{2,}/)
    .map((paragraph) => `<p>${escapeHTML(paragraph)}</p>`)
    .join("");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
  <title>${escapeHTML(safe.title)}</title>
  <style>
    :root { color-scheme: dark; --accent: ${safe.accent}; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      overflow-x: hidden;
      color: #e9f7f2;
      background:
        radial-gradient(circle at 82% 18%, color-mix(in srgb, var(--accent) 23%, transparent), transparent 28rem),
        radial-gradient(circle at 16% 84%, #10352f 0, transparent 25rem),
        #07110f;
      font: 400 16px/1.7 ui-sans-serif, system-ui, -apple-system, sans-serif;
    }
    main { width: min(760px, calc(100% - 48px)); padding: 72px 0; }
    .eyebrow {
      display: inline-flex;
      gap: 9px;
      align-items: center;
      color: #9bcfc2;
      font: 600 11px/1 ui-monospace, monospace;
      letter-spacing: .16em;
      text-transform: uppercase;
    }
    .eyebrow::before { content: ""; width: 30px; height: 1px; background: var(--accent); }
    h1 {
      max-width: 680px;
      margin: 28px 0 14px;
      font: 500 clamp(42px, 8vw, 82px)/.98 Georgia, serif;
      letter-spacing: -.045em;
    }
    .subtitle { max-width: 580px; color: #a9c2bb; font-size: clamp(18px, 3vw, 24px); }
    article {
      max-width: 620px;
      margin-top: 64px;
      padding-top: 28px;
      border-top: 1px solid #21463d;
      color: #c8d9d4;
    }
    article p + p { margin-top: 1.4em; }
    footer {
      margin-top: 64px;
      color: #6f9289;
      font: 500 11px/1.4 ui-monospace, monospace;
      letter-spacing: .12em;
      text-transform: uppercase;
    }
  </style>
</head>
<body>
  <main>
    <div class="eyebrow">Verified on Noctweb</div>
    <h1>${escapeHTML(safe.title)}</h1>
    <div class="subtitle">${escapeHTML(safe.subtitle)}</div>
    <article>${paragraphs}</article>
    <footer>Static profile · scripts disabled · lab-v0</footer>
  </main>
</body>
</html>`;
}

export async function publishSite(
  site: LabSite,
  revision: number,
  hosts: LabHost[],
  now = new Date(),
): Promise<{ canonical: string; head: LabHead; hosts: LabHost[] }> {
  if (!Number.isSafeInteger(revision) || revision < 1) {
    throw new Error("Revision must be a positive safe integer.");
  }

  const canonical = canonicalizeSite(site);
  const objectID = await sha256Hex(canonical);
  const nextHosts = hosts.map((host) =>
    host.online
      ? {
          ...host,
          corrupt: false,
          objects: { ...host.objects, [objectID]: canonical },
        }
      : host,
  );

  return {
    canonical,
    hosts: nextHosts,
    head: {
      address: LAB_ADDRESS,
      objectID,
      revision,
      finalizedAt: now.toISOString(),
    },
  };
}

export async function resolveSite(
  address: string,
  head: LabHead | null,
  hosts: LabHost[],
  route: "direct" | "passthrough",
): Promise<LabResolution> {
  const trace: ResolutionTrace[] = [
    {
      kind: "info",
      message:
        route === "passthrough"
          ? "Route selected: one bounded passthrough hop"
          : "Route selected: direct host retrieval",
    },
  ];

  if (!head || address !== head.address) {
    trace.push({
      kind: "failure",
      message: "Mock consensus has no finalized head for this address.",
    });
    return { status: "unavailable", route, objectID: head?.objectID ?? null, trace };
  }

  trace.push({
    kind: "success",
    message: `Consensus finalized revision ${head.revision}.`,
  });

  let sawRejectedObject = false;
  for (const host of hosts) {
    if (!host.online) {
      trace.push({ kind: "warning", message: `${host.name} is offline; trying next locator.` });
      continue;
    }

    const stored = host.objects[head.objectID];
    if (!stored) {
      trace.push({ kind: "warning", message: `${host.name} does not retain this object.` });
      continue;
    }

    const candidate = host.corrupt ? `${stored} ` : stored;
    const candidateID = await sha256Hex(candidate);
    if (candidateID !== head.objectID) {
      sawRejectedObject = true;
      trace.push({
        kind: "failure",
        message: `${host.name} returned a digest mismatch; bytes rejected.`,
      });
      continue;
    }

    let envelope: unknown;
    try {
      envelope = JSON.parse(candidate);
    } catch {
      sawRejectedObject = true;
      trace.push({ kind: "failure", message: `${host.name} returned invalid canonical JSON.` });
      continue;
    }

    if (!isEnvelope(envelope)) {
      sawRejectedObject = true;
      trace.push({ kind: "failure", message: `${host.name} returned an invalid lab-v0 object.` });
      continue;
    }

    trace.push({
      kind: "success",
      message: `${host.name} verified ${head.objectID.slice(0, 12)}…`,
    });
    trace.push({
      kind: "success",
      message: "Static renderer accepted the object; scripts remain disabled.",
    });

    const site: LabSite = {
      title: envelope.title,
      subtitle: envelope.subtitle,
      body: envelope.body,
      accent: envelope.accent,
    };
    return {
      status: "verified",
      hostID: host.id,
      route,
      objectID: head.objectID,
      site,
      html: renderStaticSite(site),
      trace,
    };
  }

  trace.push({
    kind: "failure",
    message: sawRejectedObject
      ? "Every available locator returned invalid bytes."
      : "No host currently serves the finalized object.",
  });
  return {
    status: sawRejectedObject ? "rejected" : "unavailable",
    route,
    objectID: head.objectID,
    trace,
  };
}

export function createHosts(): LabHost[] {
  return [
    {
      id: "host-a",
      name: "Host A",
      location: "Bahia · self-hosted",
      online: true,
      corrupt: false,
      objects: {},
    },
    {
      id: "host-b",
      name: "Host B",
      location: "Lisbon · mirror",
      online: true,
      corrupt: false,
      objects: {},
    },
  ];
}
