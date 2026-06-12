export type Tab = {
  id: string;
  label: string;
  href: string;
  kind: 'internal' | 'external' | 'embed';
  icon?: string;
  closable?: boolean;
  source?: 'builtin' | 'custom';
  frameMode?: 'iframe' | 'external';
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
};

export type ServiceDef = NavItem & {
  group: number;
  port?: number;
  match?: string[];
  frameMode?: Tab['frameMode'];
};

export const serviceRegistry: ServiceDef[] = [
  { id: 'workspace', label: 'Overview', icon: 'home', href: '#workspace', kind: 'internal', group: 0 },
  { id: 'openclaw', label: 'OpenClaw', icon: 'claw', href: 'http://127.0.0.1:18789/channels', kind: 'embed', group: 1, port: 18789, match: ['openclaw', 'gateway'], frameMode: 'external' },
  { id: 'vault', label: 'Vault Server', icon: 'shield', href: 'http://127.0.0.1:8200/ui/', kind: 'embed', group: 1, port: 8200, match: ['vault'], frameMode: 'external' },
  { id: 'litellm', label: 'LiteLLM Admin UI', icon: 'chart', href: 'http://localhost:4000/ui', kind: 'embed', group: 1, port: 4000, match: ['litellm', 'lite'] },
  { id: 'bridge', label: 'Bridge', icon: 'bridge', href: '#bridge', kind: 'internal', group: 2, match: ['bridge'] },
  { id: 'runtime', label: 'Runtime', icon: 'cube', href: '#runtime', kind: 'internal', group: 2 },
  { id: 'terminal', label: 'Terminal', icon: 'terminal', href: 'http://127.0.0.1:7681', kind: 'embed', group: 2, port: 7681 },
];

export const navSections: { id: string; titleKey: string; items: ServiceDef[] }[] = [
  {
    id: 'overview',
    titleKey: '',
    items: [
      serviceRegistry.find((item) => item.id === 'workspace')!,
      { id: 'architecture', label: 'Architecture', icon: 'network', href: '#architecture', kind: 'internal', group: 0 },
    ],
  },
  {
    id: 'services',
    titleKey: 'navServices',
    items: [
      ...serviceRegistry.filter((item) => item.group === 1),
      serviceRegistry.find((item) => item.id === 'terminal')!,
    ],
  },
];

export const findServiceDef = (serviceName: string): ServiceDef | undefined => {
  const name = serviceName.toLowerCase();
  return serviceRegistry.find((def) => def.match?.some((token) => name.includes(token)));
};

export const customWorkspaceTabs: Tab[] = [
  { id: 'runtime-console', label: 'Runtime', href: '#runtime-console', kind: 'internal', icon: 'cube', closable: true, source: 'custom' },
  { id: 'bridge-console', label: 'Bridge', href: '#bridge-console', kind: 'internal', icon: 'bridge', closable: true, source: 'custom' },
];

export const initialTabs: Tab[] = [
  { id: 'workspace', label: 'Workspace', href: '#workspace', kind: 'internal', icon: 'home', source: 'builtin' },
];

export const mockServices: Service[] = [
  { name: 'OpenClaw Gateway', state: 'Running' },
  { name: 'Bridge', state: 'Running' },
  { name: 'LiteLLM', state: 'Running' },
  { name: 'Vault', state: 'Running' },
  { name: 'XWorkmate Bridge', state: 'Running' },
];

export const fallbackMetrics: RuntimeMetrics = {
  activeSessions: 0,
  connectedAgents: 0,
  activeModels: 0,
  skillsAvailable: 0,
  workers: 0,
};

export const agents = [
  { name: 'Codex Agent', state: 'Idle', workspace: 'xworkspace-console', task: 'Homepage redesign' },
  { name: 'Hermes Agent', state: 'Running', workspace: 'messaging', task: 'Gateway sync' },
  { name: 'Gemini Agent', state: 'Idle', workspace: 'research', task: 'Waiting for input' },
  { name: 'Claude Agent', state: 'Running', workspace: 'docs', task: 'Design review' },
  { name: 'Qwen Agent', state: 'Idle', workspace: 'runtime', task: 'No active task' },
];

export const tasks = [
  ['Generate Report', 'Hermes', 'Running'],
  ['Data Analysis', 'Codex', 'Completed'],
  ['Create Presentation', 'Gemini', 'Completed'],
  ['Code Refactor', 'Claude', 'Failed'],
  ['Document Summary', 'Qwen', 'Completed'],
];

export const skillGroups = [
  { name: 'Content', skills: ['AI News Video', 'Product Video', 'IT Evolution Video'] },
  { name: 'Document', skills: ['PDF', 'DOCX', 'XLSX', 'PPTX'] },
  { name: 'Image', skills: ['Image Cog', 'Resize', 'WAN Image'] },
  { name: 'Workflow', skills: ['Content Writer', 'CN Matrix', 'Automation'] },
];

export const acpAgents = ['Claude', 'Gemini', 'Codex', 'Hermes', 'Qwen', 'OpenCode'];
export const modelTargets = 'GPT-5.5 · DeepSeek V4 · Gemini 3.1 · GLM 5 · Kimi · Claude';

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
