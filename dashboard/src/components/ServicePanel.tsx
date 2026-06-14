'use client';

import { useRef, useState } from 'react';
import type { PortalService } from '@/lib/data';
import { Icon } from './Icon';

export function ServicePanel({ service, onBack }: { service: PortalService; onBack: () => void }) {
  const [reloadKey, setReloadKey] = useState(0);
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const external = service.openMode === 'external';
  const focusFrame = () => {
    iframeRef.current?.focus();
    iframeRef.current?.contentWindow?.focus();
  };
  return (
    <div className="workspace-body">
      <section className="embed-panel">
        <div className="embed-toolbar">
          <button type="button" className="embed-tool" aria-label="Back to workspace" onClick={onBack}>
            <Icon name="arrow-left" />
          </button>
          <strong>{service.name}</strong>
          <span className="embed-url" title={service.url}>{service.url}</span>
          <div className="embed-toolbar-actions">
            <button type="button" className="embed-tool" aria-label="Reload embedded page" onClick={() => setReloadKey((value) => value + 1)} disabled={external}>
              <Icon name="refresh" />
            </button>
            <a className="embed-tool" href={service.url} target="_blank" rel="noreferrer" aria-label="Open in browser">
              <Icon name="external" />
            </a>
          </div>
        </div>
        {external ? (
          <div className="external-embed-fallback">
            <div>
              <span className="external-embed-icon"><Icon name={service.icon ?? 'external'} /></span>
              <strong>{service.name}</strong>
              <p>{service.description ?? 'Open this service in a dedicated browser tab.'}</p>
              <a href={service.url} target="_blank" rel="noreferrer">
                <Icon name="external" />
                <span>Open {service.name}</span>
              </a>
            </div>
          </div>
        ) : (
          <iframe
            ref={iframeRef}
            key={reloadKey}
            title={`${service.name} workspace`}
            src={service.url}
            tabIndex={0}
            allow="camera; microphone; display-capture; autoplay; clipboard-read; clipboard-write; fullscreen"
            allowFullScreen
            onLoad={focusFrame}
            onFocus={focusFrame}
            onPointerDown={focusFrame}
            onMouseDown={focusFrame}
            referrerPolicy="no-referrer"
            style={{ pointerEvents: 'auto' }}
          />
        )}
      </section>
    </div>
  );
}
