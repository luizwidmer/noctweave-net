"use client";

import {
  FormEvent,
  ReactNode,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  LAB_ADDRESS,
  LAB_CONSENSUS_PROFILE,
  LAB_PROFILE,
  LAB_RELAY_ROLES,
  LabHead,
  LabHost,
  LabPublisherIdentity,
  LabResolution,
  LabSite,
  canonicalizeSite,
  createHosts,
  normalizeSite,
  publishSite,
  renderStaticSite,
  resolveSite,
} from "../lib/lab-v0";
import { loadOrCreatePublisherIdentity } from "../lib/publisher-vault";

const WORKSPACE_STORAGE_KEY = "noctweb-lab:quiet-garden:v2";

const seedSite: LabSite = {
  title: "A garden with no address",
  subtitle: "Field notes from a website that belongs to its author, not its host.",
  body:
    "The page you are reading was reconstructed from verified objects. Its host can change without changing what it is.\n\nTurn a host off. Corrupt its bytes. Route through a passthrough relay. Noctweb will keep the object identity stable and reject anything that fails integrity checks.",
  accent: "#6ee7bd",
};

const templates: Array<{ name: string; description: string; site: LabSite }> = [
  {
    name: "Quiet editorial",
    description: "Long-form writing with a calm, typographic presentation.",
    site: seedSite,
  },
  {
    name: "Studio note",
    description: "A concise project announcement for a public capsule.",
    site: {
      title: "Things made carefully",
      subtitle: "A small independent studio publishing from its own key.",
      body:
        "We design tools that stay useful after the platform around them changes.\n\nThis publication is hosted in more than one place, but its object identity remains exact.",
      accent: "#86a8ff",
    },
  },
  {
    name: "Protocol brief",
    description: "A technical update with a strong information hierarchy.",
    site: {
      title: "Noctweave Net field report",
      subtitle: "Object integrity, replaceable hosting, and client-side authority.",
      body:
        "This lab revision exercises deterministic canonical bytes and host failover.\n\nConsensus, publisher signatures, and production capability semantics remain simulated in lab-v0.",
      accent: "#f5b971",
    },
  },
];

type ViewID = "overview" | "publish" | "network" | "inspector";
type ScenarioID = "healthy" | "failover" | "passthrough" | "outage";

type AppInstallPrompt = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

type LabState = {
  head: LabHead | null;
  hosts: LabHost[];
  revision: number;
};

type PublicationRecord = {
  revision: number;
  objectID: string;
  finalizedAt: string;
  replicas: number;
};

const navigation: Array<{
  id: ViewID;
  label: string;
  description: string;
  icon: string;
}> = [
  {
    id: "overview",
    label: "Overview",
    description: "Browse and test",
    icon: "◫",
  },
  {
    id: "publish",
    label: "Publish",
    description: "Build a revision",
    icon: "↗",
  },
  {
    id: "network",
    label: "Network",
    description: "Relays and consensus",
    icon: "⌘",
  },
  {
    id: "inspector",
    label: "Inspector",
    description: "Evidence and objects",
    icon: "⌕",
  },
];

const viewCopy: Record<
  ViewID,
  { eyebrow: string; title: string; description: string }
> = {
  overview: {
    eyebrow: "Workspace overview",
    title: "Quiet Garden",
    description:
      "Browse the current publication, exercise retrieval paths, and verify how the runtime responds to failure.",
  },
  publish: {
    eyebrow: "Publisher",
    title: "Prepare a new revision",
    description:
      "Compose a bounded static capsule, preview it locally, then replicate and finalize it in the deterministic workspace.",
  },
  network: {
    eyebrow: "Network",
    title: "Relay topology",
    description:
      "Inspect the three Noctweave Net relay roles, host availability, retrieval path, and mock consensus boundary.",
  },
  inspector: {
    eyebrow: "Inspector",
    title: "Trust evidence",
    description:
      "Review the exact object, ordered resolution path, integrity decisions, and local publication history.",
  },
};

const scenarioCopy: Record<
  ScenarioID,
  { name: string; description: string; icon: string }
> = {
  healthy: {
    name: "Healthy network",
    description: "Direct retrieval with both hosts available.",
    icon: "✓",
  },
  failover: {
    name: "Invalid origin",
    description: "Reject Origin bytes and fall back to the mirror.",
    icon: "↪",
  },
  passthrough: {
    name: "Indirect retrieval",
    description: "Insert one bounded passthrough hop.",
    icon: "⌁",
  },
  outage: {
    name: "Total outage",
    description: "Take every host offline and fail closed.",
    icon: "×",
  },
};

function compactID(value: string | null | undefined, edge = 8) {
  return value ? `${value.slice(0, edge)}…${value.slice(-edge)}` : "Pending";
}

