import type { DashboardStatus, Service } from './data';

const BASE = 'http://127.0.0.1:8788';

const normalizeServiceState = (state?: string): Service['state'] => {
  if (state === 'active' || state === 'running' || state === 'Running') return 'Running';
  if (state === 'inactive' || state === 'failed' || state === 'Stopped') return 'Stopped';
  return 'Degraded';
};

const mapService = (item: { name?: string; unit?: string; state?: string; detail?: string; port?: number; url?: string }): Service => ({
  name: item.name ?? item.unit ?? 'unknown',
  unit: item.unit,
  detail: item.detail,
  port: item.port,
  url: item.url,
  state: normalizeServiceState(item.state),
});

export async function fetchDashboardStatus(): Promise<DashboardStatus | null> {
  try {
    const response = await fetch(`${BASE}/health`, { cache: 'no-store' });
    if (!response.ok) return null;
    const data = await response.json();
    if (!Array.isArray(data.services)) return null;
    return {
      services: data.services.map(mapService),
      metrics: {
        activeSessions: Number(data.metrics?.activeSessions ?? 0),
        connectedAgents: Number(data.metrics?.connectedAgents ?? 0),
        activeModels: Number(data.metrics?.activeModels ?? 0),
        skillsAvailable: Number(data.metrics?.skillsAvailable ?? 0),
        workers: Number(data.metrics?.workers ?? 0),
      },
    };
  } catch {
    return null;
  }
}

export async function fetchServices(): Promise<Service[] | null> {
  try {
    const response = await fetch(`${BASE}/services`, { cache: 'no-store' });
    if (!response.ok) return null;
    const data = await response.json();
    if (!Array.isArray(data)) return null;
    return data.map(mapService);
  } catch {
    return null;
  }
}
