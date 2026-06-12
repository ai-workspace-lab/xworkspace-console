'use client';

import { useState } from 'react';
import type { Tab } from '@/lib/data';
import { Icon } from './Icon';

export function EmbedView({ tab, onBack }: { tab: Tab; onBack: () => void }) {
  const [reloadKey, setReloadKey] = useState(0);
  const frameBlocked = tab.frameMode === 'external';
  return (
    <div className="workspace-body">
      <section className="embed-panel">
        <div className="embed-toolbar">
          <button type="button" className="embed-tool" aria-label="Back to workspace" onClick={onBack}>
            <Icon name="arrow-left" />
          </button>
          <strong>{tab.label}</strong>
          <span className="embed-url" title={tab.href}>{tab.href}</span>
          <div className="embed-toolbar-actions">
            <button type="button" className="embed-tool" aria-label="Reload embedded page" onClick={() => setReloadKey((value) => value + 1)} disabled={frameBlocked}>
              <Icon name="refresh" />
            </button>
            <a className="embed-tool" href={tab.href} target="_blank" rel="noreferrer" aria-label="Open in browser">
              <Icon name="external" />
            </a>
          </div>
        </div>
        {frameBlocked ? (
          <div className="external-embed-fallback">
            <div>
              <span className="external-embed-icon"><Icon name={tab.icon ?? 'external'} /></span>
              <strong>{tab.label}</strong>
              <p>This service blocks embedded frames. Open it in a dedicated browser tab.</p>
              <a href={tab.href} target="_blank" rel="noreferrer">Open {tab.label}</a>
            </div>
          </div>
        ) : (
          <iframe
            key={reloadKey}
            title={`${tab.label} workspace`}
            src={tab.href}
            allow="camera; microphone; display-capture; autoplay; clipboard-read; clipboard-write; fullscreen"
            allowFullScreen
            referrerPolicy="no-referrer"
          />
        )}
      </section>
    </div>
  );
}
