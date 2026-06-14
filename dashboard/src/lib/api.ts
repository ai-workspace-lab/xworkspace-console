import type { DashboardStatus, PortalService, Service } from './data';

const BASE = 'http://127.0.0.1:8788';

export type ApiResult<T> = {
  data: T | null;
  unauthorized: boolean;
};

const authHeaders = (token?: string): HeadersInit => {
  const trimmed = token?.trim();
  return trimmed ? { Authorization: `Bearer ${trimmed}`, 'X-Bridge-Token': trimmed } : {};
};

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

export async function fetchAuthStatus(): Promise<{ required: boolean } | null> {
  try {
    const response = await fetch(`${BASE}/auth/status`, { cache: 'no-store' });
    if (!response.ok) return null;
    const data = await response.json();
    return { required: Boolean(data.required) };
  } catch {
    return null;
  }
}

export async function fetchDashboardStatus(token?: string): Promise<ApiResult<DashboardStatus>> {
  try {
    const response = await fetch(`${BASE}/health`, { cache: 'no-store', headers: authHeaders(token) });
    if (response.status === 401) return { data: null, unauthorized: true };
    if (!response.ok) return { data: null, unauthorized: false };
    const data = await response.json();
    if (!Array.isArray(data.services)) return { data: null, unauthorized: false };
    return {
      data: {
        services: data.services.map(mapService),
        metrics: {
          activeSessions: Number(data.metrics?.activeSessions ?? 0),
          connectedAgents: Number(data.metrics?.connectedAgents ?? 0),
          activeModels: Number(data.metrics?.activeModels ?? 0),
          skillsAvailable: Number(data.metrics?.skillsAvailable ?? 0),
          workers: Number(data.metrics?.workers ?? 0),
        },
      },
      unauthorized: false,
    };
  } catch {
    return { data: null, unauthorized: false };
  }
}

export async function fetchServices(token?: string): Promise<ApiResult<Service[]>> {
  try {
    const response = await fetch(`${BASE}/services`, { cache: 'no-store', headers: authHeaders(token) });
    if (response.status === 401) return { data: null, unauthorized: true };
    if (!response.ok) return { data: null, unauthorized: false };
    const data = await response.json();
    if (!Array.isArray(data)) return { data: null, unauthorized: false };
    return { data: data.map(mapService), unauthorized: false };
  } catch {
    return { data: null, unauthorized: false };
  }
}

export async function fetchPortalServices(token?: string): Promise<ApiResult<PortalService[]>> {
  try {
    const response = await fetch(`${BASE}/portal/services`, { cache: 'no-store', headers: authHeaders(token) });
    if (response.status === 401) return { data: null, unauthorized: true };
    if (!response.ok) return { data: null, unauthorized: false };
    const data = await response.json();
    const services = Array.isArray(data.services) ? data.services : Array.isArray(data) ? data : null;
    if (!services) return { data: null, unauthorized: false };
    return {
      data: services
        .filter((service: Partial<PortalService>) => service.key && service.name && service.url)
        .map((service: PortalService) => ({
          ...service,
          openMode: service.openMode === 'external' ? 'external' : 'iframe',
        })),
      unauthorized: false,
    };
  } catch {
    return { data: null, unauthorized: false };
  }
}

export async function validateBridgeToken(token: string): Promise<ApiResult<PortalService[]>> {
  return fetchPortalServices(token);
}
