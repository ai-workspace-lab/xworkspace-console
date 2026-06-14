'use client';

import { useEffect, useMemo, useState } from 'react';
import {
  buildInitialTabs,
  buildNavSections,
  customWorkspaceTabs,
  fallbackMetrics,
  findPortalService,
  initialTabs,
  labelsEn,
  labelsZh,
  portalServices,
  portalServiceToTab,
} from '@/lib/data';
import type { NavItem, PortalService, RuntimeMetrics, Service, Tab } from '@/lib/data';
import { fetchAuthStatus, fetchDashboardStatus, fetchPortalServices, validateBridgeToken } from '@/lib/api';
import { Sidebar } from './Sidebar';
import { Topbar } from './Topbar';
import { WorkspaceTabs } from './WorkspaceTabs';
import { WorkspaceHome } from './WorkspaceHome';
import { ServicePanel } from './ServicePanel';

export function AppShell() {
  const [selectedTab, setSelectedTab] = useState('workspace');
  const [tabs, setTabs] = useState<Tab[]>(initialTabs);
  const [services, setServices] = useState<Service[] | null>(null);
  const [metrics, setMetrics] = useState<RuntimeMetrics>(fallbackMetrics);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [language, setLanguage] = useState<'en' | 'zh'>('en');
  const [theme, setTheme] = useState<'light' | 'dark'>('light');
  const [remoteMode, setRemoteMode] = useState(true);
  const [portalServicesConfig, setPortalServicesConfig] = useState<PortalService[]>(portalServices);
  const [authRequired, setAuthRequired] = useState(false);
  const [authStatusLoaded, setAuthStatusLoaded] = useState(false);
  const [authToken, setAuthToken] = useState('');
  const [tokenInput, setTokenInput] = useState('');
  const [tokenLoaded, setTokenLoaded] = useState(false);
  const [authError, setAuthError] = useState(false);
  const [authChecking, setAuthChecking] = useState(false);

  useEffect(() => {
    let active = true;
    const refresh = () => {
      if (!tokenLoaded || !authStatusLoaded || (authRequired && !authToken)) return;
      Promise.all([fetchDashboardStatus(authToken), fetchPortalServices(authToken)]).then(([statusResult, portalResult]) => {
        if (!active) return;
        if (statusResult.unauthorized || portalResult.unauthorized) {
          setAuthRequired(true);
          setAuthError(true);
          return;
        }
        if (statusResult.data) {
          setServices(statusResult.data.services);
          setMetrics(statusResult.data.metrics);
        }
        if (portalResult.data?.length) {
          setPortalServicesConfig(portalResult.data);
        }
      });
    };
    refresh();
    const timer = window.setInterval(refresh, 15_000);
    return () => {
      active = false;
      window.clearInterval(timer);
    };
  }, [authRequired, authStatusLoaded, authToken, tokenLoaded]);

  useEffect(() => {
    setTabs((existingTabs) => {
      const workspaceTab = existingTabs.find((tab) => tab.id === 'workspace') ?? buildInitialTabs([])[0];
      const customTabs = existingTabs.filter((tab) => tab.id !== 'workspace' && !tab.serviceKey);
      return [workspaceTab, ...portalServicesConfig.map(portalServiceToTab), ...customTabs];
    });
    const activeServiceKey = selectedTab.startsWith('service-') ? selectedTab.replace(/^service-/, '') : undefined;
    if (activeServiceKey && !findPortalService(activeServiceKey, portalServicesConfig)) {
      setSelectedTab('workspace');
    }
  }, [portalServicesConfig]);

  useEffect(() => {
    const storedToken = window.localStorage.getItem('xworkspace-bridge-token') ?? '';
    setAuthToken(storedToken);
    setTokenInput(storedToken);
    setTokenLoaded(true);
    fetchAuthStatus().then((status) => {
      if (status?.required) setAuthRequired(true);
      setAuthStatusLoaded(true);
    });
  }, []);

  useEffect(() => {
    const stored = window.localStorage.getItem('xws-remote-mode');
    if (stored !== null) {
      setRemoteMode(stored === '1');
    } else if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setRemoteMode(true);
    }
  }, []);

  const toggleRemoteMode = () => {
    setRemoteMode((value) => {
      window.localStorage.setItem('xws-remote-mode', value ? '0' : '1');
      return !value;
    });
  };

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (!(event.metaKey || event.ctrlKey)) return;
      if (event.key >= '1' && event.key <= '9') {
        const index = Number(event.key) - 1;
        setTabs((existingTabs) => {
          if (existingTabs[index]) setSelectedTab(existingTabs[index].id);
          return existingTabs;
        });
        event.preventDefault();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const currentServices = services ?? [];
  const selected = tabs.find((tab) => tab.id === selectedTab);
  const selectedService = findPortalService(selected?.serviceKey, portalServicesConfig);
  const labels = language === 'zh' ? labelsZh : labelsEn;
  const dynamicNavSections = useMemo(() => buildNavSections(portalServicesConfig), [portalServicesConfig]);

  const summary = useMemo(() => {
    const runningServices = currentServices.filter((service) => service.state === 'Running').length;
    return { runningServices, runningAgents: metrics.connectedAgents, runningTasks: metrics.workers };
  }, [currentServices, metrics]);

  const openTab = (item: NavItem | Tab) => {
    const service = findPortalService(item.serviceKey, portalServicesConfig);
    const nextItem = service ? portalServiceToTab(service) : item;
    setTabs((existingTabs) => {
      if (existingTabs.some((tab) => tab.id === nextItem.id)) {
        return existingTabs.map((tab) => (tab.id === nextItem.id ? { ...tab, ...nextItem, closable: tab.closable ?? true } : tab));
      }
      return [...existingTabs, { ...nextItem, closable: true }];
    });
    setSelectedTab(nextItem.id);
  };

  const closeTab = (tabId: string) => {
    setTabs((existingTabs) => {
      const nextTabs = existingTabs.filter((tab) => tab.id !== tabId);
      if (tabId === selectedTab) setSelectedTab(nextTabs[nextTabs.length - 1]?.id ?? 'workspace');
      return nextTabs;
    });
  };

  const addCustomTab = () => {
    const nextTab = customWorkspaceTabs.find((tab) => !tabs.some((open) => open.id === tab.id)) ?? customWorkspaceTabs[0];
    openTab(nextTab);
  };

  const submitToken = async () => {
    const nextToken = tokenInput.trim();
    if (!nextToken) return;
    setAuthChecking(true);
    setAuthError(false);

    const portalResult = await validateBridgeToken(nextToken);
    setAuthChecking(false);

    if (portalResult.unauthorized || !portalResult.data?.length) {
      setAuthError(true);
      return;
    }

    window.localStorage.setItem('xworkspace-bridge-token', nextToken);
    setPortalServicesConfig(portalResult.data);
    setAuthToken(nextToken);
    setTabs(buildInitialTabs(portalResult.data));
  };

  if (tokenLoaded && authStatusLoaded && authRequired && (!authToken || authError)) {
    return <AuthGate token={tokenInput} error={authError} checking={authChecking} onTokenChange={setTokenInput} onSubmit={submitToken} />;
  }

  return (
    <div className={[sidebarCollapsed ? 'app-shell sidebar-collapsed' : 'app-shell', theme === 'dark' ? 'theme-dark' : '', remoteMode ? 'remote-mode' : ''].join(' ')}>
      <Sidebar
        labels={labels}
        navSections={dynamicNavSections}
        collapsed={sidebarCollapsed}
        selectedTab={selectedTab}
        onToggle={() => setSidebarCollapsed((value) => !value)}
        onOpen={openTab}
        onToggleLanguage={() => setLanguage((value) => (value === 'en' ? 'zh' : 'en'))}
        onToggleTheme={() => setTheme((value) => (value === 'light' ? 'dark' : 'light'))}
        theme={theme}
        remoteMode={remoteMode}
        onToggleRemoteMode={toggleRemoteMode}
      />

      <main className="workspace">
        <Topbar
          labels={labels}
          selectedLabel={selected && selected.id !== 'workspace' ? selected.label : null}
          services={currentServices}
          summary={summary}
          metrics={metrics}
          onToggleSidebar={() => setSidebarCollapsed((value) => !value)}
        />

        <WorkspaceTabs tabs={tabs} selectedTab={selectedTab} onSelect={setSelectedTab} onClose={closeTab} onAdd={addCustomTab} />

        {selected?.kind === 'embed' && selectedService ? (
          <ServicePanel service={selectedService} onBack={() => setSelectedTab('workspace')} />
        ) : (
          <WorkspaceHome labels={labels} services={currentServices} metrics={metrics} portalServices={portalServicesConfig} onOpenService={openTab} />
        )}
      </main>
    </div>
  );
}

function AuthGate({
  token,
  error,
  checking,
  onTokenChange,
  onSubmit,
}: {
  token: string;
  error: boolean;
  checking: boolean;
  onTokenChange: (value: string) => void;
  onSubmit: () => void | Promise<void>;
}) {
  return (
    <main className="auth-gate">
      <form
        className="auth-card"
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit();
        }}
      >
        <span className="brand-mark">AI</span>
        <h1>AI Workspace Portal</h1>
        <p>Enter the xworkmate-bridge token to load local services.</p>
        <input
          autoFocus
          type="password"
          value={token}
          onChange={(event) => onTokenChange(event.target.value)}
          placeholder="Bridge token"
          aria-label="Bridge token"
          disabled={checking}
        />
        {error ? <small>Token rejected by the local API.</small> : null}
        <button type="submit" disabled={checking}>{checking ? 'Unlocking...' : 'Unlock'}</button>
      </form>
    </main>
  );
}
