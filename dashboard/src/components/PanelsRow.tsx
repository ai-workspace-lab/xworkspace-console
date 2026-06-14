'use client';

import { useState } from 'react';
import { findPortalServiceForStatus } from '@/lib/data';
import type { Labels, RuntimeMetrics, Service } from '@/lib/data';
import { Icon } from './Icon';

export function PanelsRow({ labels, services, metrics }: { labels: Labels; services: Service[]; metrics: RuntimeMetrics }) {
  const [range, setRange] = useState('7d');

  return (
    <div className="panels-row">
      <section className="home-panel">
        <div className="home-panel-head">
          <h2>{labels.serviceHealth}</h2>
          <span>{services.length}</span>
        </div>
        <div className="health-row">
          {services.map((service) => {
            const portalService = findPortalServiceForStatus(service.name);
            const running = service.state === 'Running';
            return (
              <div className="health-item" key={service.name} title={service.name}>
                <span className={running ? 'health-icon good' : 'health-icon bad'}>
                  <Icon name={portalService?.icon ?? 'cube'} />
                </span>
                <small>{portalService?.name ?? service.name}</small>
                <em>{running ? labels.healthy : labels.degraded}</em>
              </div>
            );
          })}
        </div>
      </section>

      <section className="home-panel">
        <div className="home-panel-head">
          <h2>{labels.systemOverview}</h2>
        </div>
        <div className="overview-grid">
          <div><strong>{metrics.activeSessions}</strong><small>{labels.activeSessions}</small></div>
          <div><strong>{metrics.connectedAgents}</strong><small>{labels.connectedAgents}</small></div>
          <div><strong>{metrics.activeModels}</strong><small>{labels.activeModels}</small></div>
          <div><strong>{metrics.skillsAvailable}+</strong><small>{labels.skillsAvailable}</small></div>
        </div>
      </section>

      <section className="home-panel">
        <div className="home-panel-head">
          <h2>{labels.activity}</h2>
          <span className="range-tabs" aria-label="Service activity range">
            {[labels.today, '7d', '2w', '1m'].map((item) => (
              <span key={item} className={range === item ? 'active' : ''} onClick={() => setRange(item)}>{item}</span>
            ))}
          </span>
        </div>
        <div className="service-chart mini" aria-hidden="true">
          <svg viewBox="0 0 640 80">
            <path className="grid-line" d="M24 70H620" />
            <path className="chart-main" d="M30 62C82 46 114 66 156 47S224 24 280 40 346 58 402 38 494 19 540 33 582 48 618 24" />
          </svg>
        </div>
      </section>
    </div>
  );
}
