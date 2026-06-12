'use client';

import { useEffect, useMemo, useState } from 'react';
import { customWorkspaceTabs, fallbackMetrics, initialTabs, labelsEn, labelsZh, mockServices } from '@/lib/data';
import type { NavItem, RuntimeMetrics, Service, Tab } from '@/lib/data';
import { fetchDashboardStatus } from '@/lib/api';
import { Sidebar } from './Sidebar';
import { Topbar } from './Topbar';
import { WorkspaceTabs } from './WorkspaceTabs';
import { WorkspaceHome } from './WorkspaceHome';
import { EmbedView } from './EmbedView';

export function AppShell() {
  const [selectedTab, setSelectedTab] = useState('workspace');
  const [tabs, setTabs] = useState<Tab[]>(initialTabs);
  const [services, setServices] = useState<Service[] | null>(null);
  const [metrics, setMetrics] = useState<RuntimeMetrics>(fallbackMetrics);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [language, setLanguage] = useState<'en' | 'zh'>('en');
  const [theme, setTheme] = useState<'light' | 'dark'>('light');
  const [remoteMode, setRemoteMode] = useState(true);

  useEffect(() => {
    let active = true;
    const refresh = () => {
      fetchDashboardStatus().then((data) => {
        if (!active || !data) return;
        setServices(data.services);
        setMetrics(data.metrics);
      });
    };
    refresh();
    const timer = window.setInterval(refresh, 15_000);
    return () => {
      active = false;
      window.clearInterval(timer);
    };
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

  const currentServices = services ?? mockServices;
  const selected = tabs.find((tab) => tab.id === selectedTab);
  const labels = language === 'zh' ? labelsZh : labelsEn;

  const summary = useMemo(() => {
    const runningServices = currentServices.filter((service) => service.state === 'Running').length;
    return { runningServices, runningAgents: metrics.connectedAgents, runningTasks: metrics.workers };
  }, [currentServices, metrics]);

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
      if (tabId === selectedTab) setSelectedTab(nextTabs[nextTabs.length - 1]?.id ?? 'workspace');
      return nextTabs;
    });
  };

  const addCustomTab = () => {
    const nextTab = customWorkspaceTabs.find((tab) => !tabs.some((open) => open.id === tab.id)) ?? customWorkspaceTabs[0];
    openTab(nextTab);
  };

  return (
    <div className={[sidebarCollapsed ? 'app-shell sidebar-collapsed' : 'app-shell', theme === 'dark' ? 'theme-dark' : '', remoteMode ? 'remote-mode' : ''].join(' ')}>
      <Sidebar
        labels={labels}
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

        {selected?.kind === 'embed' && selected.id !== 'workspace' ? (
          <EmbedView tab={selected} onBack={() => setSelectedTab('workspace')} />
        ) : (
          <WorkspaceHome labels={labels} services={currentServices} metrics={metrics} onOpenService={openTab} />
        )}
      </main>
    </div>
  );
}
