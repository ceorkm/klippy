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

// Scene 6 — Scale Demo (4s / 120 frames)

// Metric icons
const MetricIcons: Record<string, (c: string) => React.ReactNode> = {
  "Search Response": (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" />
    </svg>
  ),
  Scrolling: (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="3" width="20" height="14" rx="2" ry="2" /><line x1="8" y1="21" x2="16" y2="21" /><line x1="12" y1="17" x2="12" y2="21" />
    </svg>
  ),
  "Cache Hit Rate": (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <ellipse cx="12" cy="5" rx="9" ry="3" /><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3" /><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5" />
    </svg>
  ),
  "Max Memory": (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="4" y="4" width="16" height="16" rx="2" /><rect x="9" y="9" width="6" height="6" /><path d="M15 2v2" /><path d="M15 20v2" /><path d="M2 15h2" /><path d="M2 9h2" /><path d="M20 15h2" /><path d="M20 9h2" /><path d="M9 2v2" /><path d="M9 20v2" />
    </svg>
  ),
  "Startup Time": (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" />
    </svg>
  ),
  "Background Processing": (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="23 4 23 10 17 10" /><polyline points="1 20 1 14 7 14" /><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
    </svg>
  ),
};

export const Scene6Scale: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const counterProgress = interpolate(frame, [10, 80], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.bezier(0.25, 0.1, 0.25, 1),
  });
  const counterValue = Math.floor(counterProgress * 3247891);
  const formattedCounter = counterValue.toLocaleString();

  const titleIn = spring({ frame, fps, config: { damping: 200 } });
  const subtitleIn = spring({ frame: frame - 10, fps, config: { damping: 200 } });

  // Perspective — overhead angle on metrics
  const perspRotX = interpolate(frame, [0, 40], [12, 5], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const titleBlur = interpolate(frame, [0, 18], [14, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const metrics = [
    { label: "Search Response", value: "<100ms", color: COLORS.green },
    { label: "Scrolling", value: "60 fps", color: COLORS.accent },
    { label: "Cache Hit Rate", value: "94%", color: COLORS.purple },
    { label: "Max Memory", value: "500MB", color: COLORS.blue },
    { label: "Startup Time", value: "<2s", color: COLORS.yellow },
    { label: "Background Processing", value: "Always", color: COLORS.mint },
  ];

  const bars = [
    { label: "10K", height: 0.08 },
    { label: "100K", height: 0.18 },
    { label: "500K", height: 0.38 },
    { label: "1M", height: 0.58 },
    { label: "2M", height: 0.78 },
    { label: "3M+", height: 1.0 },
  ];

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
        perspective: 800,
      }}
    >
      <SceneBg />

      {/* Top section: Label + Counter */}
      <div style={{ textAlign: "center", marginBottom: 8, opacity: titleIn, zIndex: 2 }}>
        <div style={{ fontSize: 18, color: COLORS.accent, fontWeight: 600, letterSpacing: 3, textTransform: "uppercase", marginBottom: 16, filter: `blur(${titleBlur}px)` }}>
          Performance at Scale
        </div>
      </div>

      {/* Counter */}
      <div
        style={{
          fontSize: 140,
          fontWeight: 900,
          fontFamily: FONTS.mono,
          color: COLORS.text,
          letterSpacing: -4,
          textAlign: "center",
          lineHeight: 1,
          zIndex: 2,
        }}
      >
        {formattedCounter}
      </div>
      <div style={{ fontSize: 28, color: COLORS.textSecondary, marginTop: 10, marginBottom: 50, opacity: subtitleIn, zIndex: 2 }}>
        clipboard items — zero slowdown
      </div>

      {/* Bottom section: Metrics + Chart side by side */}
      <div style={{ display: "flex", gap: 50, alignItems: "flex-end", maxWidth: 1200, zIndex: 2, transform: `rotateX(${perspRotX}deg)` }}>
        {/* Metrics grid */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
          {metrics.map((m, i) => {
            const mIn = spring({ frame: frame - 30 - i * 5, fps, config: { damping: 200 } });
            return (
              <div
                key={m.label}
                style={{
                  padding: "16px 22px",
                  borderRadius: 12,
                  background: COLORS.bg,
                  border: `1px solid ${COLORS.border}`,
                  display: "flex",
                  alignItems: "center",
                  gap: 14,
                  opacity: mIn,
                  transform: `translateY(${(1 - mIn) * 10}px)`,
                  boxShadow: "0 2px 12px rgba(0,0,0,0.05)",
                  minWidth: 240,
                }}
              >
                <div
                  style={{
                    width: 40,
                    height: 40,
                    borderRadius: 10,
                    background: `${m.color}10`,
                    border: `1px solid ${m.color}20`,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    flexShrink: 0,
                  }}
                >
                  {MetricIcons[m.label]?.(m.color)}
                </div>
                <div>
                  <div style={{ fontSize: 26, fontWeight: 800, color: m.color, fontFamily: FONTS.mono, lineHeight: 1.2 }}>{m.value}</div>
                  <div style={{ fontSize: 13, color: COLORS.dim }}>{m.label}</div>
                </div>
              </div>
            );
          })}
        </div>

        {/* Bar chart */}
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
          <div style={{ display: "flex", alignItems: "flex-end", gap: 14, height: 280 }}>
            {bars.map((bar, i) => {
              const barIn = spring({ frame: frame - 20 - i * 6, fps, config: { damping: 15, stiffness: 100 } });
              const barHeight = bar.height * 240 * barIn;
              return (
                <div key={bar.label} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
                  <div
                    style={{
                      width: 52,
                      height: barHeight,
                      borderRadius: 8,
                      background: `linear-gradient(to top, ${COLORS.accentDark}, ${COLORS.accent})`,
                      opacity: 0.75 + barIn * 0.25,
                      boxShadow: bar.height >= 0.78 ? `0 4px 16px ${COLORS.accent}30` : "none",
                    }}
                  />
                  <span style={{ fontSize: 13, color: COLORS.dim, fontFamily: FONTS.mono }}>{bar.label}</span>
                </div>
              );
            })}
          </div>
          <div style={{ fontSize: 13, color: COLORS.dim, letterSpacing: 1, textTransform: "uppercase", marginTop: 4 }}>
            Clipboard Items
          </div>
        </div>
      </div>
    </div>
  );
};
