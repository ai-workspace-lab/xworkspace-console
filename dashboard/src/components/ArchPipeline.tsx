'use client';

import { useState } from 'react';
import { acpAgents, agents, findServiceDef, serviceRegistry, skillGroups } from '@/lib/data';
import type { Labels, NavItem, Service } from '@/lib/data';
import { Icon } from './Icon';

export function ArchPipeline({
  labels,
  services,
  onOpenService,
}: {
  labels: Labels;
  services: Service[];
  onOpenService: (item: NavItem) => void;
}) {
  const [skillsOpen, setSkillsOpen] = useState(false);

  const stateOf = (id: string): Service['state'] | undefined => {
    const def = serviceRegistry.find((item) => item.id === id);
    const service = services.find((entry) => def?.match?.some((token) => entry.name.toLowerCase().includes(token)));
    return service?.state;
  };
  const dot = (state?: Service['state']) => (
    <i className={state === 'Running' ? 'dot good' : state ? 'dot bad' : 'dot idle'} />
  );
  const runningAgents = agents.filter((agent) => agent.state === 'Running').map((agent) => agent.name.split(' ')[0]);
  const totalSkills = skillGroups.reduce((count, group) => count + group.skills.length, 0);
  const externalModels = [
    { name: 'GPT-5.5', mark: '◎', tone: 'openai' },
    { name: 'DeepSeek V4', mark: 'D', tone: 'deepseek' },
    { name: 'Gemini 3.1', mark: '✦', tone: 'gemini' },
    { name: 'GLM 5', mark: 'Z', tone: 'glm' },
    { name: 'MiniMax', mark: '〽', tone: 'minimax' },
    { name: 'Kimi', mark: 'K', tone: 'kimi' },
    { name: 'Claude', mark: 'AI', tone: 'claude' },
    { name: 'and more', mark: '…', tone: 'more' },
  ];

  return (
    <section className="arch-pipeline blueprint" aria-label="Architecture pipeline">
      <div className="entry-stack">
        <div className="entry-card node-card">
          <span className="node-icon chat"><Icon name="messages" /></span>
          <strong>User Entry</strong>
          <small>APP Chat / Web Chat<br />XWorkmate Bridge</small>
        </div>

        <button type="button" className="gateway-card node-card" onClick={() => onOpenService(serviceRegistry.find((item) => item.id === 'openclaw')!)}>
          <div className="gateway-meta">
            <span className="node-index blue">1</span>
            <span className="node-title">{labels.gatewayBand}</span>
          </div>
          {dot(stateOf('openclaw'))}
          <strong>OpenClaw Gateway</strong>
          <small>v2026.6.1</small>
          <small>127.0.0.1:18789</small>
          <small>token auth</small>
          <small>Local Only</small>
        </button>
      </div>

      <div className="agent-plane node-card">
        <div className="node-head">
          <span className="node-index purple">2</span>
          <strong>{labels.agentBand}</strong>
          <small>4 {labels.sessions} · 8 {labels.workers}</small>
          {dot()}
        </div>
        <div className="agent-icons">
          {['Main Agent', 'Memory', 'Scheduler', 'SubAgents', 'ACP Router'].map((item, index) => (
            <span key={item}><Icon name={index === 1 ? 'database' : index === 2 ? 'plus' : index === 4 ? 'network' : 'bot'} />{item}</span>
          ))}
        </div>
        <div className="agent-inner-grid">
          <div className="mini-node">
            <strong>{labels.memoryCard}</strong>
            <span>QMD (Vector Search)</span>
            <span>MEMORY.md</span>
            <span>memory/*.md (Logs)</span>
            <span>Session Index</span>
          </div>
          <div className="mini-node">
            <strong>{labels.acpCard}</strong>
            <div className="router-grid">
              {acpAgents.map((agent) => (
                <em key={agent} className={runningAgents.includes(agent) ? 'busy' : ''}>{agent}</em>
              ))}
            </div>
          </div>
        </div>
      </div>

      <button type="button" className="skill-plane node-card" aria-expanded={skillsOpen} onClick={() => setSkillsOpen((value) => !value)}>
        <div className="node-head">
          <span className="node-index green">3</span>
          <strong>{labels.skillBand} Layer</strong>
          <small>{totalSkills * 2}+ {labels.skillsCount}</small>
          {dot(stateOf('bridge'))}
        </div>
        <div className="skill-stack">
          {skillGroups.map((group) => (
            <div key={group.name} className="skill-item">
              <span><Icon name={group.name === 'Image' ? 'chart' : group.name === 'Workflow' ? 'sparkles' : 'folder'} /></span>
              <strong>{group.name} Skills</strong>
              <small>{group.skills.join(' · ')}</small>
            </div>
          ))}
        </div>
      </button>

      <aside className="workspace-status node-card">
        <strong>{labels.workspaceStatus}</strong>
        <div><span>{labels.sessions}</span><b>333</b><small>Active</small><Icon name="user" /></div>
        <div><span>Agents</span><b>7</b><small>Connected</small><Icon name="bot" /></div>
        <div><span>Memory</span><b>Enabled</b><Icon name="database" /></div>
        <div><span>Skills</span><b>30+</b><Icon name="sparkles" /></div>
      </aside>

      <button type="button" className="model-layer node-card" onClick={() => onOpenService(serviceRegistry.find((item) => item.id === 'litellm')!)}>
        <div className="node-head">
          <span className="node-index amber">4</span>
          <strong>{labels.modelBand} Layer</strong>
          <small>LiteLLM · 4000 · OpenAI-compatible · Anthropic-compatible</small>
          {dot(stateOf('litellm'))}
        </div>
      </button>

      <div className="external-layer node-card">
        <div className="node-head">
          <span className="node-index red">5</span>
          <strong>External Model Services</strong>
        </div>
        <div className="model-row">
          {externalModels.map((model) => (
            <span key={model.name}>
              <i className={`model-logo ${model.tone}`}>{model.mark}</i>
              {model.name}
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}

export { findServiceDef };
