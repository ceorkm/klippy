import React from "react";
import {
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  Easing,
} from "remotion";
import { COLORS, FONTS } from "../theme";
import { SceneBg } from "../components/SceneBg";

// Scene 4 — Smart Classification (5s / 150 frames)

// SVG icon components for each content type
const Icons: Record<string, (color: string) => React.ReactNode> = {
  URLs: (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
  ),
  Code: (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="16 18 22 12 16 6" />
      <polyline points="8 6 2 12 8 18" />
    </svg>
  ),
  Emails: (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7" />
    </svg>
  ),
  "API Keys": (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
    </svg>
  ),
  JSON: (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1" />
      <path d="M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1" />
    </svg>
  ),
  Images: (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
      <circle cx="8.5" cy="8.5" r="1.5" />
      <polyline points="21 15 16 10 5 21" />
    </svg>
  ),
  Addresses: (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z" />
      <circle cx="12" cy="10" r="3" />
    </svg>
  ),
  "Payment Cards": (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="1" y="4" width="22" height="16" rx="2" ry="2" />
      <line x1="1" y1="10" x2="23" y2="10" />
    </svg>
  ),
  "Phone Numbers": (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z" />
    </svg>
  ),
  Colors: (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="13.5" cy="6.5" r="2.5" />
      <circle cx="17.5" cy="10.5" r="2.5" />
      <circle cx="8.5" cy="7.5" r="2.5" />
      <circle cx="6.5" cy="12.5" r="2.5" />
      <path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z" />
    </svg>
  ),
  Markdown: (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="M7 8v8l3-3 3 3V8" />
      <path d="M17 12h-2l2-4 2 4h-2v4" />
    </svg>
  ),
  Dates: (c) => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
      <line x1="16" y1="2" x2="16" y2="6" />
      <line x1="8" y1="2" x2="8" y2="6" />
      <line x1="3" y1="10" x2="21" y2="10" />
    </svg>
  ),
};

const CONTENT_TYPES = [
  { name: "URLs", color: COLORS.purple, count: "847K", pattern: "HTTP/HTTPS links" },
  { name: "Code", color: COLORS.mint, count: "421K", pattern: "Swift, JS, Python..." },
  { name: "Emails", color: COLORS.green, count: "156K", pattern: "RFC-compliant" },
  { name: "API Keys", color: COLORS.red, count: "12K", pattern: "15+ providers" },
  { name: "JSON", color: COLORS.cyan, count: "234K", pattern: "Validated structure" },
  { name: "Images", color: COLORS.pink, count: "89K", pattern: "With thumbnails" },
  { name: "Addresses", color: COLORS.yellow, count: "45K", pattern: "Street + ZIP" },
  { name: "Payment Cards", color: COLORS.red, count: "3K", pattern: "Luhn validated" },
  { name: "Phone Numbers", color: COLORS.blue, count: "67K", pattern: "US & international" },
  { name: "Colors", color: COLORS.accent, count: "28K", pattern: "Hex, RGB values" },
  { name: "Markdown", color: COLORS.muted, count: "134K", pattern: "Syntax patterns" },
  { name: "Dates", color: COLORS.yellow, count: "91K", pattern: "Multiple formats" },
];

export const Scene4Classification: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const titleIn = spring({ frame, fps, config: { damping: 200 } });
  const subIn = spring({ frame: frame - 10, fps, config: { damping: 200 } });
  const titleBlur = interpolate(frame, [0, 18], [14, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const subBlur = interpolate(frame, [10, 26], [10, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // Perspective — overhead angle on card grid
  const perspRotX = interpolate(frame, [0, 40], [14, 6], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        background: "#fafaf8",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        alignItems: "center",
        fontFamily: FONTS.heading,
        position: "relative",
        overflow: "hidden",
        padding: "0 60px",
        perspective: 800,
      }}
    >
      <SceneBg />
      {/* Header */}
      <div style={{ textAlign: "center", marginBottom: 16, opacity: titleIn, transform: `translateY(${(1 - titleIn) * 20}px)`, filter: `blur(${titleBlur}px)`, zIndex: 2 }}>
        <div style={{ fontSize: 18, color: COLORS.accent, fontWeight: 600, letterSpacing: 3, textTransform: "uppercase", marginBottom: 12 }}>
          Smart Classification
        </div>
        <div style={{ fontSize: 64, fontWeight: 800, color: COLORS.text, letterSpacing: -1 }}>
          15+ Content Types
        </div>
      </div>
      <div style={{ fontSize: 22, color: COLORS.textSecondary, textAlign: "center", opacity: subIn, marginBottom: 40, filter: `blur(${subBlur}px)`, zIndex: 2 }}>
        Rule-based detection. No AI. No cloud. Zero false positives.
      </div>

      {/* Grid */}
      <div style={{ display: "flex", flexWrap: "wrap", gap: 16, justifyContent: "center", maxWidth: 1200, transform: `rotateX(${perspRotX}deg)`, zIndex: 2 }}>
        {CONTENT_TYPES.map((type, i) => {
          const cardIn = spring({ frame: frame - 25 - i * 4, fps, config: { damping: 20, stiffness: 150 } });

          return (
            <div
              key={type.name}
              style={{
                width: 290,
                padding: "16px 20px",
                borderRadius: 12,
                background: COLORS.bg,
                border: `1px solid ${COLORS.border}`,
                opacity: cardIn,
                transform: `scale(${0.85 + cardIn * 0.15}) translateY(${(1 - cardIn) * 15}px)`,
                display: "flex",
                alignItems: "center",
                gap: 14,
                boxShadow: "0 2px 8px rgba(0,0,0,0.04)",
              }}
            >
              {/* Icon */}
              <div
                style={{
                  width: 50,
                  height: 50,
                  borderRadius: 10,
                  background: `${type.color}12`,
                  border: `1px solid ${type.color}20`,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  flexShrink: 0,
                }}
              >
                {Icons[type.name]?.(type.color) ?? (
                  <div style={{ width: 14, height: 14, borderRadius: 4, background: type.color }} />
                )}
              </div>

              <div style={{ flex: 1 }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <span style={{ fontSize: 18, fontWeight: 700, color: COLORS.text }}>{type.name}</span>
                  <span style={{ fontSize: 14, color: type.color, fontFamily: FONTS.mono, fontWeight: 600 }}>{type.count}</span>
                </div>
                <div style={{ fontSize: 13, color: COLORS.dim, marginTop: 2 }}>{type.pattern}</div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
