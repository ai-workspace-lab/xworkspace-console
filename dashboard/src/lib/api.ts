import type { Service } from './data';

const BASE = 'http://127.0.0.1:8788';

export async function fetchServices(): Promise<Service[] | null> {
  try {
    const response = await fetch(`${BASE}/services`, { cache: 'no-store' });
    if (!response.ok) return null;
    const data = await response.json();
    if (!Array.isArray(data)) return null;
    return data.map((item: { name?: string; unit?: string; state?: string }) => ({
      name: item.name ?? item.unit ?? 'unknown',
      state: item.state === 'active' ? 'Running' : item.state === 'inactive' ? 'Stopped' : 'Degraded',
    }));
  } catch {
    return null;
  }
}
