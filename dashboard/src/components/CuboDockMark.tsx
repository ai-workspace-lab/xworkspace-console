import React from 'react';

interface CuboDockMarkProps {
  size?: number;
  className?: string;
  withBackground?: boolean;
}

export function CuboDockMark({ size = 32, className = '', withBackground = true }: CuboDockMarkProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 512 512"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      aria-label="Cubo-Dock Logo"
    >
      {withBackground && (
        <rect width="512" height="512" rx="136" fill="#0F172A" />
      )}

      {/* Cubo-Dock Main Observation Cockpit */}
      <g transform="translate(64, 48) scale(1.92)">
        {/* Lateral Extension Flanges */}
        <rect x="24" y="86" width="16" height="30" rx="8" fill="#6366F1" />
        <rect x="160" y="86" width="16" height="30" rx="8" fill="#6366F1" />
        {/* Grounded Podium Chassis */}
        <rect x="36" y="80" width="128" height="66" rx="24" fill="#6366F1" />
        {/* Clear Observation Canopy Dome */}
        <path d="M54 80 C54 44 80 32 100 32 C120 32 146 44 146 80 Z" fill="#4338CA" />
        {/* Luminous Emerald Green Core Eyes */}
        <circle cx="82" cy="60" r="7" fill="#10B981" />
        <circle cx="118" cy="60" r="7" fill="#10B981" />
        {/* Chassis Emerald Status Visor */}
        <rect x="76" y="106" width="48" height="12" rx="6" fill="#10B981" />
      </g>

      {/* Bottom-Right 2x2 Ecosystem Badge */}
      <g transform="translate(396, 396)">
        <rect width="80" height="80" rx="22" fill="#1E293B" fillOpacity="0.96" />
        <rect x="14" y="14" width="22" height="22" rx="6" fill="#38BDF8" />
        <rect x="44" y="14" width="22" height="22" rx="6" fill="#FFFFFF" />
        <rect x="14" y="44" width="22" height="22" rx="6" fill="#FFFFFF" />
        <rect x="44" y="44" width="22" height="22" rx="6" fill="#38BDF8" />
      </g>
    </svg>
  );
}
