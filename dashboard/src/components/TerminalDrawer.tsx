'use client';

import { useRef, useState } from 'react';
import type { Labels } from '@/lib/data';
import { Icon } from './Icon';

export function TerminalDrawer({
  labels,
  collapsed,
  expanded,
  onCollapse,
  onToggle,
}: {
  labels: Labels;
  collapsed: boolean;
  expanded: boolean;
  onCollapse: () => void;
  onToggle: () => void;
}) {
  const [height, setHeight] = useState(250);
  const [dragging, setDragging] = useState(false);
  const dragStart = useRef({ y: 0, height: 250 });

  const onDragStart = (event: React.PointerEvent) => {
    if (expanded || collapsed) return;
    event.preventDefault();
    (event.target as HTMLElement).setPointerCapture(event.pointerId);
    dragStart.current = { y: event.clientY, height };
    setDragging(true);
  };

  const onDragMove = (event: React.PointerEvent) => {
    if (!dragging) return;
    const delta = dragStart.current.y - event.clientY;
    const max = Math.floor(window.innerHeight * 0.8);
    setHeight(Math.min(max, Math.max(120, dragStart.current.height + delta)));
  };

  const onDragEnd = (event: React.PointerEvent) => {
    if (!dragging) return;
    (event.target as HTMLElement).releasePointerCapture(event.pointerId);
    setDragging(false);
  };

  return (
    <section className={[expanded ? 'terminal-drawer expanded' : 'terminal-drawer', collapsed ? 'collapsed' : '', dragging ? 'dragging' : ''].join(' ')}>
      <div
        className="terminal-resize-handle"
        role="separator"
        aria-orientation="horizontal"
        aria-label="Resize terminal"
        onPointerDown={onDragStart}
        onPointerMove={onDragMove}
        onPointerUp={onDragEnd}
        onPointerCancel={onDragEnd}
      >
        <span />
      </div>
      <div className="terminal-head clickable" onClick={onCollapse} role="button" aria-expanded={!collapsed}>
        <div>
          <Icon name={collapsed ? 'chevron-right' : 'chevron-down'} />
          <Icon name="terminal" />
          <strong>{labels.terminal}</strong>
        </div>
        <div className="terminal-actions" onClick={(event) => event.stopPropagation()}>
          <a href="http://127.0.0.1:7681" target="_blank" rel="noreferrer">{labels.newTab}</a>
          <button type="button" onClick={onCollapse}>{collapsed ? labels.expand : labels.collapse}</button>
          <button type="button" onClick={onToggle}>{expanded ? labels.restore : labels.maximize}</button>
          <button type="button" aria-label="Terminal menu">⋮</button>
        </div>
      </div>
      <div className="terminal-frame" style={!expanded && !collapsed ? { height } : undefined}>
        {!collapsed ? (
          <iframe title="ttyd terminal" src="http://127.0.0.1:7681" loading="lazy" style={dragging ? { pointerEvents: 'none' } : undefined} />
        ) : null}
      </div>
    </section>
  );
}
