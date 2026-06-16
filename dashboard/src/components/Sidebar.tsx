'use client';

import { useState } from 'react';
import type { Labels, NavItem, NavSection } from '@/lib/data';
import { Icon } from './Icon';

export function Sidebar({
  labels,
  navSections,
  collapsed,
  selectedTab,
  onToggle,
  onOpen,
  onToggleLanguage,
  onToggleTheme,
  onResetAuthClick,
  theme,
  remoteMode,
  onToggleRemoteMode,
}: {
  labels: Labels;
  navSections: NavSection[];
  collapsed: boolean;
  selectedTab: string;
  onToggle: () => void;
  onOpen: (item: NavItem) => void;
  onToggleLanguage: () => void;
  onToggleTheme: () => void;
  onResetAuthClick: () => void;
  theme: 'light' | 'dark';
  remoteMode: boolean;
  onToggleRemoteMode: () => void;
}) {
  const [openSections, setOpenSections] = useState<Record<string, boolean>>({ services: true, infra: true });

  return (
    <aside className="sidebar">
      <div className="brand">
        <span className="brand-mark"><Icon name="bot" /></span>
      </div>

      <nav className="side-nav" aria-label="XWorkspace navigation">
        {navSections.map((section) => (
          <div className="nav-group" key={section.id}>
            {section.titleKey && !collapsed ? (
              <button
                type="button"
                className="nav-section-toggle"
                aria-expanded={openSections[section.id] !== false}
                onClick={() => setOpenSections((value) => ({ ...value, [section.id]: !(value[section.id] !== false) }))}
              >
                <span>{labels[section.titleKey]}</span>
                <Icon name={openSections[section.id] !== false ? 'chevron-down' : 'chevron-right'} />
              </button>
            ) : null}
            {collapsed || openSections[section.id] !== false
              ? section.items.map((item) => (
                  <a
                    key={item.id}
                    href={item.href}
                    className={selectedTab === item.id ? 'active' : ''}
                    title={collapsed ? item.label : undefined}
                    onClick={(event) => {
                      event.preventDefault();
                      onOpen(item);
                    }}
                  >
                    <Icon name={item.icon} />
                    <span>{item.label}</span>
                  </a>
                ))
              : null}
          </div>
        ))}
      </nav>

      <div className="sidebar-tools">
        <button 
          className="sidebar-tool-button" 
          type="button" 
          aria-label="Reset Auth Token" 
          title="Reset Auth Token" 
          onClick={onResetAuthClick}
          style={{ color: '#d32f2f' }}
        >
          <Icon name="power" />
          <strong>{!collapsed ? 'Reset Token' : ''}</strong>
        </button>
        <button className="sidebar-tool-button" type="button" aria-label={collapsed ? labels.expand : labels.collapse} onClick={onToggle}>
          <Icon name={collapsed ? 'panel-expand' : 'panel-collapse'} />
        </button>
        <button className="sidebar-tool-button" type="button" aria-label={labels.languageLabel} title={labels.languageLabel} onClick={onToggleLanguage}>
          <span className="language-mark">{labels.lang}</span>
        </button>
        <button className="sidebar-tool-button" type="button" aria-label={labels.themeLabel} title={labels.themeLabel} onClick={onToggleTheme}>
          <Icon name={theme === 'light' ? 'moon' : 'sun'} />
          <strong>{theme === 'light' ? labels.themeDark : labels.themeLight}</strong>
        </button>
      </div>
    </aside>
  );
}
