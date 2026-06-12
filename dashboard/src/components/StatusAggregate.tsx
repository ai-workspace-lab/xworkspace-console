'use client';

import { useEffect, useRef, useState } from 'react';
import type { Labels, Service } from '@/lib/data';
import { Icon } from './Icon';

export function StatusAggregate({
  labels,
  services,
  summary,
}: {
  labels: Labels;
  services: Service[];
  summary: { runningServices: number; runningAgents: number };
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement | null>(null);
  const total = services.length;
  const allOk = summary.runningServices === total;

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    document.addEventListener('pointerdown', onPointerDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('pointerdown', onPointerDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <div className="status-aggregate" ref={rootRef}>
      <button
        type="button"
        className={allOk ? 'status-pill ok' : 'status-pill warn'}
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        <span className="status-dot" />
        {summary.runningServices}/{total}
        <Icon name={allOk ? 'check' : 'alert'} />
      </button>
      {open ? (
        <div className="status-popover" role="dialog" aria-label="System status">
          <div className="status-popover-row">
            <Icon name="wifi" />
            <span>{labels.connected}</span>
            <i className="dot good" />
          </div>
          <div className="status-popover-row">
            <Icon name="bot" />
            <span>{summary.runningAgents} {labels.agentsRunning}</span>
            <i className="dot good" />
          </div>
          <div className="status-popover-row">
            <Icon name="shield" />
            <span>{labels.vaultReady}</span>
            <i className="dot good" />
          </div>
          <div className="status-popover-divider" />
          {services.map((service) => (
            <div className="status-popover-row" key={service.name}>
              <span className="service-name">{service.name}</span>
              <i className={service.state === 'Running' ? 'dot good' : 'dot bad'} />
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}
