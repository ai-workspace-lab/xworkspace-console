import React from 'react';

const paths: Record<string, React.ReactNode> = {
  home: <path d="M3 10.5 12 3l9 7.5v9a1.5 1.5 0 0 1-1.5 1.5H15v-6H9v6H4.5A1.5 1.5 0 0 1 3 19.5z" />,
  bot: <path d="M8 9h8a4 4 0 0 1 4 4v4.5A2.5 2.5 0 0 1 17.5 20h-11A2.5 2.5 0 0 1 4 17.5V13a4 4 0 0 1 4-4Zm1 4h.01M15 13h.01M9 17h6M12 5v4M9 5h6" />,
  box: <path d="m12 3 8 4v10l-8 4-8-4V7zM4 7l8 4 8-4M12 11v10" />,
  clock: <path d="M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 4.5V12l3 2" />,
  database: <path d="M5 6c0-1.7 3.1-3 7-3s7 1.3 7 3-3.1 3-7 3-7-1.3-7-3Zm0 0v6c0 1.7 3.1 3 7 3s7-1.3 7-3V6M5 12v6c0 1.7 3.1 3 7 3s7-1.3 7-3v-6" />,
  memory: <path d="M7 4h10a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3Zm2 4h6v8H9zM9 2v2M15 2v2M9 20v2M15 20v2M2 9h2M2 15h2M20 9h2M20 15h2" />,
  messages: <path d="M5 6.5A3.5 3.5 0 0 1 8.5 3h7A3.5 3.5 0 0 1 19 6.5v4A3.5 3.5 0 0 1 15.5 14H11l-4 3v-3A3.5 3.5 0 0 1 3.5 10.5v-4Z" />,
  network: <path d="M12 5v4M12 15v4M5 12h4M15 12h4M9 9l-3-3M15 9l3-3M9 15l-3 3M15 15l3 3M9 12a3 3 0 1 0 6 0 3 3 0 0 0-6 0Z" />,
  plus: <path d="M12 5v14M5 12h14" />,
  sparkles: <path d="m12 3 1.7 5.1L19 10l-5.3 1.9L12 17l-1.7-5.1L5 10l5.3-1.9zM19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8zM5 15l.8 2.2L8 18l-2.2.8L5 21l-.8-2.2L2 18l2.2-.8z" />,
  tasks: <path d="M8 6h11M8 12h11M8 18h11M4.5 6l1 1 1.8-2M4.5 12l1 1 1.8-2M4.5 18l1 1 1.8-2" />,
  folder: <path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H10l2 2h6.5A2.5 2.5 0 0 1 21 9.5v7A2.5 2.5 0 0 1 18.5 19h-13A2.5 2.5 0 0 1 3 16.5z" />,
  claw: <path d="M12 3v5M7 5l2.5 4M17 5l-2.5 4M5 13a7 7 0 0 0 14 0M8 13a4 4 0 0 0 8 0" />,
  bridge: <path d="M4 17h16M6 17V9l6-4 6 4v8M8 17v-5h8v5" />,
  chart: <path d="M4 19V5M4 19h16M7 15l3-4 4 2 4-7" />,
  shield: <path d="M12 3 20 6v5c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6z" />,
  cube: <path d="m12 3 8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9" />,
  terminal: <path d="m5 8 4 4-4 4M11 17h8" />,
  settings: <path d="M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Zm0-5v3M12 18v3M4.2 5.6l2.1 2.1M17.7 16.3l2.1 2.1M3 12h3M18 12h3M4.2 18.4l2.1-2.1M17.7 7.7l2.1-2.1" />,
  menu: <path d="M5 7h14M5 12h14M5 17h14" />,
  globe: <path d="M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm-8 9h16M12 3c2.2 2.4 3.3 5.4 3.3 9S14.2 18.6 12 21M12 3C9.8 5.4 8.7 8.4 8.7 12S9.8 18.6 12 21" />,
  wifi: <path d="M4 9a12 12 0 0 1 16 0M7 12a7.5 7.5 0 0 1 10 0M10 15a3 3 0 0 1 4 0M12 19h.01" />,
  bell: <path d="M18 16H6l1.4-2V10a4.6 4.6 0 0 1 9.2 0v4zM10 19h4" />,
  user: <path d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM4 21a8 8 0 0 1 16 0" />,
  languages: <path d="M4 6h9M8.5 4v2c0 4-2.2 7.2-5.5 9M6 10c1.5 2.2 3.8 4.1 6.6 5.5M14 18h7M17.5 6l4.5 12M20.3 13h-5.6" />,
  moon: <path d="M20 14.5A7.5 7.5 0 1 1 9.5 4 6 6 0 0 0 20 14.5Z" />,
  sun: <path d="M12 3v2.2M12 18.8V21M4.9 4.9l1.6 1.6M17.5 17.5l1.6 1.6M3 12h2.2M18.8 12H21M4.9 19.1l1.6-1.6M17.5 6.5l1.6-1.6M12 7.2a4.8 4.8 0 1 0 0 9.6 4.8 4.8 0 0 0 0-9.6Z" />,
  'arrow-left': <path d="M19 12H5M12 5l-7 7 7 7" />,
  refresh: <path d="M20 11A8 8 0 1 0 18.9 15M20 4v7h-7" />,
  external: <path d="M14 4h6v6M20 4l-9 9M19 14v5a1.5 1.5 0 0 1-1.5 1.5h-12A1.5 1.5 0 0 1 4 19V6.5A1.5 1.5 0 0 1 5.5 5H10" />,
  check: <path d="m5 12 5 5L20 7" />,
  alert: <path d="M12 9v4M12 17h.01M10.3 4.3 2.8 17.5A2 2 0 0 0 4.5 20.5h15a2 2 0 0 0 1.7-3L13.7 4.3a2 2 0 0 0-3.4 0Z" />,
  'chevron-left': <path d="m15 18-6-6 6-6" />,
  'chevron-down': <path d="m6 9 6 6 6-6" />,
  'chevron-right': <path d="m9 18 6-6-6-6" />,
  'chevrons-left': <path d="m13.5 17-5-5 5-5M19 17l-5-5 5-5" />,
  'chevrons-right': <path d="m10.5 17 5-5-5-5M5 17l5-5-5-5" />,
  'panel-collapse': <path d="M20 6H4M20 12h-8M20 18H4M8 9.5 5.5 12 8 14.5" />,
  'panel-expand': <path d="M4 6h16M12 12h8M4 18h16M6 9.5 8.5 12 6 14.5" />,
  rocket: <path d="M5 16c-1 1-1.5 4-1.5 4S6.5 19.5 7.5 18.5M14 4c3 0 6 3 6 6-2.5 5-7 9-11 10l-5-5C5 11 9.5 6.5 14 4Zm0 4a2 2 0 1 0 .01 4A2 2 0 0 0 14 8Z" />,
  help: <path d="M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm-2.5 6.5a2.5 2.5 0 1 1 3.7 2.2c-.8.45-1.2.9-1.2 1.8M12 17h.01" />,
};

export function Icon({ name }: { name: string }) {
  return (
    <svg className="icon" viewBox="0 0 24 24" aria-hidden="true">
      <g fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8">
        {paths[name] ?? paths.cube}
      </g>
    </svg>
  );
}
