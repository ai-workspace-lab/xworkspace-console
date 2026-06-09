import React, { useEffect, useMemo, useState } from 'react';
import ReactDOM from 'react-dom/client';
import './styles.css';

type Tab = {
  id: string;
  label: string;
  href: string;
  kind: 'internal' | 'external' | 'embed';
  icon?: string;
  closable?: boolean;
  source?: 'builtin' | 'custom';
};

type Service = {
  name: string;
  state: 'Running' | 'Degraded' | 'Stopped';
};

type NavItem = {
  id: string;
  label: string;
  icon: string;
  href: string;
  kind: Tab['kind'];
};

const navGroups: NavItem[][] = [
  [
    { id: 'workspace', label: 'Workspace', icon: 'home', href: '#workspace', kind: 'internal' },
  ],
  [
    { id: 'openclaw', label: 'OpenClaw', icon: 'claw', href: 'http://127.0.0.1:18789/channels', kind: 'embed' },
    { id: 'bridge', label: 'Bridge', icon: 'bridge', href: '#bridge', kind: 'internal' },
    { id: 'litellm', label: 'LiteLLM', icon: 'chart', href: 'http://127.0.0.1:4000/ui', kind: 'embed' },
    { id: 'vault', label: 'Vault', icon: 'shield', href: 'http://127.0.0.1:8200', kind: 'embed' },
  ],
  [
    { id: 'runtime', label: 'Runtime', icon: 'cube', href: '#runtime', kind: 'internal' },
    { id: 'terminal', label: 'Terminal', icon: 'terminal', href: 'http://127.0.0.1:7681', kind: 'embed' },
  ],
];

const builtinServiceTabs: Tab[] = [
  { id: 'openclaw', label: 'OpenClaw', href: 'http://127.0.0.1:18789/channels', kind: 'embed', icon: 'claw', closable: true, source: 'builtin' },
  { id: 'vault', label: 'Vault', href: 'http://127.0.0.1:8200', kind: 'embed', icon: 'shield', closable: true, source: 'builtin' },
  { id: 'litellm', label: 'LiteLLM', href: 'http://127.0.0.1:4000/ui', kind: 'embed', icon: 'chart', closable: true, source: 'builtin' },
  { id: 'terminal', label: 'Terminal', href: 'http://127.0.0.1:7681', kind: 'embed', icon: 'terminal', closable: true, source: 'builtin' },
];

const customWorkspaceTabs: Tab[] = [
  { id: 'runtime-console', label: 'Runtime', href: '#runtime-console', kind: 'internal', icon: 'cube', closable: true, source: 'custom' },
  { id: 'bridge-console', label: 'Bridge', href: '#bridge-console', kind: 'internal', icon: 'bridge', closable: true, source: 'custom' },
];

const initialTabs: Tab[] = [
  { id: 'workspace', label: 'Workspace', href: '#workspace', kind: 'internal', icon: 'home', source: 'builtin' },
  builtinServiceTabs[0],
];

const mockServices: Service[] = [
  { name: 'OpenClaw Gateway', state: 'Running' },
  { name: 'Bridge', state: 'Running' },
  { name: 'LiteLLM', state: 'Running' },
  { name: 'Vault', state: 'Running' },
  { name: 'XWorkmate Bridge', state: 'Running' },
];

const agents = [
  { name: 'Codex Agent', state: 'Idle', workspace: 'xworkspace-console', task: 'Homepage redesign' },
  { name: 'Hermes Agent', state: 'Running', workspace: 'messaging', task: 'Gateway sync' },
  { name: 'Gemini Agent', state: 'Idle', workspace: 'research', task: 'Waiting for input' },
  { name: 'Claude Agent', state: 'Running', workspace: 'docs', task: 'Design review' },
  { name: 'Qwen Agent', state: 'Idle', workspace: 'runtime', task: 'No active task' },
];

const tasks = [
  ['Generate Report', 'Hermes', 'Running'],
  ['Data Analysis', 'Codex', 'Completed'],
  ['Create Presentation', 'Gemini', 'Completed'],
  ['Code Refactor', 'Claude', 'Failed'],
  ['Document Summary', 'Qwen', 'Completed'],
];

