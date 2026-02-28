// Klippy Launch Video - Design System
// Clean white background — professional, attention-grabbing

export const COLORS = {
  bg: "#ffffff",
  surface: "#f5f5f4",
  surfaceLight: "#fafaf9",
  border: "#e7e5e4",
  borderDark: "#d6d3d1",
  accent: "#f97316", // Klippy orange
  accentLight: "#fb923c",
  accentDark: "#ea580c",
  text: "#1c1917",
  textSecondary: "#57534e",
  muted: "#78716c",
  dim: "#a8a29e",
  // Category colors
  purple: "#7c3aed",
  green: "#16a34a",
  mint: "#0d9488",
  pink: "#db2777",
  blue: "#2563eb",
  red: "#dc2626",
  yellow: "#ca8a04",
  cyan: "#0891b2",
} as const;

export const FONTS = {
  heading: "Space Grotesk, system-ui, sans-serif",
  mono: "Space Mono, JetBrains Mono, Menlo, monospace",
  brand: "Space Grotesk, system-ui, sans-serif",
} as const;

export const VIDEO = {
  width: 1920,
  height: 1080,
  fps: 30,
} as const;
