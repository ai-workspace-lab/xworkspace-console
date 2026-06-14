export type Tab = {
  id: string;
  label: string;
  href: string;
  kind: 'internal' | 'external' | 'embed';
  icon?: string;
  closable?: boolean;
  source?: 'builtin' | 'custom';
  serviceKey?: string;
};

export type PortalService = {
  key: string;
  name: string;
  url: string;
  openMode: 'iframe' | 'external';
  healthUrl?: string;
  description?: string;
  icon?: string;
  match?: string[];
  port?: number;
  role?: 'gateway' | 'model-router';
};

export type Service = {
  name: string;
  state: 'Running' | 'Degraded' | 'Stopped';
  unit?: string;
  detail?: string;
  port?: number;
  url?: string;
};

export type RuntimeMetrics = {
  activeSessions: number;
  connectedAgents: number;
  activeModels: number;
  skillsAvailable: number;
  workers: number;
};

export type DashboardStatus = {
  services: Service[];
  metrics: RuntimeMetrics;
};

export type NavItem = {
  id: string;
  label: string;
  icon: string;
  href: string;
  kind: Tab['kind'];
  serviceKey?: string;
};

export type NavSectionItem = NavItem & {
  group: number;
  port?: number;
  match?: string[];
};

export type NavSection = { id: string; titleKey: string; items: NavSectionItem[] };

export const portalServices: PortalService[] = [
  {
    key: 'litellm',
    name: 'LiteLLM Admin UI',
    url: 'http://localhost:4000/ui',
    openMode: 'iframe',
    description: 'Model routing and provider administration.',
    icon: 'chart',
    match: ['litellm', 'lite'],
    port: 4000,
    role: 'model-router',
  },
  {
    key: 'openclaw',
    name: 'OpenClaw',
    url: 'http://127.0.0.1:18789/channels',
    openMode: 'external',
    description: 'Gateway dashboard. Opens outside the portal because the service blocks embedded frames.',
    icon: 'claw',
    match: ['openclaw', 'gateway'],
    port: 18789,
    role: 'gateway',
  },
  {
    key: 'vault',
    name: 'Vault Server',
    url: 'http://127.0.0.1:8200/ui',
    openMode: 'external',
    description: 'Vault UI. Opens outside the portal because the service blocks embedded frames.',
    icon: 'shield',
    match: ['vault'],
    port: 8200,
  },
  {
    key: 'terminal',
    name: 'Terminal',
    url: 'http://127.0.0.1:7681',
    openMode: 'iframe',
    healthUrl: 'http://127.0.0.1:7681',
    description: 'Local ttyd terminal.',
    icon: 'terminal',
    match: ['ttyd', 'terminal'],
    port: 7681,
  },
];

export const workspaceNavItems: NavSectionItem[] = [
  { id: 'workspace', label: 'Overview', icon: 'home', href: '#workspace', kind: 'internal', group: 0 },
  { id: 'architecture', label: 'Architecture', icon: 'network', href: '#architecture', kind: 'internal', group: 0 },
];

export const portalServiceToNavItem = (service: PortalService): NavSectionItem => ({
  id: `service-${service.key}`,
  label: service.name,
  icon: service.icon ?? 'cube',
  href: service.url,
  kind: 'embed',
  group: 1,
  port: service.port,
  match: service.match,
  serviceKey: service.key,
});

export const portalServiceToTab = (service: PortalService): Tab => ({
  id: `service-${service.key}`,
  label: service.name,
  href: service.url,
  kind: 'embed',
  icon: service.icon ?? 'cube',
  closable: true,
  source: 'builtin',
  serviceKey: service.key,
});

export const portalNavItems = portalServices.map(portalServiceToNavItem);
export const portalTabs = portalServices.map(portalServiceToTab);

export const buildNavSections = (services: PortalService[] = portalServices): NavSection[] => [
  {
    id: 'overview',
    titleKey: '',
    items: workspaceNavItems,
  },
  {
    id: 'services',
    titleKey: 'navServices',
    items: services.map(portalServiceToNavItem),
  },
];

export const navSections = buildNavSections();

export const findPortalService = (serviceKey?: string, services: PortalService[] = portalServices): PortalService | undefined => {
  if (!serviceKey) return undefined;
  return services.find((service) => service.key === serviceKey);
};

export const findPortalServiceByRole = (role: PortalService['role'], services: PortalService[] = portalServices): PortalService | undefined => {
  if (!role) return undefined;
  return services.find((service) => service.role === role);
};

export const findPortalServiceForStatus = (serviceName: string, services: PortalService[] = portalServices): PortalService | undefined => {
  const name = serviceName.toLowerCase();
  return services.find((service) => {
    const tokens = service.match ?? [service.key, service.name];
    return tokens.some((token) => name.includes(token.toLowerCase()));
  });
};

export const findPortalServiceStatus = (
  services: Service[],
  serviceKey?: string,
  portalServiceConfig: PortalService[] = portalServices,
): Service['state'] | undefined => {
  const serviceConfig = findPortalService(serviceKey, portalServiceConfig);
  if (!serviceConfig) return undefined;
  return services.find((entry) => findPortalServiceForStatus(entry.name, portalServiceConfig)?.key === serviceConfig.key)?.state;
};

