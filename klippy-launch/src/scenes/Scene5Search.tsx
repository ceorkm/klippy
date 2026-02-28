import React from "react";
import {
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  Easing,
} from "remotion";
import { COLORS, FONTS } from "../theme";
import { AppWindow } from "./AppWindow";
import { SceneBg } from "../components/SceneBg";

// Scene 5 — Search Power (5s / 150 frames)
// Shows searching across multiple content types

export const Scene5Search: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const searchQuery = "stripe";
  const typedChars = Math.min(
    Math.floor(interpolate(frame, [20, 45], [0, searchQuery.length], {
      extrapolateRight: "clamp",
      extrapolateLeft: "clamp",
    })),
    searchQuery.length
  );
  const displayedQuery = searchQuery.slice(0, typedChars);
  const cursorVisible = Math.floor(frame / 8) % 2 === 0;

  const windowIn = spring({ frame, fps, config: { damping: 200 } });

  // Persistent perspective tilt — classic product showcase
  const perspRotY = interpolate(frame, [0, 40], [-22, -14], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const perspRotX = interpolate(frame, [0, 40], [10, 5], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const SEARCH_RESULTS = [
    { type: "URL", color: COLORS.purple, text: "https://dashboard.stripe.com/payments", time: "5m ago" },
    { type: "API Key", color: COLORS.red, text: "sk_test_XXXXXXXXXXXXXXXXXXXX", time: "12m ago" },
    { type: "Email", color: COLORS.green, text: "billing-support@stripe.com", time: "1h ago" },
    { type: "Code", color: COLORS.mint, text: "stripe.charges.create({ amount: 2000 })", time: "2h ago" },
    { type: "JSON", color: COLORS.cyan, text: '{"id": "ch_3N", "object": "charge", ...}', time: "3h ago" },
  ];

  const speedIn = spring({ frame: frame - 50, fps, config: { damping: 10, stiffness: 200 } });

  const operators = [
    { op: "type:url", desc: "Filter by type" },
    { op: '"exact"', desc: "Exact match" },
    { op: "-exclude", desc: "Exclude term" },
    { op: "+required", desc: "Must include" },
  ];

  // Icons for result types
  const TypeIcons: Record<string, (c: string) => React.ReactNode> = {
    URL: (c) => (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
        <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
      </svg>
    ),
    "API Key": (c) => (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
      </svg>
    ),
    Email: (c) => (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
        <rect x="2" y="4" width="20" height="16" rx="2" />
        <path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7" />
      </svg>
    ),
    Code: (c) => (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="16 18 22 12 16 6" />
        <polyline points="8 6 2 12 8 18" />
      </svg>
    ),
    JSON: (c) => (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1" />
        <path d="M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1" />
      </svg>
    ),
  };

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        background: "#fafaf8",
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        fontFamily: FONTS.heading,
        position: "relative",
        overflow: "hidden",
        perspective: 800,
      }}
    >
      <SceneBg />
      <div style={{ display: "flex", gap: 40, alignItems: "flex-start", transform: `rotateY(${perspRotY}deg) rotateX(${perspRotX}deg)`, zIndex: 2 }}>
        <AppWindow title="Klippy — Search" width={820} height={560} opacity={windowIn} scale={0.9 + windowIn * 0.1}>
          <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
            {/* Search input */}
            <div style={{ padding: "16px", borderBottom: `1px solid ${COLORS.border}` }}>
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 10,
                  background: COLORS.surface,
                  borderRadius: 8,
                  padding: "12px 16px",
                  border: `1px solid ${COLORS.accent}40`,
                }}
              >
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={COLORS.accent} strokeWidth="2" strokeLinecap="round">
                  <circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" />
                </svg>
                <span style={{ fontSize: 19, color: COLORS.text, fontFamily: FONTS.mono, flex: 1 }}>
                  {displayedQuery}
                  {cursorVisible && typedChars < searchQuery.length && (
                    <span style={{ color: COLORS.accent }}>|</span>
                  )}
                </span>
                {typedChars >= searchQuery.length && (
                  <div
                    style={{
                      fontSize: 15,
                      color: COLORS.green,
                      background: `${COLORS.green}10`,
                      padding: "3px 10px",
                      borderRadius: 6,
                      fontFamily: FONTS.mono,
                      fontWeight: 600,
                      opacity: speedIn,
                      transform: `scale(${0.8 + speedIn * 0.2})`,
                    }}
                  >
                    8ms
                  </div>
                )}
              </div>
            </div>

            {/* Results count + type filter chips */}
            {typedChars >= searchQuery.length && (
              <div style={{ padding: "10px 16px", borderBottom: `1px solid ${COLORS.border}`, opacity: speedIn }}>
                <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 8 }}>
                  <span style={{ fontSize: 15, color: COLORS.dim }}>
                    <span style={{ color: COLORS.accent, fontWeight: 600 }}>1,247</span> results in{" "}
                    <span style={{ color: COLORS.green, fontWeight: 600 }}>8ms</span>
                  </span>
                </div>
                <div style={{ display: "flex", gap: 6 }}>
                  {["All", "URLs", "API Keys", "Emails", "Code", "JSON"].map((chip, ci) => {
                    const chipColors = [COLORS.text, COLORS.purple, COLORS.red, COLORS.green, COLORS.mint, COLORS.cyan];
                    return (
                      <div
                        key={chip}
                        style={{
                          padding: "3px 10px",
                          borderRadius: 10,
                          fontSize: 12,
                          fontWeight: 600,
                          background: ci === 0 ? COLORS.text : `${chipColors[ci]}10`,
                          color: ci === 0 ? COLORS.bg : chipColors[ci],
                          border: `1px solid ${ci === 0 ? COLORS.text : chipColors[ci]}25`,
                        }}
                      >
                        {chip}
                      </div>
                    );
                  })}
                </div>
              </div>
            )}

            {/* Results */}
            <div style={{ flex: 1, overflow: "hidden" }}>
              {SEARCH_RESULTS.map((result, i) => {
                const resultIn = spring({ frame: frame - 55 - i * 5, fps, config: { damping: 200 } });
                return (
                  <div
                    key={i}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      padding: "12px 16px",
                      gap: 12,
                      opacity: resultIn,
                      transform: `translateX(${(1 - resultIn) * 20}px)`,
                      borderBottom: `1px solid ${COLORS.border}`,
                    }}
                  >
                    {/* Type icon */}
                    <div
                      style={{
                        width: 34,
                        height: 34,
                        borderRadius: 8,
                        background: `${result.color}10`,
                        border: `1px solid ${result.color}20`,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        flexShrink: 0,
                      }}
                    >
                      {TypeIcons[result.type]?.(result.color)}
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 2 }}>
                        <span style={{ fontSize: 12, fontWeight: 700, color: result.color, textTransform: "uppercase", letterSpacing: 0.5 }}>
                          {result.type}
                        </span>
                      </div>
                      <div style={{ fontSize: 15, fontFamily: FONTS.mono, color: COLORS.text, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                        {result.text}
                      </div>
                    </div>
                    <span style={{ fontSize: 13, color: COLORS.dim, flexShrink: 0 }}>{result.time}</span>
                  </div>
                );
              })}
            </div>
          </div>
        </AppWindow>

        {/* Operators panel */}
        <div style={{ display: "flex", flexDirection: "column", gap: 12, paddingTop: 60 }}>
          <div style={{ fontSize: 16, color: COLORS.accent, fontWeight: 600, letterSpacing: 2, textTransform: "uppercase", marginBottom: 4, opacity: spring({ frame: frame - 40, fps, config: { damping: 200 } }) }}>
            Search Operators
          </div>
          {operators.map((op, i) => {
            const opIn = spring({ frame: frame - 50 - i * 8, fps, config: { damping: 200 } });
            return (
              <div key={op.op} style={{ display: "flex", alignItems: "center", gap: 12, opacity: opIn, transform: `translateX(${(1 - opIn) * 20}px)` }}>
                <code style={{ fontSize: 17, fontFamily: FONTS.mono, color: COLORS.accent, background: `${COLORS.accent}08`, padding: "4px 10px", borderRadius: 6, border: `1px solid ${COLORS.accent}20`, whiteSpace: "nowrap" }}>
                  {op.op}
                </code>
                <span style={{ fontSize: 16, color: COLORS.textSecondary }}>{op.desc}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
