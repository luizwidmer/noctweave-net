"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import {
  LAB_ADDRESS,
  LAB_PROFILE,
  LabHead,
  LabHost,
  LabResolution,
  LabSite,
  createHosts,
  publishSite,
  resolveSite,
} from "../lib/lab-v0";

const seedSite: LabSite = {
  title: "A garden with no address",
  subtitle: "Field notes from a website that belongs to its author, not its host.",
  body:
    "The page you are reading was reconstructed from verified objects. Its host can change without changing what it is.\n\nTurn a host off. Corrupt its bytes. Route through a passthrough relay. Noctweb will keep the identity stable and reject anything that fails verification.",
  accent: "#6ee7bd",
};

type LabState = {
  head: LabHead | null;
  hosts: LabHost[];
  revision: number;
};

function compactID(value: string | null | undefined) {
  return value ? `${value.slice(0, 10)}…${value.slice(-6)}` : "pending";
}

export default function Home() {
  const [lab, setLab] = useState<LabState>({
    head: null,
    hosts: createHosts(),
    revision: 0,
  });
  const [draft, setDraft] = useState<LabSite>(seedSite);
  const [address, setAddress] = useState(LAB_ADDRESS);
  const [activeAddress, setActiveAddress] = useState(LAB_ADDRESS);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [usePassthrough, setUsePassthrough] = useState(false);
  const [resolution, setResolution] = useState<LabResolution | null>(null);
  const [notice, setNotice] = useState("Starting deterministic testnet…");

  const publish = useCallback(async (site: LabSite, resetHosts = false) => {
    const baseHosts = resetHosts ? createHosts() : lab.hosts;
    const revision = lab.revision + 1;
    const published = await publishSite(site, revision, baseHosts);
    setLab({ head: published.head, hosts: published.hosts, revision });
    setNotice(
      `Revision ${revision} finalized and stored on ${
        published.hosts.filter((host) => host.objects[published.head.objectID]).length
      } hosts.`,
    );
  }, [lab.hosts, lab.revision]);

  useEffect(() => {
    if (lab.head === null && lab.revision === 0) {
      void publishSite(seedSite, 1, createHosts()).then((published) => {
        setLab({ head: published.head, hosts: published.hosts, revision: 1 });
        setNotice("Revision 1 finalized. The browser is ready.");
      });
    }
  }, [lab.head, lab.revision]);

  useEffect(() => {
    let active = true;
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

  function navigate(event: FormEvent) {
    event.preventDefault();
    setActiveAddress(address.trim());
  }

  function updateHost(id: LabHost["id"], change: Partial<LabHost>) {
    setLab((current) => ({
      ...current,
      hosts: current.hosts.map((host) =>
        host.id === id ? { ...host, ...change } : host,
      ),
    }));
  }

  async function resetLab() {
    const published = await publishSite(seedSite, 1, createHosts());
    setDraft(seedSite);
    setAddress(LAB_ADDRESS);
    setActiveAddress(LAB_ADDRESS);
    setUsePassthrough(false);
    setLab({ head: published.head, hosts: published.hosts, revision: 1 });
    setNotice("Testnet restored to its verified baseline.");
  }

  return (
    <main className="lab-shell">
      <header className="lab-header">
        <div className="brand">
          <span className="brand-mark" aria-hidden="true">
            <i />
            <i />
            <i />
          </span>
          <span className="brand-name">NOCTWEB</span>
          <span className="brand-product">LAB</span>
          <span className="profile-badge">{LAB_PROFILE}</span>
        </div>
        <div className="header-state">
          <span className="pulse" />
          LOCAL TESTNET
          <span className="divider" />
          <span className="muted">scripts disabled</span>
        </div>
      </header>

      <section className="workspace">
        <aside className="left-rail">
          <section className="panel publisher-panel">
            <div className="panel-heading">
              <span>PUBLISHER STUDIO</span>
              <span className="status-number">R{lab.revision || "—"}</span>
            </div>
            <label>
              <span>Site title</span>
              <input
                value={draft.title}
                maxLength={80}
                onChange={(event) =>
                  setDraft((current) => ({ ...current, title: event.target.value }))
                }
              />
            </label>
            <label>
              <span>Subtitle</span>
              <input
                value={draft.subtitle}
                maxLength={160}
                onChange={(event) =>
                  setDraft((current) => ({ ...current, subtitle: event.target.value }))
                }
              />
            </label>
            <label>
              <span>Body</span>
              <textarea
                value={draft.body}
                maxLength={1_200}
                onChange={(event) =>
                  setDraft((current) => ({ ...current, body: event.target.value }))
                }
              />
            </label>
            <div className="accent-row">
              <label>
                <span>Accent</span>
                <input
                  className="color-input"
                  type="color"
                  value={draft.accent}
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, accent: event.target.value }))
                  }
                />
              </label>
              <button className="primary-action" onClick={() => void publish(draft)}>
                Publish revision
              </button>
            </div>
            <p className="notice" aria-live="polite">{notice}</p>
          </section>

          <section className="panel topology-panel">
            <div className="panel-heading">
              <span>TESTNET TOPOLOGY</span>
              <button className="text-action" onClick={() => void resetLab()}>
                Reset
              </button>
            </div>
            <div className="consensus-node">
              <div className="node-icon consensus-icon">C</div>
              <div>
                <strong>Mock consensus</strong>
                <span>finalized head · deterministic</span>
              </div>
              <span className="node-state ok">LIVE</span>
            </div>
            <div className="topology-line" />
            {lab.hosts.map((host) => (
              <div className="host-row" key={host.id}>
                <div className={`node-icon ${host.online ? "" : "offline-icon"}`}>H</div>
                <div className="host-copy">
                  <strong>{host.name}</strong>
                  <span>{host.location}</span>
                </div>
                <button
                  className={`state-toggle ${host.online ? "online" : "offline"}`}
                  aria-label={`${host.online ? "Take" : "Bring"} ${host.name} ${
                    host.online ? "offline" : "online"
                  }`}
                  onClick={() => updateHost(host.id, { online: !host.online })}
                >
                  {host.online ? "ONLINE" : "OFFLINE"}
                </button>
              </div>
            ))}
          </section>
        </aside>

        <section className="browser-column">
          <div className="browser-frame">
            <div className="browser-toolbar">
              <div className="window-controls" aria-hidden="true">
                <span />
                <span />
                <span />
              </div>
              <button className="nav-button" aria-label="Back" disabled>←</button>
              <button className="nav-button" aria-label="Forward" disabled>→</button>
              <button
                className="nav-button"
                aria-label="Reload"
                onClick={() => setReloadNonce((current) => current + 1)}
              >
                ↻
              </button>
              <form className="address-form" onSubmit={navigate}>
                <span className="verified-lock" aria-hidden="true">◇</span>
                <input
                  aria-label="Noctweb address"
                  value={address}
                  spellCheck={false}
                  onChange={(event) => setAddress(event.target.value)}
                />
                <span className="address-profile">{LAB_PROFILE}</span>
              </form>
              <button className="menu-button" aria-label="Browser menu">•••</button>
            </div>

            <div className="site-viewport">
              {resolution?.status === "verified" ? (
                <iframe
                  data-testid="site-frame"
                  title={`Noctweb site: ${resolution.site.title}`}
                  sandbox=""
                  srcDoc={resolution.html}
                />
              ) : (
                <div className="failure-view" data-testid="failure-view">
                  <span className="failure-glyph">×</span>
                  <p className="failure-label">
                    {resolution?.status === "rejected"
                      ? "VERIFICATION REJECTED"
                      : "SITE UNAVAILABLE"}
                  </p>
                  <h1>The finalized object could not be rendered.</h1>
                  <p>
                    Noctweb never substitutes unverified bytes. Restore a valid host
                    or reset the testnet.
                  </p>
                </div>
              )}
            </div>
            <div className="browser-statusbar">
              <span className={`status-dot ${resolution?.status ?? "loading"}`} />
              <strong>{resolution?.status === "verified" ? "VERIFIED" : "NOT RENDERED"}</strong>
              <span>{activeHost?.name ?? "No accepted host"}</span>
              <span className="status-spacer" />
              <span>{usePassthrough ? "1 PASSTHROUGH HOP" : "DIRECT RETRIEVAL"}</span>
            </div>
          </div>

          <section className="fault-deck">
            <div>
              <span className="section-kicker">FAULT DECK</span>
              <h2>Break the network, not the identity.</h2>
            </div>
            <div className="fault-controls">
              <label className="switch-control">
                <input
                  type="checkbox"
                  checked={usePassthrough}
                  onChange={(event) => setUsePassthrough(event.target.checked)}
                />
                <span className="switch" />
                Passthrough route
              </label>
              {lab.hosts.map((host) => (
                <label className="switch-control" key={`${host.id}-corrupt`}>
                  <input
                    type="checkbox"
                    checked={host.corrupt}
                    disabled={!host.online}
                    onChange={(event) =>
                      updateHost(host.id, { corrupt: event.target.checked })
                    }
                  />
                  <span className="switch danger" />
                  Corrupt {host.name}
                </label>
              ))}
            </div>
          </section>
        </section>

        <aside className="right-rail">
          <section className="panel verification-panel">
            <div className="panel-heading">
              <span>VERIFICATION TRACE</span>
              <span className={`trace-state ${resolution?.status ?? "loading"}`}>
                {resolution?.status ?? "resolving"}
              </span>
            </div>
            <ol className="trace-list">
              {(resolution?.trace ?? []).map((entry, index) => (
                <li className={entry.kind} key={`${entry.message}-${index}`}>
                  <span>{entry.kind === "success" ? "✓" : entry.kind === "failure" ? "!" : "·"}</span>
                  <p>{entry.message}</p>
                </li>
              ))}
            </ol>
          </section>

          <section className="panel object-panel">
            <div className="panel-heading">
              <span>FINALIZED OBJECT</span>
            </div>
            <dl>
              <div>
                <dt>ADDRESS</dt>
                <dd>{lab.head?.address ?? "resolving"}</dd>
              </div>
              <div>
                <dt>OBJECT ID</dt>
                <dd title={lab.head?.objectID}>{compactID(lab.head?.objectID)}</dd>
              </div>
              <div>
                <dt>REVISION</dt>
                <dd>{lab.head ? `R${lab.head.revision}` : "—"}</dd>
              </div>
              <div>
                <dt>PROFILE</dt>
                <dd>{LAB_PROFILE} · static</dd>
              </div>
            </dl>
          </section>

          <section className="panel security-panel">
            <span className="security-icon">◎</span>
            <div>
              <strong>Sandbox locked</strong>
              <p>HTML and CSS only. No scripts, same-origin access, or capability APIs.</p>
            </div>
          </section>
        </aside>
      </section>
    </main>
  );
}