function App() {
  const [selectedTab, setSelectedTab] = useState('workspace');
  const [tabs, setTabs] = useState(initialTabs);
  const [services, setServices] = useState<Service[] | null>(null);
  const [terminalExpanded, setTerminalExpanded] = useState(false);
  const [terminalCollapsed, setTerminalCollapsed] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  useEffect(() => {
    fetch('http://127.0.0.1:8788/services')
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => {
        if (!Array.isArray(data)) return;
        setServices(
          data.map((item) => ({
            name: item.name ?? item.unit,
            state: item.state === 'active' ? 'Running' : item.state === 'inactive' ? 'Stopped' : 'Degraded',
          })),
        );
      })
      .catch(() => setServices(null));
  }, []);

  const currentServices = services ?? mockServices;
  const selected = tabs.find((tab) => tab.id === selectedTab);

  const summary = useMemo(() => {
    const runningServices = currentServices.filter((service) => service.state === 'Running').length;
    const runningAgents = agents.filter((agent) => agent.state === 'Running').length;
    const runningTasks = tasks.filter((task) => task[2] === 'Running').length;
    return { runningServices, runningAgents, runningTasks };
  }, [currentServices]);

  const openTab = (item: NavItem | Tab) => {
    setTabs((existingTabs) => {
      if (existingTabs.some((tab) => tab.id === item.id)) return existingTabs;
      return [...existingTabs, { ...item, closable: true }];
    });
    setSelectedTab(item.id);
  };

  const closeTab = (tabId: string) => {
    setTabs((existingTabs) => {
      const nextTabs = existingTabs.filter((tab) => tab.id !== tabId);
      if (tabId === selectedTab) setSelectedTab(nextTabs.at(-1)?.id ?? 'workspace');
      return nextTabs;
    });
  };

  const addCustomTab = () => {
    const nextTab = customWorkspaceTabs.find((tab) => !tabs.some((open) => open.id === tab.id)) ?? customWorkspaceTabs[0];
    openTab(nextTab);
  };

  return (
    <div className={sidebarCollapsed ? 'app-shell sidebar-collapsed' : 'app-shell'}>
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-x">X</span>
          <strong>XWorkspace</strong>
        </div>

        <nav className="side-nav" aria-label="XWorkspace navigation">
          {navGroups.map((group, groupIndex) => (
            <div className="nav-group" key={`group-${groupIndex}`}>
              {group.map((item) => (
                <a
                  key={item.id}
                  href={item.href}
                  className={selectedTab === item.id ? 'active' : ''}
                  onClick={(event) => {
                    event.preventDefault();
                    openTab(item);
                  }}
                >
                  <Icon name={item.icon} />
                  <span>{item.label}</span>
                </a>
              ))}
            </div>
          ))}
        </nav>

        <button className="collapse-button" type="button" onClick={() => setSidebarCollapsed((value) => !value)}>
          <Icon name={sidebarCollapsed ? 'menu' : 'arrow-left'} />
          <span>Collapse</span>
        </button>
      </aside>

      <main className="workspace">
        <header className="topbar">
          <button className="menu-button" type="button" aria-label="Toggle sidebar" onClick={() => setSidebarCollapsed((value) => !value)}>
            <Icon name="menu" />
          </button>
          <div className="status-strip">
            <StatusItem label="Asia/Shanghai" icon="globe" />
            <StatusItem label="Connected" icon="wifi" good />
            <StatusItem label={`${summary.runningAgents} Agents Running`} icon="bot" good />
            <StatusItem label="Vault Ready" icon="shield" good />
            <strong>10:30</strong>
            <button className="round-button" type="button" aria-label="Notifications">
              <Icon name="bell" />
            </button>
            <button className="round-button" type="button" aria-label="Profile">
              <Icon name="user" />
            </button>
          </div>
        </header>

        <section className="workspace-tabs" aria-label="Workspace tabs">
          {tabs.map((tab) => (
            <button
              className={selectedTab === tab.id ? 'tab active' : 'tab'}
              key={tab.id}
              type="button"
              onClick={() => setSelectedTab(tab.id)}
            >
              {tab.icon ? <Icon name={tab.icon} /> : null}
              <span>{tab.label}</span>
              {tab.closable ? (
                <span
                  className="tab-close"
                  role="button"
                  tabIndex={0}
                  onClick={(event) => {
                    event.stopPropagation();
                    closeTab(tab.id);
                  }}
                >
                  ×
                </span>
              ) : null}
            </button>
          ))}
          <button
            className="tab add"
            type="button"
            onClick={addCustomTab}
          >
            +
          </button>
        </section>

        {selected?.kind === 'embed' && selected.id !== 'workspace' ? (
          <EmbedWorkspace tab={selected} />
        ) : (
          <WorkspaceHome services={currentServices} summary={summary} onOpenHome={() => setSelectedTab('workspace')} />
        )}

        <TerminalDrawer
          collapsed={terminalCollapsed}
          expanded={terminalExpanded}
          onCollapse={() => setTerminalCollapsed((value) => !value)}
          onToggle={() => setTerminalExpanded((value) => !value)}
        />
      </main>
    </div>
  );
}

