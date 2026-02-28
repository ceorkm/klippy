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

// Scene 3 — Menu Bar App (5s / 150 frames)

// Type icons for clipboard items
const TypeIcons: Record<string, (c: string) => React.ReactNode> = {
  URL: (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
  ),
  Code: (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="16 18 22 12 16 6" />
      <polyline points="8 6 2 12 8 18" />
    </svg>
  ),
  Email: (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7" />
    </svg>
  ),
  "API Key": (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
    </svg>
  ),
  JSON: (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1" />
      <path d="M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1" />
    </svg>
  ),
  Phone: (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z" />
    </svg>
  ),
  Address: (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z" />
      <circle cx="12" cy="10" r="3" />
    </svg>
  ),
  Color: (c) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="13.5" cy="6.5" r="2.5" />
      <circle cx="17.5" cy="10.5" r="2.5" />
      <circle cx="8.5" cy="7.5" r="2.5" />
      <circle cx="6.5" cy="12.5" r="2.5" />
      <path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z" />
    </svg>
  ),
};

// Giant macOS cursor for launch video
const MacCursor: React.FC<{ pressed?: boolean }> = ({ pressed }) => (
  <svg width={44} height={58} viewBox="0 0 22 29" fill="none">
    <path
      d="M1.5 1L1.5 23L6.5 18L12 27L15.5 25L10 16L17 16L1.5 1Z"
      fill="white"
      stroke="#1c1917"
      strokeWidth="1.8"
      strokeLinejoin="round"
    />
  </svg>
);

// Cursor waypoints — browse items then click the pinned URL
// AppWindow (1100x620) centered at x=410 y=230. Items start ~y=395
const CURSOR_POSITIONS = [
  { frame: 0, x: 700, y: 290 },     // start near search bar
  { frame: 35, x: 700, y: 290 },    // hold at search bar
  { frame: 50, x: 650, y: 460 },    // browse to item 1 (Code)
  { frame: 62, x: 620, y: 520 },    // browse to item 2 (Email)
  { frame: 74, x: 640, y: 575 },    // browse to item 3 (API Key)
  { frame: 85, x: 620, y: 405 },    // back up to item 0 (URL)
  { frame: 90, x: 620, y: 405 },    // hover on item 0
  { frame: 95, x: 620, y: 405 },    // click item 0
  { frame: 115, x: 620, y: 405 },   // hold
  { frame: 130, x: 750, y: 350 },   // drift away
];

const CLIPBOARD_ITEMS = [
  { type: "URL", color: COLORS.purple, text: "https://github.com/klippy-app", time: "Just now" },
  { type: "Code", color: COLORS.mint, text: "func handleClipboard() -> Bool {", time: "2m ago" },
  { type: "Email", color: COLORS.green, text: "team@klippy.dev", time: "5m ago" },
  { type: "API Key", color: COLORS.red, text: "sk-proj-a8f3k2nB7x...", time: "12m ago" },
  { type: "JSON", color: COLORS.cyan, text: '{"status": "success", "data": [...]}', time: "15m ago" },
  { type: "Phone", color: COLORS.blue, text: "+1 (415) 555-0132", time: "23m ago" },
  { type: "Address", color: COLORS.pink, text: "1 Infinite Loop, Cupertino, CA", time: "1h ago" },
  { type: "Color", color: COLORS.accent, text: "#f97316", time: "2h ago" },
];

