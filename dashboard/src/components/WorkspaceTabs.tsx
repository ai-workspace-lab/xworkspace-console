'use client';

import type { Tab } from '@/lib/data';
import { Icon } from './Icon';

export function WorkspaceTabs({
  tabs,
  selectedTab,
  onSelect,
  onClose,
  onAdd,
}: {
  tabs: Tab[];
  selectedTab: string;
  onSelect: (id: string) => void;
  onClose: (id: string) => void;
  onAdd: () => void;
}) {
  return (
    <section className="workspace-tabs" aria-label="Workspace tabs">
      {tabs.map((tab) => (
        <button
          className={selectedTab === tab.id ? 'tab active' : 'tab'}
          key={tab.id}
          type="button"
          onClick={() => onSelect(tab.id)}
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
                onClose(tab.id);
              }}
            >
              ×
            </span>
          ) : null}
        </button>
      ))}
      <button className="tab add" type="button" onClick={onAdd}>
        +
      </button>
    </section>
  );
}