export const customWorkspaceTabs: Tab[] = [
  { id: 'runtime-console', label: 'Runtime', href: '#runtime-console', kind: 'internal', icon: 'cube', closable: true, source: 'custom' },
  { id: 'bridge-console', label: 'Bridge', href: '#bridge-console', kind: 'internal', icon: 'bridge', closable: true, source: 'custom' },
];

export const buildInitialTabs = (services: PortalService[] = portalServices): Tab[] => [
  { id: 'workspace', label: 'Workspace', href: '#workspace', kind: 'internal', icon: 'home', source: 'builtin' },
  ...services.map(portalServiceToTab),
];

export const initialTabs = buildInitialTabs();

export const fallbackMetrics: RuntimeMetrics = {
  activeSessions: 0,
  connectedAgents: 0,
  activeModels: 0,
  skillsAvailable: 0,
  workers: 0,
};

export const skillGroups = [
  { name: 'Content', skills: ['AI News Video', 'Product Video', 'IT Evolution Video'] },
  { name: 'Document', skills: ['PDF', 'DOCX', 'XLSX', 'PPTX'] },
  { name: 'Image', skills: ['Image Cog', 'Resize', 'WAN Image'] },
  { name: 'Workflow', skills: ['Content Writer', 'CN Matrix', 'Automation'] },
];

export const acpAgents = ['Claude', 'Gemini', 'Codex', 'Hermes', 'Qwen', 'OpenCode'];

export type Labels = Record<string, string>;

export const labelsZh: Labels = {
  product: 'XWorkspace',
  controlPlane: '控制面',
  workspace: '工作空间',
  collapse: '收起',
  expand: '展开',
  connected: '已连接',
  agentsRunning: '个 Agent 运行中',
  vaultReady: 'Vault 就绪',
  homepageTitle: 'AI Workspace',
  homepageSubtitle: '在一个工作空间里统一组织 Runtime、Gateway 和本地 AI 服务。',
  activity: '服务活动',
  serviceCards: '服务卡片',
  serviceHealth: '服务健康',
  systemOverview: '系统总览',
  workspaceStatus: '工作空间状态',
  today: '今天',
  newTab: '新标签',
  terminal: '终端',
  maximize: '最大化',
  restore: '还原',
  themeLight: '浅色',
  themeDark: '深色',
  lang: '中/EN',
  languageLabel: '语言',
  themeLabel: '主题',
  remoteLabel: '远程模式',
  remoteOn: '开',
  remoteOff: '关',
  gatewayBand: '网关',
  agentBand: 'Agent 控制面',
  skillBand: '技能运行时',
  modelBand: '模型路由',
  memoryCard: '记忆系统',
  acpCard: 'ACP 路由',
  sessions: '会话',
  workers: '工作进程',
  skillsCount: '个技能',
  providers: '家模型供应商',
  navServices: '服务',
  navInfra: '基础设施',
  healthy: '健康',
  degraded: '异常',
  activeSessions: '活跃会话',
  connectedAgents: '已连接 Agent',
  activeModels: '可用模型',
  skillsAvailable: '可用技能',
  secLocal: '100% 本地 · 数据不出服务器',
  secToken: 'Token 认证 · 安全访问控制',
  secLoopback: '无公网暴露 · 仅本地回环',
  secE2e: '端到端加密 · 全服务保护',
};

export const labelsEn: Labels = {
  product: 'XWorkmate',
  controlPlane: 'Control Plane',
  workspace: 'Workspace',
  collapse: 'Collapse',
  expand: 'Expand',
  connected: 'Connected',
  agentsRunning: 'Agents Running',
  vaultReady: 'Vault Ready',
  homepageTitle: 'AI Workspace',
  homepageSubtitle: 'Runtime, gateway and local AI services are organized in one workspace.',
  activity: 'Service Activity',
  serviceCards: 'Service Cards',
  serviceHealth: 'Service Health',
  systemOverview: 'System Overview',
  workspaceStatus: 'Workspace Status',
  today: 'Today',
  newTab: 'New Tab',
  terminal: 'Terminal',
  maximize: 'Maximize',
  restore: 'Restore',
  themeLight: 'Light',
  themeDark: 'Dark',
  lang: 'EN/中',
  languageLabel: 'Language',
  themeLabel: 'Theme',
  remoteLabel: 'Remote Mode',
  remoteOn: 'On',
  remoteOff: 'Off',
  gatewayBand: 'Gateway',
  agentBand: 'Agent Control Plane',
  skillBand: 'Skill Runtime',
  modelBand: 'Model Routing',
  memoryCard: 'Memory System',
  acpCard: 'ACP Router',
  sessions: 'Sessions',
  workers: 'Workers',
  skillsCount: 'skills',
  providers: 'providers',
  navServices: 'Services',
  navInfra: 'Infrastructure',
  healthy: 'Healthy',
  degraded: 'Degraded',
  activeSessions: 'Active Sessions',
  connectedAgents: 'Connected Agents',
  activeModels: 'Active Models',
  skillsAvailable: 'Skills Available',
  secLocal: '100% Local · No data leaves your server',
  secToken: 'Token Auth · Secure access control',
  secLoopback: 'No Public Exposure · Local loopback only',
  secE2e: 'End-to-End Encrypted · All services protected',
};