export const Scene3MenuBar: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const menuBarIn = spring({ frame, fps, config: { damping: 200 } });

  // Perspective entrance — dramatic tilt, flattens before cursor at frame 25
  const perspRotY = interpolate(frame, [0, 28], [-25, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const perspRotX = interpolate(frame, [0, 28], [12, 0], {
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
        justifyContent: "center",
        alignItems: "center",
        fontFamily: FONTS.heading,
        position: "relative",
        overflow: "hidden",
        perspective: 800,
      }}
    >
      <SceneBg />
      <div style={{ position: "absolute", inset: 0, transform: `rotateY(${perspRotY}deg) rotateX(${perspRotX}deg)`, zIndex: 2 }}>
      <AppWindow
        title="Klippy — Clipboard Manager"
        width={1100}
        height={620}
        opacity={menuBarIn}
        scale={0.9 + menuBarIn * 0.1}
      >
        <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column" }}>
          {/* Search bar */}
          <div style={{ padding: "12px 16px", borderBottom: `1px solid ${COLORS.border}` }}>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                background: COLORS.surface,
                borderRadius: 8,
                padding: "10px 14px",
                border: `1px solid ${COLORS.border}`,
              }}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={COLORS.dim} strokeWidth="2" strokeLinecap="round">
                <circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" />
              </svg>
              <span style={{ fontSize: 17, color: COLORS.dim, fontFamily: FONTS.mono }}>
                Search clipboard history...
              </span>
              <div style={{ flex: 1 }} />
              <span
                style={{
                  fontSize: 14,
                  color: COLORS.dim,
                  background: COLORS.bg,
                  padding: "2px 8px",
                  borderRadius: 4,
                  border: `1px solid ${COLORS.border}`,
                }}
              >
                ⌘K
              </span>
            </div>
          </div>

          {/* Category filters */}
          <div style={{ padding: "8px 16px", display: "flex", gap: 6, borderBottom: `1px solid ${COLORS.border}` }}>
            {["All", "URLs", "Code", "Emails", "API Keys", "JSON", "Files"].map((cat, i) => {
              const catIn = spring({ frame: frame - 30 - i * 3, fps, config: { damping: 200 } });
              return (
                <div
                  key={cat}
                  style={{
                    padding: "4px 12px",
                    borderRadius: 12,
                    fontSize: 15,
                    fontWeight: 500,
                    background: i === 0 ? COLORS.text : COLORS.surface,
                    color: i === 0 ? COLORS.bg : COLORS.muted,
                    border: `1px solid ${i === 0 ? COLORS.text : COLORS.border}`,
                    opacity: catIn,
                    transform: `scale(${0.8 + catIn * 0.2})`,
                  }}
                >
                  {cat}
                </div>
              );
            })}
          </div>

          {/* Clipboard items */}
          <div style={{ flex: 1, overflow: "hidden", padding: "4px 0" }}>
            {CLIPBOARD_ITEMS.map((item, i) => {
              const itemIn = spring({ frame: frame - 40 - i * 5, fps, config: { damping: 200 } });
              const isHovered = frame > 90 && frame < 120 && i === 0;

              return (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    padding: "10px 16px",
                    gap: 12,
                    opacity: itemIn,
                    transform: `translateX(${(1 - itemIn) * 30}px)`,
                    background: isHovered ? COLORS.surface : "transparent",
                    borderLeft: isHovered ? `3px solid ${COLORS.accent}` : "3px solid transparent",
                  }}
                >
                  {/* Type icon */}
                  <div
                    style={{
                      width: 36,
                      height: 36,
                      borderRadius: 8,
                      background: `${item.color}12`,
                      border: `1px solid ${item.color}25`,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      flexShrink: 0,
                    }}
                  >
                    {TypeIcons[item.type]?.(item.color) ?? (
                      <div style={{ width: 10, height: 10, borderRadius: "50%", background: item.color }} />
                    )}
                  </div>

                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 2 }}>
                      <span style={{ fontSize: 14, fontWeight: 600, color: item.color, textTransform: "uppercase", letterSpacing: 0.5 }}>
                        {item.type}
                      </span>
                      {i === 0 && (
                        <span style={{ fontSize: 12, color: COLORS.accent, background: `${COLORS.accent}10`, padding: "1px 6px", borderRadius: 4, fontWeight: 600 }}>
                          Pinned
                        </span>
                      )}
                    </div>
                    <div style={{ fontSize: 16, color: COLORS.text, fontFamily: FONTS.mono, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                      {item.text}
                    </div>
                  </div>

                  <div style={{ fontSize: 14, color: COLORS.dim, flexShrink: 0 }}>{item.time}</div>
                </div>
              );
            })}
          </div>

          {/* Bottom bar */}
          <div style={{ padding: "8px 16px", borderTop: `1px solid ${COLORS.border}`, display: "flex", justifyContent: "space-between" }}>
            <span style={{ fontSize: 14, color: COLORS.dim }}>3,247,891 items</span>
            <span style={{ fontSize: 14, color: COLORS.dim }}>Klippy v1.0 — 100% Local</span>
          </div>
        </div>
      </AppWindow>
      </div>

      {/* Giant animated cursor */}
      {(() => {
        const wpFrames = CURSOR_POSITIONS.map((p) => p.frame);
        const xs = CURSOR_POSITIONS.map((p) => p.x);
        const ys = CURSOR_POSITIONS.map((p) => p.y);

        const cursorX = interpolate(frame, wpFrames, xs, {
          extrapolateRight: "clamp",
          extrapolateLeft: "clamp",
        });
        const cursorY = interpolate(frame, wpFrames, ys, {
          extrapolateRight: "clamp",
          extrapolateLeft: "clamp",
        });

        const cursorOpacity = interpolate(frame, [25, 35, 125, 140], [0, 1, 1, 0], {
          extrapolateRight: "clamp",
          extrapolateLeft: "clamp",
        });

        // Click at frame 95
        const isPressed = frame >= 95 && frame < 99;
        const cursorScale = isPressed ? 0.85 : 1;

        // Click ripple
        const clickFrame = 95;
        const showRipple = frame >= clickFrame && frame < clickFrame + 14;

        return (
          <>
            {showRipple && (() => {
              const rippleX = interpolate(clickFrame, wpFrames, xs, {
                extrapolateRight: "clamp",
                extrapolateLeft: "clamp",
              });
              const rippleY = interpolate(clickFrame, wpFrames, ys, {
                extrapolateRight: "clamp",
                extrapolateLeft: "clamp",
              });

              const dotOpacity = interpolate(
                frame, [clickFrame, clickFrame + 2, clickFrame + 8], [0, 0.5, 0],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );
              const ringProgress = interpolate(
                frame, [clickFrame, clickFrame + 12], [0, 1],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );
              const ringOpacity = interpolate(
                frame, [clickFrame, clickFrame + 3, clickFrame + 12], [0, 0.6, 0],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );
              const ring2Progress = interpolate(
                frame, [clickFrame + 3, clickFrame + 14], [0, 1],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );
              const ring2Opacity = interpolate(
                frame, [clickFrame + 3, clickFrame + 5, clickFrame + 14], [0, 0.35, 0],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );

              return (
                <>
                  <div style={{ position: "absolute", left: rippleX, top: rippleY, width: 20, height: 20, borderRadius: "50%", background: COLORS.accent, opacity: dotOpacity, transform: "translate(-50%, -50%)", zIndex: 100, pointerEvents: "none" }} />
                  <div style={{ position: "absolute", left: rippleX, top: rippleY, width: 30 + ringProgress * 50, height: 30 + ringProgress * 50, borderRadius: "50%", border: `3px solid ${COLORS.accent}`, opacity: ringOpacity, transform: "translate(-50%, -50%)", zIndex: 100, pointerEvents: "none" }} />
                  <div style={{ position: "absolute", left: rippleX, top: rippleY, width: 20 + ring2Progress * 70, height: 20 + ring2Progress * 70, borderRadius: "50%", border: `2px solid ${COLORS.accent}60`, opacity: ring2Opacity, transform: "translate(-50%, -50%)", zIndex: 100, pointerEvents: "none" }} />
                </>
              );
            })()}

            <div
              style={{
                position: "absolute",
                left: cursorX,
                top: cursorY,
                zIndex: 101,
                pointerEvents: "none",
                opacity: cursorOpacity,
                transform: `scale(${cursorScale})`,
                transformOrigin: "top left",
                filter: "drop-shadow(0 4px 12px rgba(0,0,0,0.35)) drop-shadow(0 1px 3px rgba(0,0,0,0.2))",
              }}
            >
              <MacCursor pressed={isPressed} />
            </div>
          </>
        );
      })()}
    </div>
  );
};
