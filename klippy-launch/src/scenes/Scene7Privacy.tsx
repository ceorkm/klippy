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

// Scene 7 — Privacy & Security (3.5s / 105 frames)

// Badge icons
const BadgeIcons: Record<string, React.ReactNode> = {
  "100% Local Storage": (
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke={COLORS.green} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <ellipse cx="12" cy="5" rx="9" ry="3" />
      <path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3" />
      <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5" />
    </svg>
  ),
  "No Cloud Sync": (
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke={COLORS.green} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 2l20 20" />
      <path d="M18.09 18.09A6.5 6.5 0 0 1 6.5 17H5a4 4 0 0 1-.95-7.88" />
      <path d="M7.73 7.73A6.5 6.5 0 0 1 18.5 10h.5a4 4 0 0 1 3.15 6.46" />
    </svg>
  ),
  "No Telemetry": (
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke={COLORS.green} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z" />
      <circle cx="12" cy="12" r="3" />
      <line x1="2" y1="2" x2="22" y2="22" />
    </svg>
  ),
  "Fully Open Source": (
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke={COLORS.green} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="16 18 22 12 16 6" />
      <polyline points="8 6 2 12 8 18" />
    </svg>
  ),
};

export const Scene7Privacy: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const shieldScale = spring({ frame, fps, config: { damping: 10, stiffness: 120 } });
  const titleIn = spring({ frame: frame - 15, fps, config: { damping: 200 } });
  const titleBlur = interpolate(frame, [15, 32], [12, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // Perspective — overhead angle on badges
  const perspRotX = interpolate(frame, [0, 35], [12, 5], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const badges = [
    { text: "100% Local Storage", desc: "Core Data + SQLite" },
    { text: "No Cloud Sync", desc: "Data never leaves your Mac" },
    { text: "No Telemetry", desc: "Zero analytics, zero tracking" },
    { text: "Fully Open Source", desc: "MIT Licensed — audit every line" },
  ];

  const features = [
    "API key detection (15+ providers)",
    "Payment card validation (Luhn check)",
    "Auth token flagging",
    "macOS sandbox compatible",
  ];

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        background: "#fafaf8",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: FONTS.heading,
        position: "relative",
        overflow: "hidden",
        perspective: 800,
      }}
    >
      <SceneBg color={COLORS.green} />
      {/* Shield icon — SVG, no emoji */}
      <div style={{ transform: `scale(${shieldScale})`, marginBottom: 16, zIndex: 2 }}>
        <svg width="100" height="100" viewBox="0 0 24 24" fill="none" stroke={COLORS.green} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
          <path d="m9 12 2 2 4-4" stroke={COLORS.green} strokeWidth="2" />
        </svg>
      </div>

      {/* Title */}
      <div style={{ fontSize: 18, color: COLORS.green, fontWeight: 600, letterSpacing: 3, textTransform: "uppercase", marginBottom: 10, opacity: titleIn, zIndex: 2, filter: `blur(${titleBlur}px)` }}>
        Privacy First
      </div>
      <div style={{ fontSize: 60, fontWeight: 800, color: COLORS.text, letterSpacing: -1, marginBottom: 36, opacity: titleIn, transform: `translateY(${(1 - titleIn) * 15}px)`, zIndex: 2, filter: `blur(${titleBlur}px)` }}>
        Your data stays on your Mac
      </div>

      {/* Badge cards */}
      <div style={{ display: "flex", gap: 16, marginBottom: 32, zIndex: 2, transform: `rotateX(${perspRotX}deg)` }}>
        {badges.map((badge, i) => {
          const badgeIn = spring({ frame: frame - 20 - i * 6, fps, config: { damping: 15, stiffness: 150 } });
          return (
            <div
              key={badge.text}
              style={{
                padding: "16px 20px",
                borderRadius: 12,
                background: COLORS.bg,
                border: `1px solid ${COLORS.border}`,
                textAlign: "center",
                width: 230,
                opacity: badgeIn,
                transform: `scale(${0.85 + badgeIn * 0.15}) translateY(${(1 - badgeIn) * 15}px)`,
                boxShadow: "0 2px 8px rgba(0,0,0,0.04)",
              }}
            >
              <div style={{ margin: "0 auto 10px", width: 48, height: 48, borderRadius: 12, background: `${COLORS.green}10`, border: `1px solid ${COLORS.green}20`, display: "flex", alignItems: "center", justifyContent: "center" }}>
                {BadgeIcons[badge.text]}
              </div>
              <div style={{ fontSize: 18, fontWeight: 700, color: COLORS.text, marginBottom: 4 }}>{badge.text}</div>
              <div style={{ fontSize: 14, color: COLORS.dim }}>{badge.desc}</div>
            </div>
          );
        })}
      </div>

      {/* Feature list */}
      <div style={{ display: "flex", gap: 20, zIndex: 2 }}>
        {features.map((feat, i) => {
          const featIn = spring({ frame: frame - 50 - i * 5, fps, config: { damping: 200 } });
          return (
            <div key={feat} style={{ display: "flex", alignItems: "center", gap: 6, opacity: featIn }}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={COLORS.green} strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                <path d="m5 12 5 5L20 7" />
              </svg>
              <span style={{ fontSize: 16, color: COLORS.textSecondary }}>{feat}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
};