function formatTime(value: string | null | undefined) {
  if (!value) return "Pending";
  return new Intl.DateTimeFormat("en", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(new Date(value));
}

function isStoredSite(value: unknown): value is LabSite {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return (
    typeof record.title === "string" &&
    typeof record.subtitle === "string" &&
    typeof record.body === "string" &&
    typeof record.accent === "string"
  );
}

function MetricCard({
  label,
  value,
  detail,
  tone = "neutral",
}: {
  label: string;
  value: string;
  detail: string;
  tone?: "neutral" | "good" | "warning";
}) {
  return (
    <article className={`metric-card ${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
      <p>{detail}</p>
    </article>
  );
}

function Panel({
  className = "",
  title,
  eyebrow,
  action,
  children,
}: {
  className?: string;
  title?: string;
  eyebrow?: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className={`surface ${className}`}>
      {(title || eyebrow || action) && (
        <header className="surface-header">
          <div>
            {eyebrow && <span className="surface-eyebrow">{eyebrow}</span>}
            {title && <h2>{title}</h2>}
          </div>
          {action}
        </header>
      )}
      {children}
    </section>
  );
}

export default function Home() {
  const [activeView, setActiveView] = useState<ViewID>("overview");
  const [lab, setLab] = useState<LabState>({
    head: null,
    hosts: createHosts(),
    revision: 0,
  });
  const [draft, setDraft] = useState<LabSite>(seedSite);
  const [publishedSite, setPublishedSite] = useState<LabSite>(seedSite);
  const [address, setAddress] = useState(LAB_ADDRESS);
  const [activeAddress, setActiveAddress] = useState(LAB_ADDRESS);
  const [navigationHistory, setNavigationHistory] = useState([LAB_ADDRESS]);
  const [historyIndex, setHistoryIndex] = useState(0);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [usePassthrough, setUsePassthrough] = useState(false);
  const [resolution, setResolution] = useState<LabResolution | null>(null);
  const [notice, setNotice] = useState("Starting the local workspace…");
  const [publishing, setPublishing] = useState(false);
  const [publisherIdentity, setPublisherIdentity] =
    useState<LabPublisherIdentity | null>(null);
  const [installPrompt, setInstallPrompt] =
    useState<AppInstallPrompt | null>(null);
  const [publicationHistory, setPublicationHistory] = useState<
    PublicationRecord[]
  >([]);
  const [selectedScenario, setSelectedScenario] =
    useState<ScenarioID>("healthy");
  const [storageReady, setStorageReady] = useState(false);
  const publishLock = useRef(false);

  useEffect(() => {
    let restoredDraft = seedSite;
    let restoredPublishedSite = seedSite;
    let restoredRevision = 1;
    let restoredHistory: PublicationRecord[] = [];

    try {
      const stored = localStorage.getItem(WORKSPACE_STORAGE_KEY);
      if (stored) {
        const parsed = JSON.parse(stored) as {
          draft?: unknown;
          publishedSite?: unknown;
          revision?: unknown;
          history?: unknown;
        };
        if (isStoredSite(parsed.draft)) {
          restoredDraft = parsed.draft;
        }
        if (isStoredSite(parsed.publishedSite)) {
          restoredPublishedSite = parsed.publishedSite;
        }
        if (
          Number.isSafeInteger(parsed.revision) &&
          Number(parsed.revision) >= 1
        ) {
          restoredRevision = Number(parsed.revision);
        }
        if (Array.isArray(parsed.history)) {
          restoredHistory = parsed.history.filter(
            (entry): entry is PublicationRecord =>
              Boolean(entry) &&
              typeof entry === "object" &&
              Number.isSafeInteger((entry as PublicationRecord).revision) &&
              typeof (entry as PublicationRecord).objectID === "string" &&
              typeof (entry as PublicationRecord).finalizedAt === "string" &&
              Number.isSafeInteger((entry as PublicationRecord).replicas),
          );
        }
      }
    } catch {
      localStorage.removeItem(WORKSPACE_STORAGE_KEY);
    }

    setDraft(restoredDraft);
    setPublishedSite(restoredPublishedSite);
    setPublicationHistory(restoredHistory);
    setStorageReady(true);

    void loadOrCreatePublisherIdentity()
      .then(async (identity) => {
        setPublisherIdentity(identity);
        const published = await publishSite(
          restoredPublishedSite,
          restoredRevision,
          createHosts(),
          identity,
        );
        const replicas = published.hosts.filter(
          (host) => host.objects[published.head.objectID],
        ).length;
        setLab({
          head: published.head,
          hosts: published.hosts,
          revision: restoredRevision,
        });
        setPublicationHistory((current) =>
          current.length
            ? current
            : [
                {
                  revision: restoredRevision,
                  objectID: published.head.objectID,
                  finalizedAt: published.head.finalizedAt,
                  replicas,
                },
              ],
        );
        setNotice(
          `Workspace ready. Publisher identity and revision ${restoredRevision} are verified locally.`,
        );
      })
      .catch((error) => {
        setNotice(
          error instanceof Error
            ? `Publisher key vault unavailable: ${error.message}`
            : "Publisher key vault unavailable.",
        );
      });
  }, []);

  useEffect(() => {
    if (!storageReady) return;
    localStorage.setItem(
      WORKSPACE_STORAGE_KEY,
      JSON.stringify({
        draft,
        publishedSite,
        revision: lab.revision || 1,
        history: publicationHistory.slice(0, 20),
      }),
    );
  }, [draft, lab.revision, publicationHistory, publishedSite, storageReady]);

  useEffect(() => {
    if ("serviceWorker" in navigator) {
      void navigator.serviceWorker.register("/sw.js");
    }
    const handleInstallPrompt = (event: Event) => {
      event.preventDefault();
      setInstallPrompt(event as AppInstallPrompt);
    };
    window.addEventListener("beforeinstallprompt", handleInstallPrompt);
    return () =>
      window.removeEventListener("beforeinstallprompt", handleInstallPrompt);
  }, []);

  useEffect(() => {
    let active = true;
    setResolution(null);
    void resolveSite(
      activeAddress,
      lab.head,
      lab.hosts,
      usePassthrough ? "passthrough" : "direct",
    ).then((result) => {
      if (active) setResolution(result);
    });
    return () => {
      active = false;
    };
  }, [activeAddress, lab.head, lab.hosts, reloadNonce, usePassthrough]);

  const activeHost = useMemo(
    () =>
      resolution?.status === "verified"
        ? lab.hosts.find((host) => host.id === resolution.hostID)
        : null,
    [lab.hosts, resolution],
  );

  const replicaCount = useMemo(
    () =>
      lab.head
        ? lab.hosts.filter((host) => host.objects[lab.head!.objectID]).length
        : 0,
    [lab.head, lab.hosts],
  );

  const draftPreview = useMemo(() => renderStaticSite(draft), [draft]);
  const isDirty =
    JSON.stringify(normalizeSite(draft)) !== JSON.stringify(publishedSite);
  const canPublish =
    draft.title.trim().length > 0 &&
    draft.subtitle.trim().length > 0 &&
    draft.body.trim().length > 0 &&
    publisherIdentity !== null &&
    !publishing;

  const publisherPassed =
    resolution?.trace.some((entry) =>
      entry.message.startsWith("Publisher identity"),
    ) ?? false;

  const canonicalObject = useMemo(() => {
    if (resolution?.status === "verified") {
      return canonicalizeSite(resolution.site);
    }
    if (!lab.head) return "";
    return (
      lab.hosts
        .map((host) => host.objects[lab.head!.objectID])
        .find((value) => typeof value === "string") ?? ""
    );
  }, [lab.head, lab.hosts, resolution]);

  const objectBytes = useMemo(
    () => new TextEncoder().encode(canonicalObject).byteLength,
    [canonicalObject],
  );

  function commitNavigation(nextAddress: string) {
    const normalized = nextAddress.trim();
    if (!normalized) return;
    const nextHistory = navigationHistory.slice(0, historyIndex + 1);
    if (nextHistory.at(-1) !== normalized) nextHistory.push(normalized);
    setNavigationHistory(nextHistory);
    setHistoryIndex(nextHistory.length - 1);
    setAddress(normalized);
    setActiveAddress(normalized);
  }

  function navigate(event: FormEvent) {
    event.preventDefault();
    commitNavigation(address);
  }

  function moveHistory(direction: -1 | 1) {
    const nextIndex = historyIndex + direction;
    const nextAddress = navigationHistory[nextIndex];
    if (!nextAddress) return;
    setHistoryIndex(nextIndex);
    setAddress(nextAddress);
    setActiveAddress(nextAddress);
  }

  function updateHost(id: LabHost["id"], change: Partial<LabHost>) {
    setLab((current) => ({
      ...current,
      hosts: current.hosts.map((host) =>
        host.id === id ? { ...host, ...change } : host,
      ),
    }));
  }

  function repairedHosts(current: LabState) {
    const stored =
      current.head &&
      current.hosts
        .map((host) => host.objects[current.head!.objectID])
        .find((value) => typeof value === "string");

    return current.hosts.map((host) => ({
      ...host,
      online: true,
      corrupt: false,
      objects:
        current.head && stored
          ? { ...host.objects, [current.head.objectID]: stored }
          : host.objects,
    }));
  }

  function applyScenario(id: ScenarioID) {
    setSelectedScenario(id);
    setUsePassthrough(id === "passthrough");
    setLab((current) => {
      const healthyHosts = repairedHosts(current);
      if (id === "outage") {
        return {
          ...current,
          hosts: healthyHosts.map((host) => ({ ...host, online: false })),
        };
      }
      if (id === "failover") {
        return {
          ...current,
          hosts: healthyHosts.map((host) =>
            host.id === "host-a" ? { ...host, corrupt: true } : host,
          ),
        };
      }
      return { ...current, hosts: healthyHosts };
    });
    setNotice(`${scenarioCopy[id].name} scenario applied.`);
  }

  async function publishDraft() {
    if (publishLock.current || !canPublish) return;
    publishLock.current = true;
    setPublishing(true);
    setNotice("Validating canonical bytes and preparing simulated replicas…");
    try {
      const revision = lab.revision + 1;
      const normalized = normalizeSite(draft);
      if (!publisherIdentity) {
        throw new Error("Publisher identity is not available.");
      }
      const published = await publishSite(
        normalized,
        revision,
        lab.hosts,
        publisherIdentity,
      );
      const replicas = published.hosts.filter(
        (host) => host.objects[published.head.objectID],
      ).length;
      setDraft(normalized);
      setPublishedSite(normalized);
      setLab({ head: published.head, hosts: published.hosts, revision });
      setPublicationHistory((current) =>
        [
          {
            revision,
            objectID: published.head.objectID,
            finalizedAt: published.head.finalizedAt,
            replicas,
          },
          ...current.filter((record) => record.revision !== revision),
        ].slice(0, 20),
      );
      setNotice(
        `Revision ${revision} finalized locally with ${replicas} simulated ${
          replicas === 1 ? "replica" : "replicas"
        }.`,
      );
      setActiveView("overview");
    } catch (error) {
      setNotice(
        error instanceof Error
          ? `Publication rejected: ${error.message}`
          : "Publication rejected by the lab profile.",
      );
    } finally {
      setPublishing(false);
      publishLock.current = false;
    }
  }

  async function resetWorkspace() {
    if (!publisherIdentity) {
      setNotice("Publisher identity is not available.");
      return;
    }
    const published = await publishSite(
      seedSite,
      1,
      createHosts(),
      publisherIdentity,
    );
    const record: PublicationRecord = {
      revision: 1,
      objectID: published.head.objectID,
      finalizedAt: published.head.finalizedAt,
      replicas: 2,
    };
    setDraft(seedSite);
    setPublishedSite(seedSite);
    setAddress(LAB_ADDRESS);
    setActiveAddress(LAB_ADDRESS);
    setNavigationHistory([LAB_ADDRESS]);
    setHistoryIndex(0);
    setUsePassthrough(false);
    setSelectedScenario("healthy");
    setPublicationHistory([record]);
    setLab({ head: published.head, hosts: published.hosts, revision: 1 });
    setNotice("Workspace restored to the verified lab baseline.");
  }

  async function copyObjectID() {
    if (!lab.head) return;
    try {
      await navigator.clipboard.writeText(lab.head.objectID);
      setNotice("Object ID copied.");
    } catch {
      setNotice("Clipboard access is unavailable in this browser.");
    }
  }

  function exportReport() {
    const report = {
      generatedAt: new Date().toISOString(),
      environment: "local-simulation",
      profile: LAB_PROFILE,
      address: lab.head?.address ?? null,
      head: lab.head,
      publisherIdentity: lab.head
        ? {
            publisherID: lab.head.publisherID,
            algorithm: lab.head.signatureAlgorithm,
          }
        : null,
      route: resolution?.route ?? null,
      path: resolution?.path ?? [],
      integrity: resolution?.status ?? "resolving",
      hosts: lab.hosts.map(({ objects, ...host }) => ({
        ...host,
        objectCount: Object.keys(objects).length,
      })),
      trace: resolution?.trace ?? [],
    };
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(report, null, 2)], {
        type: "application/json",
      }),
    );
    const link = document.createElement("a");
    link.href = url;
    link.download = `noctweb-lab-r${lab.revision || 0}-report.json`;
    link.click();
    URL.revokeObjectURL(url);
    setNotice("Local diagnostic report exported.");
  }

  async function installApp() {
    if (!installPrompt) return;
    await installPrompt.prompt();
    const choice = await installPrompt.userChoice;
    setNotice(
      choice.outcome === "accepted"
        ? "Noctweb Lab installation accepted."
        : "App installation dismissed.",
    );
    setInstallPrompt(null);
  }

  const copy = viewCopy[activeView];

  return (
    <main className="product-shell">
      <header className="topbar">
        <div className="wordmark">
          <span className="wordmark-symbol" aria-hidden="true">
            <i />
            <i />
            <i />
          </span>
          <span className="wordmark-name">NOCTWEB</span>
          <span className="wordmark-product">LAB</span>
        </div>
        <div className="topbar-context">
          <span className="topbar-path">Quiet Garden</span>
          <span className="topbar-separator">/</span>
          <span>{copy.title}</span>
        </div>
        <div className="environment-status">
          {installPrompt && (
            <button
              type="button"
              className="install-button"
              onClick={() => void installApp()}
            >
              Install app
            </button>
          )}
          <span className="live-dot" />
          <span>Local simulation</span>
          <span className="profile-chip">{LAB_PROFILE}</span>
        </div>
      </header>

      <div className="app-frame">
        <aside className="sidebar">
          <div className="workspace-card">
            <span className="workspace-avatar">QG</span>
            <div>
              <strong>Quiet Garden</strong>
              <span>
                {lab.head
                  ? `Publisher ${compactID(lab.head.publisherID, 5)}`
                  : "Creating publisher identity…"}
              </span>
            </div>
          </div>

          <nav className="primary-navigation" aria-label="Workspace">
            {navigation.map((item) => (
              <button
                type="button"
                key={item.id}
                className={activeView === item.id ? "active" : ""}
                aria-current={activeView === item.id ? "page" : undefined}
                onClick={() => setActiveView(item.id)}
              >
                <span className="nav-icon" aria-hidden="true">
                  {item.icon}
                </span>
                <span className="nav-copy">
                  <strong>{item.label}</strong>
                  <small>{item.description}</small>
                </span>
              </button>
            ))}
          </nav>

          <div className="sidebar-boundary">
            <span className="boundary-icon" aria-hidden="true">
              ◎
            </span>
            <div>
              <strong>Local simulation</strong>
              <p>
                Installable app. Real local publisher signature, mock consensus,
                and no production security claim.
              </p>
            </div>
          </div>
        </aside>

        <section className="product-content">
          <header className="page-header">
            <div>
              <span className="page-eyebrow">{copy.eyebrow}</span>
              <h1>{copy.title}</h1>
              <p>{copy.description}</p>
            </div>
            <div className="page-actions">
              {activeView !== "publish" && (
                <button
                  type="button"
                  className="button secondary"
                  onClick={() => setActiveView("publish")}
                >
                  Edit publication
                </button>
              )}
              {activeView === "network" ? (
                <button
                  type="button"
                  className="button quiet"
                  onClick={() => void resetWorkspace()}
                >
                  Reset workspace
                </button>
              ) : (
                <span
                  className={`head-status ${
                    resolution?.status === "verified" ? "good" : "warning"
                  }`}
                >
                  <i />
                  {resolution?.status === "verified"
                    ? "Object integrity passed"
                    : resolution?.status === "rejected"
                      ? "Object rejected"
                      : "Awaiting valid object"}
                </span>
              )}
            </div>
          </header>

          <div className="notice-strip" role="status" aria-live="polite">
            <span aria-hidden="true">i</span>
            <p>{notice}</p>
          </div>

          {activeView === "overview" && (
            <div className="view-stack">
              <section className="metrics-grid" aria-label="Workspace status">
                <MetricCard
                  label="Object integrity"
                  value={
                    resolution?.status === "verified"
                      ? "Passed"
                      : resolution?.status === "rejected"
                        ? "Rejected"
                        : "Unavailable"
                  }
                  detail="Exact SHA-256 bytes"
                  tone={
                    resolution?.status === "verified" ? "good" : "warning"
                  }
                />
                <MetricCard
                  label="Finalized head"
                  value={lab.head ? `Revision ${lab.head.revision}` : "Pending"}
                  detail={
                    lab.head
                      ? `Mock finality · ${formatTime(lab.head.finalizedAt)}`
                      : "Deterministic consensus"
                  }
                />
                <MetricCard
                  label="Host replicas"
                  value={`${replicaCount} of ${lab.hosts.length}`}
                  detail="Simulated exact-byte storage"
                  tone={replicaCount > 0 ? "good" : "warning"}
                />
                <MetricCard
                  label="Retrieval path"
                  value={usePassthrough ? "One hop" : "Direct"}
                  detail={
                    usePassthrough
                      ? "Bounded passthrough"
                      : "Client-selected host"
                  }
                />
              </section>

              <section className="overview-grid">
                <Panel
                  className="browser-surface"
                  eyebrow="Runtime"
                  title="Noctweb Browser"
                  action={
                    <span
                      className={`runtime-badge ${
                        resolution?.status === "verified" ? "good" : "warning"
                      }`}
                    >
                      {resolution?.status === "verified"
                        ? "Integrity passed"
                        : "Not rendered"}
                    </span>
                  }
                >
                  <div className="browser-toolbar">
                    <div className="history-controls">
                      <button
                        type="button"
                        aria-label="Go back"
                        disabled={historyIndex === 0}
                        onClick={() => moveHistory(-1)}
                      >
                        ←
                      </button>
                      <button
                        type="button"
                        aria-label="Go forward"
                        disabled={historyIndex >= navigationHistory.length - 1}
                        onClick={() => moveHistory(1)}
                      >
                        →
                      </button>
                      <button
                        type="button"
                        aria-label="Reload"
                        onClick={() => setReloadNonce((current) => current + 1)}
                      >
                        ↻
                      </button>
                    </div>
                    <form className="address-bar" onSubmit={navigate}>
                      <span
                        className={
                          resolution?.status === "verified"
                            ? "address-state good"
                            : "address-state warning"
                        }
                        aria-hidden="true"
                      >
                        ◇
                      </span>
                      <input
                        aria-label="Noctweb address"
                        value={address}
                        spellCheck={false}
                        onChange={(event) => setAddress(event.target.value)}
                      />
                      <span className="address-profile">{LAB_PROFILE}</span>
                    </form>
                  </div>

                  <div className="browser-viewport">
                    {resolution?.status === "verified" ? (
                      <iframe
                        data-testid="site-frame"
                        title={`Noctweb site: ${resolution.site.title}`}
                        sandbox=""
                        srcDoc={resolution.html}
                      />
                    ) : (
                      <div
                        className="browser-failure"
                        data-testid="failure-view"
                      >
                        <span aria-hidden="true">
                          {resolution?.status === "rejected" ? "!" : "×"}
                        </span>
                        <p className="failure-kicker">
                          {resolution?.status === "rejected"
                            ? "Object integrity failed"
                            : "Publication unavailable"}
                        </p>
                        <h2>No acceptable bytes were rendered.</h2>
                        <p>
                          Noctweb fails closed. Restore a host with bytes that
                          match the finalized object ID, then reload.
                        </p>
                      </div>
                    )}
                  </div>

                  <div className="browser-footer">
                    <div>
                      <span
                        className={`status-indicator ${
                          resolution?.status ?? "loading"
                        }`}
                      />
                      <strong>
                        {resolution?.status === "verified"
                          ? "Integrity verified"
                          : "Not rendered"}
                      </strong>
                    </div>
                    <span>{activeHost?.name ?? "No accepted host"}</span>
                    <span className="footer-spacer" />
                    <span>
                      {usePassthrough
                        ? "1 simulated passthrough hop"
                        : "Direct retrieval"}
                    </span>
                  </div>
                </Panel>

                <div className="evidence-column">
                  <Panel eyebrow="Trust report" title="Evidence, separated">
                    <div className="evidence-list">
                      <div>
                        <span
                          className={`evidence-mark ${
                            resolution?.status === "verified"
                              ? "passed"
                              : "failed"
                          }`}
                        >
                          {resolution?.status === "verified" ? "✓" : "×"}
                        </span>
                        <div>
                          <strong>Object integrity</strong>
                          <p>
                            {resolution?.status === "verified"
                              ? "Digest matches finalized object ID."
                              : "No acceptable exact-byte object."}
                          </p>
                        </div>
                        <span className="evidence-result">
                          {resolution?.status === "verified"
                            ? "Passed"
                            : "Not passed"}
                        </span>
                      </div>
                      <div>
                        <span
                          className={`evidence-mark ${
                            publisherPassed ? "passed" : "failed"
                          }`}
                        >
                          {publisherPassed ? "✓" : "×"}
                        </span>
                        <div>
                          <strong>Publisher authority</strong>
                          <p>
                            {publisherPassed
                              ? "Publication-scoped signed head accepted."
                              : "Publisher head has not been verified."}
                          </p>
                        </div>
                        <span className="evidence-result">
                          {publisherPassed ? "Passed" : "Not passed"}
                        </span>
                      </div>
                      <div>
                        <span className="evidence-mark simulated">M</span>
                        <div>
                          <strong>Consensus finality</strong>
                          <p>{LAB_CONSENSUS_PROFILE.profile}</p>
                        </div>
                        <span className="evidence-result simulated">Mock</span>
                      </div>
                      <div>
                        <span className="evidence-mark passed">✓</span>
                        <div>
                          <strong>Runtime sandbox</strong>
                          <p>Originless, static, and script-disabled.</p>
                        </div>
                        <span className="evidence-result">Locked</span>
                      </div>
                    </div>
                  </Panel>

                  <Panel
                    eyebrow="Finalized object"
                    title={lab.head ? `Revision ${lab.head.revision}` : "Pending"}
                    action={
                      <button
                        type="button"
                        className="text-button"
                        disabled={!lab.head}
                        onClick={() => void copyObjectID()}
                      >
                        Copy ID
                      </button>
                    }
                  >
                    <dl className="object-summary">
                      <div>
                        <dt>Address</dt>
                        <dd>{lab.head?.address ?? "Pending"}</dd>
                      </div>
                      <div>
                        <dt>Object ID</dt>
                        <dd title={lab.head?.objectID}>
                          {compactID(lab.head?.objectID)}
                        </dd>
                      </div>
                      <div>
                        <dt>Publisher ID</dt>
                        <dd title={lab.head?.publisherID}>
                          {compactID(lab.head?.publisherID)}
                        </dd>
                      </div>
                      <div>
                        <dt>Accepted host</dt>
                        <dd>{activeHost?.name ?? "None"}</dd>
                      </div>
                      <div>
                        <dt>Canonical size</dt>
                        <dd>{objectBytes || 0} bytes</dd>
                      </div>
                    </dl>
                    <div className="route-path" aria-label="Resolution path">
                      {(resolution?.path ?? ["Noctweb Browser"]).map(
                        (node, index, path) => (
                          <div key={`${node}-${index}`}>
                            <span>{node}</span>
                            {index < path.length - 1 && <i>→</i>}
                          </div>
                        ),
                      )}
                    </div>
                  </Panel>
                </div>
              </section>

              <Panel
                className="scenario-panel"
                eyebrow="Test runs"
                title="Exercise the trust boundary"
                action={
                  <button
                    type="button"
                    className="text-button"
                    onClick={() => setActiveView("inspector")}
                  >
                    Open inspector
                  </button>
                }
              >
                <div className="scenario-grid">
                  {(Object.keys(scenarioCopy) as ScenarioID[]).map((id) => {
                    const scenario = scenarioCopy[id];
                    return (
                      <button
                        type="button"
                        key={id}
                        className={
                          selectedScenario === id ? "selected" : undefined
                        }
                        aria-pressed={selectedScenario === id}
                        onClick={() => applyScenario(id)}
                      >
                        <span aria-hidden="true">{scenario.icon}</span>
                        <div>
                          <strong>{scenario.name}</strong>
                          <p>{scenario.description}</p>
                        </div>
                        <i aria-hidden="true">→</i>
                      </button>
                    );
                  })}
                </div>
              </Panel>
            </div>
          )}

          {activeView === "publish" && (
            <section className="studio-grid">
              <Panel
                className="editor-surface"
                eyebrow="Draft"
                title="Publication content"
                action={
                  <span className={`draft-state ${isDirty ? "dirty" : ""}`}>
                    <i />
                    {isDirty ? "Unsaved revision" : "Matches head"}
                  </span>
                }
              >
                <div className="template-picker">
                  <span>Start from a format</span>
                  <div>
                    {templates.map((template) => (
                      <button
                        type="button"
                        key={template.name}
                        onClick={() => {
                          setDraft(template.site);
                          setNotice(`${template.name} format applied to draft.`);
                        }}
                      >
                        <strong>{template.name}</strong>
                        <small>{template.description}</small>
                      </button>
                    ))}
                  </div>
                </div>

                <div className="editor-form">
                  <label>
                    <span>
                      Site title <small>{draft.title.length}/80</small>
                    </span>
                    <input
                      value={draft.title}
                      maxLength={80}
                      onChange={(event) =>
                        setDraft((current) => ({
                          ...current,
                          title: event.target.value,
                        }))
                      }
                    />
                  </label>
                  <label>
                    <span>
                      Subtitle <small>{draft.subtitle.length}/160</small>
                    </span>
                    <input
                      value={draft.subtitle}
                      maxLength={160}
                      onChange={(event) =>
                        setDraft((current) => ({
                          ...current,
                          subtitle: event.target.value,
                        }))
                      }
                    />
                  </label>
                  <label>
                    <span>
                      Body <small>{draft.body.length}/1200</small>
                    </span>
                    <textarea
                      value={draft.body}
                      maxLength={1_200}
                      onChange={(event) =>
                        setDraft((current) => ({
                          ...current,
                          body: event.target.value,
                        }))
                      }
                    />
                  </label>
                  <label className="accent-field">
                    <span>Accent color</span>
                    <div>
                      <input
                        type="color"
                        value={draft.accent}
                        aria-label="Publication accent color"
                        onChange={(event) =>
                          setDraft((current) => ({
                            ...current,
                            accent: event.target.value,
                          }))
                        }
                      />
                      <code>{draft.accent}</code>
                    </div>
                  </label>
                </div>

                <div className="publish-action">
                  <div>
                    <strong>Publish revision {lab.revision + 1}</strong>
                    <p>
                      Validates canonical bytes, stores them on available simulated
                      hosts, then advances the mock head.
                    </p>
                  </div>
                  <button
                    type="button"
                    className="button primary"
                    disabled={!canPublish}
                    onClick={() => void publishDraft()}
                  >
                    {publishing ? "Publishing…" : "Publish revision"}
                  </button>
                </div>
              </Panel>

              <div className="studio-preview-column">
                <Panel
                  className="draft-preview"
                  eyebrow="Local preview"
                  title="Scriptless renderer"
                  action={<span className="profile-chip">{LAB_PROFILE}</span>}
                >
                  <div className="preview-address">
                    <span>◇</span>
                    <code>{LAB_ADDRESS}</code>
                    <span>Draft</span>
                  </div>
                  <iframe
                    title="Draft publication preview"
                    sandbox=""
                    srcDoc={draftPreview}
                  />
                </Panel>

                <Panel eyebrow="Release pipeline" title="Publication evidence">
                  <ol className="pipeline-list">
                    <li className="complete">
                      <span>1</span>
                      <div>
                        <strong>Validate</strong>
                        <p>Bounded fields and deterministic canonical JSON.</p>
                      </div>
                    </li>
                    <li className="simulated">
                      <span>2</span>
                      <div>
                        <strong>Publisher authority</strong>
                        <p>
                          Publication-scoped Ed25519 lab identity and signed head.
                        </p>
                      </div>
                    </li>
                    <li className="complete">
                      <span>3</span>
                      <div>
                        <strong>Replicate</strong>
                        <p>{replicaCount} simulated host replicas available.</p>
                      </div>
                    </li>
                    <li className="simulated">
                      <span>4</span>
                      <div>
                        <strong>Finalize</strong>
                        <p>Deterministic mock head, not production consensus.</p>
                      </div>
                    </li>
                  </ol>
                </Panel>
              </div>
            </section>
          )}

          {activeView === "network" && (
            <div className="view-stack">
              <Panel
                className="topology-surface"
                eyebrow="Active path"
                title="Local simulation topology"
                action={
                  <div className="route-selector" aria-label="Retrieval route">
                    <button
                      type="button"
                      className={!usePassthrough ? "active" : ""}
                      aria-pressed={!usePassthrough}
                      onClick={() => {
                        setUsePassthrough(false);
                        setNotice("Direct host retrieval selected.");
                      }}
                    >
                      Direct
                    </button>
                    <button
                      type="button"
                      className={usePassthrough ? "active" : ""}
                      aria-pressed={usePassthrough}
                      onClick={() => {
                        setUsePassthrough(true);
                        setNotice("One bounded passthrough hop selected.");
                      }}
                    >
                      Passthrough
                    </button>
                  </div>
                }
              >
                <div className="topology-canvas">
                  <div className="topology-node consensus">
                    <span>C</span>
                    <div>
                      <strong>Mock consensus adapter</strong>
                      <small>Head + locator commitments only</small>
                    </div>
                    <i>SIMULATED</i>
                  </div>
                  <span className="topology-connector vertical" />
                  <div className="retrieval-lane">
                    <div className="topology-node runtime">
                      <span>N</span>
                      <div>
                        <strong>Noctweb Browser</strong>
                        <small>Chooses path and verifies locally</small>
                      </div>
                    </div>
                    <span className="topology-arrow">→</span>
                    {usePassthrough && (
                      <>
                        <div className="topology-node passthrough">
                          <span>P</span>
                          <div>
                            <strong>Passthrough relay</strong>
                            <small>One bounded opaque exchange</small>
                          </div>
                        </div>
                        <span className="topology-arrow">→</span>
                      </>
                    )}
                    <div className="host-node-group">
                      {lab.hosts.map((host) => (
                        <div
                          className={`topology-node host ${
                            host.online ? "" : "offline"
                          }`}
                          key={`${host.id}-topology`}
                        >
                          <span>H</span>
                          <div>
                            <strong>{host.name}</strong>
                            <small>
                              {host.online
                                ? host.corrupt
                                  ? "Serving invalid candidate bytes"
                                  : "Exact-byte object available"
                                : "Unavailable"}
                            </small>
                          </div>
                          <i>
                            {host.online
                              ? host.corrupt
                                ? "INVALID"
                                : "ONLINE"
                              : "OFFLINE"}
                          </i>
                        </div>
                      ))}
                    </div>
                  </div>
                  <div className="control-lane">
                    <span className="lane-label">Private control plane</span>
                    <div className="topology-node standard">
                      <span>S</span>
                      <div>
                        <strong>Standard relay</strong>
                        <small>
                          Invitations and collaboration; not in public retrieval
                        </small>
                      </div>
                      <i>SEPARATE</i>
                    </div>
                  </div>
                </div>
              </Panel>

              <section className="relay-role-grid">
                {LAB_RELAY_ROLES.map((role) => (
                  <article className={`relay-role ${role.id}`} key={role.id}>
                    <header>
                      <span>{role.id.slice(0, 1).toUpperCase()}</span>
                      <div>
                        <h2>{role.name}</h2>
                        <code>{role.module}</code>
                      </div>
                      <i>LAB</i>
                    </header>
                    <p>{role.purpose}</p>
                    <dl>
                      <div>
                        <dt>Storage</dt>
                        <dd>{role.storage}</dd>
                      </div>
                      <div>
                        <dt>Boundary</dt>
                        <dd>{role.boundary}</dd>
                      </div>
                    </dl>
                  </article>
                ))}
              </section>

              <section className="network-details-grid">
                <Panel eyebrow="Host relays" title="Simulated instances">
                  <div className="host-manager">
                    {lab.hosts.map((host) => (
                      <article key={host.id}>
                        <div className="host-identity">
                          <span className={host.online ? "online" : "offline"}>
                            H
                          </span>
                          <div>
                            <strong>{host.name}</strong>
                            <p>{host.location}</p>
                          </div>
                        </div>
                        <div className="host-facts">
                          <span>
                            {Object.keys(host.objects).length} stored{" "}
                            {Object.keys(host.objects).length === 1
                              ? "object"
                              : "objects"}
                          </span>
                          <span>
                            {host.corrupt
                              ? "Invalid response injected"
                              : "Exact-byte response"}
                          </span>
                        </div>
                        <div className="host-actions">
                          <button
                            type="button"
                            className={host.online ? "active" : ""}
                            aria-pressed={host.online}
                            onClick={() =>
                              updateHost(host.id, { online: !host.online })
                            }
                          >
                            {host.online ? "Online" : "Offline"}
                          </button>
                          <button
                            type="button"
                            className={host.corrupt ? "danger active" : ""}
                            aria-pressed={host.corrupt}
                            disabled={!host.online}
                            onClick={() =>
                              updateHost(host.id, { corrupt: !host.corrupt })
                            }
                          >
                            {host.corrupt ? "Invalid bytes" : "Inject fault"}
                          </button>
                        </div>
                      </article>
                    ))}
                  </div>
                </Panel>

                <Panel eyebrow="Consensus boundary" title="Finality evidence">
                  <dl className="consensus-details">
                    <div>
                      <dt>Profile</dt>
                      <dd>{LAB_CONSENSUS_PROFILE.profile}</dd>
                    </div>
                    <div>
                      <dt>Epoch</dt>
                      <dd>{LAB_CONSENSUS_PROFILE.epoch}</dd>
                    </div>
                    <div>
                      <dt>Evidence</dt>
                      <dd>{LAB_CONSENSUS_PROFILE.evidence}</dd>
                    </div>
                    <div>
                      <dt>Validity</dt>
                      <dd>{LAB_CONSENSUS_PROFILE.validity}</dd>
                    </div>
                    <div>
                      <dt>Current head</dt>
                      <dd>{lab.head ? `Revision ${lab.head.revision}` : "Pending"}</dd>
                    </div>
                    <div>
                      <dt>Finalized locators</dt>
                      <dd>{lab.hosts.length} simulated hosts</dd>
                    </div>
                  </dl>
                  <div className="boundary-note">
                    <span>!</span>
                    <p>
                      Consensus does not store capsule bodies, select retrieval
                      paths, guarantee availability, or judge execution safety.
                    </p>
                  </div>
                </Panel>
              </section>
            </div>
          )}

          {activeView === "inspector" && (
            <div className="view-stack">
              <section className="inspector-grid">
                <Panel
                  className="trace-surface"
                  eyebrow="Resolution run"
                  title={scenarioCopy[selectedScenario].name}
                  action={
                    <span
                      className={`runtime-badge ${
                        resolution?.status === "verified" ? "good" : "warning"
                      }`}
                    >
                      {resolution?.status ?? "Resolving"}
                    </span>
                  }
                >
                  <ol className="trace-timeline">
                    {(resolution?.trace ?? []).map((entry, index) => (
                      <li className={entry.kind} key={`${entry.message}-${index}`}>
                        <span>{String(index + 1).padStart(2, "0")}</span>
                        <i>
                          {entry.kind === "success"
                            ? "✓"
                            : entry.kind === "failure"
                              ? "!"
                              : entry.kind === "warning"
                                ? "·"
                                : "i"}
                        </i>
                        <div>
                          <strong>
                            {entry.kind === "success"
                              ? "Accepted"
                              : entry.kind === "failure"
                                ? "Rejected"
                                : entry.kind === "warning"
                                  ? "Fallback"
                                  : "Runtime"}
                          </strong>
                          <p>{entry.message}</p>
                        </div>
                      </li>
                    ))}
                  </ol>
                </Panel>

                <Panel
                  className="raw-object-surface"
                  eyebrow="Canonical object"
                  title={`${objectBytes} bytes`}
                  action={
                    <button
                      type="button"
                      className="text-button"
                      onClick={exportReport}
                    >
                      Export report
                    </button>
                  }
                >
                  <dl className="inspector-facts">
                    <div>
                      <dt>Object ID</dt>
                      <dd>{compactID(lab.head?.objectID, 12)}</dd>
                    </div>
                    <div>
                      <dt>Encoding</dt>
                      <dd>Canonical JSON · lab-v0</dd>
                    </div>
                    <div>
                      <dt>Digest</dt>
                      <dd>SHA-256</dd>
                    </div>
                    <div>
                      <dt>Publisher signature</dt>
                      <dd>
                        {lab.head
                          ? `${lab.head.signatureAlgorithm} · verified locally`
                          : "Pending"}
                      </dd>
                    </div>
                    <div>
                      <dt>Publisher ID</dt>
                      <dd>{compactID(lab.head?.publisherID, 12)}</dd>
                    </div>
                  </dl>
                  <pre>
                    <code>{canonicalObject || "No canonical object available."}</code>
                  </pre>
                  <div className="inspector-warning">
                    lab-v0 is intentionally incompatible. These bytes are not a
                    stable Noctweave Net wire object.
                  </div>
                </Panel>
              </section>

              <Panel
                eyebrow="Revision history"
                title="Local publications"
                action={
                  <span className="history-count">
                    {publicationHistory.length}{" "}
                    {publicationHistory.length === 1 ? "revision" : "revisions"}
                  </span>
                }
              >
                <div className="revision-table" role="table">
                  <div className="revision-row header" role="row">
                    <span role="columnheader">Revision</span>
                    <span role="columnheader">Object ID</span>
                    <span role="columnheader">Replicas</span>
                    <span role="columnheader">Finalized</span>
                    <span role="columnheader">Evidence</span>
                  </div>
                  {publicationHistory.map((record, index) => (
                    <div
                      className="revision-row"
                      role="row"
                      key={`${record.objectID}-${record.revision}`}
                    >
                      <strong role="cell">
                        R{record.revision}
                        {index === 0 && <i>Current</i>}
                      </strong>
                      <code role="cell">{compactID(record.objectID, 10)}</code>
                      <span role="cell">
                        {record.replicas}/{lab.hosts.length} simulated
                      </span>
                      <span role="cell">{formatTime(record.finalizedAt)}</span>
                      <span role="cell" className="mock-evidence">
                        Mock finality
                      </span>
                    </div>
                  ))}
                </div>
              </Panel>
            </div>
          )}
        </section>
      </div>
    </main>
  );
}