function WorkspaceHome({
  services,
  summary,
  onOpenHome,
}: {
  services: Service[];
  summary: { runningServices: number; runningAgents: number; runningTasks: number };
  onOpenHome: () => void;
}) {
  return (
    <div className="workspace-body">
      <section className="console-board">
        <div className="command-panel">
          <div className="board-heading">
            <div>
              <h1>AI Workspace Control Plane</h1>
              <p>Runtime, gateway and local AI services are organized in one workspace.</p>
            </div>
            <span className="healthy-chip"><span /> Workspace Ready</span>
          </div>

          <div className="activity-card">
            <div className="activity-head">
              <h2>Service Activity</h2>
              <div className="range-tabs" aria-label="Service activity range">
                {['Today', '7d', '2w', '1m'].map((range, index) => <span className={index === 1 ? 'active' : ''} key={range}>{range}</span>)}
              </div>
            </div>
            <div className="service-chart" aria-hidden="true">
              <svg viewBox="0 0 640 220">
                <path className="grid-line" d="M24 40H620M24 92H620M24 144H620M24 196H620" />
                <path className="chart-muted" d="M30 150C80 116 98 184 150 130S230 54 286 112 357 168 410 118 492 88 534 122 584 168 618 110" />
                <path className="chart-main" d="M30 166C82 124 114 176 156 126S224 62 280 104 346 154 402 102 494 52 540 88 582 128 618 64" />
                <circle cx="280" cy="104" r="7" />
              </svg>
            </div>
          </div>

          <a className="service-cards homepage-link" href="#workspace" onClick={(event) => {
            event.preventDefault();
            onOpenHome();
          }}>
            {services.slice(0, 4).map((service, index) => (
              <article className={index === 1 ? 'service-card tilted' : 'service-card'} key={service.name}>
                <Icon name={service.name.toLowerCase().includes('vault') ? 'shield' : service.name.toLowerCase().includes('lite') ? 'chart' : service.name.toLowerCase().includes('bridge') ? 'bridge' : 'claw'} />
                <span>{service.name}</span>
                <strong>{service.state}</strong>
              </article>
            ))}
          </a>
          <section className="service-summary panel">
            <div className="panel-head">
              <h2>Core Services</h2>
            </div>
            <div className="service-list compact">
              {services.map((service) => (
                <div className="service-row" key={service.name}>
                  <span className={service.state === 'Running' ? 'service-dot good' : 'service-dot warn'} />
                  <strong>{service.name}</strong>
                  <span>{service.state}</span>
                </div>
              ))}
            </div>
          </section>
        </div>
      </section>

    </div>
  );
}

function EmbedWorkspace({ tab }: { tab: Tab }) {
  return (
    <div className="workspace-body">
      <section className="embed-panel">
        <div className="panel-head">
          <div>
            <h2>{tab.label}</h2>
            <p>{tab.href}</p>
          </div>
          <a href={tab.href} target="_blank" rel="noreferrer">Open in browser</a>
        </div>
        <iframe title={`${tab.label} workspace`} src={tab.href} />
      </section>
    </div>
  );
}

function TerminalDrawer({
  collapsed,
  expanded,
  onCollapse,
  onToggle,
}: {
  collapsed: boolean;
  expanded: boolean;
  onCollapse: () => void;
  onToggle: () => void;
}) {
  return (
    <section className={[expanded ? 'terminal-drawer expanded' : 'terminal-drawer', collapsed ? 'collapsed' : ''].join(' ')}>
      <div className="terminal-head">
        <div>
          <Icon name="terminal" />
          <strong>Terminal</strong>
        </div>
        <div className="terminal-actions">
          <a href="http://127.0.0.1:7681" target="_blank" rel="noreferrer">New Tab</a>
          <button type="button" onClick={onCollapse}>{collapsed ? 'Expand' : 'Collapse'}</button>
          <button type="button" onClick={onToggle}>{expanded ? 'Restore' : 'Maximize'}</button>
          <button type="button" aria-label="Terminal menu">⋮</button>
        </div>
      </div>
      <div className="terminal-frame">
        <iframe title="ttyd terminal" src="http://127.0.0.1:7681" />
        <pre aria-hidden="true">
          <span>ubuntu@workspace:~$</span> openclaw status{'\n'}
          Gateway Running{'\n'}
          Bridge Running{'\n'}
          LiteLLM Running{'\n'}
          Vault Running{'\n'}
          XWorkmate Bridge Running{'\n\n'}
          <span>ubuntu@workspace:~$</span> _
        </pre>
      </div>
    </section>
  );
}

