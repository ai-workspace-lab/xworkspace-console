'use client';

import { useEffect, useState } from 'react';
import type { Labels, Service } from '@/lib/data';
import { Icon } from './Icon';
import { StatusAggregate } from './StatusAggregate';

export function Topbar({
  labels,
  selectedLabel,
  services,
  summary,
  onToggleSidebar,
}: {
  labels: Labels;
  selectedLabel: string | null;
  services: Service[];
  summary: { runningServices: number; runningAgents: number };
  onToggleSidebar: () => void;
}) {
  const breadcrumbItems = [labels.product, labels.workspace, selectedLabel].filter(Boolean) as string[];
  const [time, setTime] = useState('');

  useEffect(() => {
    const updateTime = () => setTime(new Intl.DateTimeFormat('en-US', { hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date()));
    updateTime();
    const timer = window.setInterval(updateTime, 30_000);
    return () => window.clearInterval(timer);
  }, []);

  return (
    <header className="topbar">
      <div className="topbar-left">
        <button className="menu-button" type="button" aria-label="Toggle sidebar" onClick={onToggleSidebar}>
          <Icon name="menu" />
        </button>
        <nav className="breadcrumb" aria-label="Breadcrumb">
          {breadcrumbItems.map((item, index) => (
            <span key={`${item}-${index}`}>
              {index > 0 ? <span className="breadcrumb-separator">/</span> : null}
              <span className={index === breadcrumbItems.length - 1 ? 'breadcrumb-current' : ''}>{item}</span>
            </span>
          ))}
        </nav>
      </div>
      <div className="status-strip">
        <StatusAggregate labels={labels} services={services} summary={summary} />
        <span className="status-pill"><Icon name="user" />333 Sessions</span>
        <span className="status-pill"><Icon name="clock" />{time}</span>
        <button className="round-button" type="button" aria-label="Notifications">
          <Icon name="bell" />
        </button>
        <button className="profile-button" type="button" aria-label="Profile">
          X
        </button>
      </div>
    </header>
  );
}