function Panel({ title, action, children }: React.PropsWithChildren<{ title: string; action?: string }>) {
  return (
    <article className="panel">
      <div className="panel-head">
        <h2>{title}</h2>
        {action ? <button type="button">{action}</button> : null}
      </div>
      {children}
    </article>
  );
}

function StatusItem({ label, icon, good }: { label: string; icon: string; good?: boolean }) {
  return (
    <span className="status-item">
      <Icon name={icon} />
      {good ? <i /> : null}
      {label}
    </span>
  );
}

function StatusBadge({ state }: { state: string }) {
  const normalized = state.toLowerCase();
  const variant = normalized.includes('fail') || normalized.includes('stop') ? 'bad' : normalized.includes('idle') ? 'idle' : 'good';
  return <span className={`badge ${variant}`}>{state}</span>;
}

function Icon({ name }: { name: string }) {
  const paths: Record<string, React.ReactNode> = {
    home: <path d="M3 10.5 12 3l9 7.5v9a1.5 1.5 0 0 1-1.5 1.5H15v-6H9v6H4.5A1.5 1.5 0 0 1 3 19.5z" />,
    bot: <path d="M8 9h8a4 4 0 0 1 4 4v4.5A2.5 2.5 0 0 1 17.5 20h-11A2.5 2.5 0 0 1 4 17.5V13a4 4 0 0 1 4-4Zm1 4h.01M15 13h.01M9 17h6M12 5v4M9 5h6" />,
    tasks: <path d="M8 6h11M8 12h11M8 18h11M4.5 6l1 1 1.8-2M4.5 12l1 1 1.8-2M4.5 18l1 1 1.8-2" />,
    folder: <path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H10l2 2h6.5A2.5 2.5 0 0 1 21 9.5v7A2.5 2.5 0 0 1 18.5 19h-13A2.5 2.5 0 0 1 3 16.5z" />,
    claw: <path d="M12 3v5M7 5l2.5 4M17 5l-2.5 4M5 13a7 7 0 0 0 14 0M8 13a4 4 0 0 0 8 0" />,
    bridge: <path d="M4 17h16M6 17V9l6-4 6 4v8M8 17v-5h8v5" />,
    chart: <path d="M4 19V5M4 19h16M7 15l3-4 4 2 4-7" />,
    shield: <path d="M12 3 20 6v5c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6z" />,
    cube: <path d="m12 3 8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9" />,
    terminal: <path d="m5 8 4 4-4 4M11 17h8" />,
    settings: <path d="M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Zm0-5v3M12 18v3M4.2 5.6l2.1 2.1M17.7 16.3l2.1 2.1M3 12h3M18 12h3M4.2 18.4l2.1-2.1M17.7 7.7l2.1-2.1" />,
    menu: <path d="M5 7h14M5 12h14M5 17h14" />,
    globe: <path d="M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm-8 9h16M12 3c2.2 2.4 3.3 5.4 3.3 9S14.2 18.6 12 21M12 3C9.8 5.4 8.7 8.4 8.7 12S9.8 18.6 12 21" />,
    wifi: <path d="M4 9a12 12 0 0 1 16 0M7 12a7.5 7.5 0 0 1 10 0M10 15a3 3 0 0 1 4 0M12 19h.01" />,
    bell: <path d="M18 16H6l1.4-2V10a4.6 4.6 0 0 1 9.2 0v4zM10 19h4" />,
    user: <path d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM4 21a8 8 0 0 1 16 0" />,
    'arrow-left': <path d="M19 12H5M12 5l-7 7 7 7" />,
  };

  return (
    <svg className="icon" viewBox="0 0 24 24" aria-hidden="true">
      <g fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8">
        {paths[name] ?? paths.cube}
      </g>
    </svg>
  );
}

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
