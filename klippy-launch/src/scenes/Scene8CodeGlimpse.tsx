import React from "react";
import {
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  Img,
  staticFile,
  Easing,
} from "remotion";
import { COLORS, FONTS } from "../theme";
import { SceneBg } from "../components/SceneBg";

// Scene 8 — Klippy In Action (4s / 120 frames)
// Split screen: Chat on left, Klippy panel on right catching copied items

const CHAT_MESSAGES = [
  {
    sender: "Chris",
    memoji: "memoji-chris.png",
    text: "Here's the endpoint:",
    copyValue: "https://api.stripe.com/v1/charges",
    copyType: "URL",
    copyColor: COLORS.purple,
    msgFrame: 5,
    copyFrame: 18,
    clipFrame: 26,
  },
  {
    sender: "Francis",
    memoji: "memoji-francis.png",
    text: "Auth token for staging:",
    copyValue: "sk_test_XXXXXXXXXXXXXXX...",
    copyType: "API Key",
    copyColor: COLORS.red,
    msgFrame: 22,
    copyFrame: 40,
    clipFrame: 48,
  },
  {
    sender: "Chris",
    memoji: "memoji-chris.png",
    text: "New brand color:",
    copyValue: "#f97316",
    copyType: "Color",
    copyColor: COLORS.accent,
    msgFrame: 44,
    copyFrame: 58,
    clipFrame: 66,
  },
  {
    sender: "Francis",
    memoji: "memoji-francis.png",
    text: "Use this handler:",
    copyValue: "async (req) => res.json({ok: true})",
    copyType: "Code",
    copyColor: COLORS.mint,
    msgFrame: 62,
    copyFrame: 78,
    clipFrame: 86,
  },
];

// Giant macOS cursor for launch video — white fill with dark stroke
const MacCursor: React.FC<{ pressed?: boolean }> = ({ pressed }) => (
  <svg width={44} height={58} viewBox="0 0 22 29" fill="none">
    <path
      d="M1.5 1L1.5 23L6.5 18L12 27L15.5 25L10 16L17 16L1.5 1Z"
      fill="white"
      stroke="#1c1917"
      strokeWidth="1.8"
      strokeLinejoin="round"
    />
    {pressed && (
      <circle cx="6" cy="10" r="3" fill={COLORS.accent} opacity={0.5} />
    )}
  </svg>
);

// Cursor waypoints: absolute positions in 1920x1080 scene space
// Layout: panels centered. Left panel (840w) starts at x≈306, top at y≈180
// Chat padding 24px top 28px left. Avatar 48px + 14px gap → content at x≈396
// Each msg: name(20px)+mb5+text(20px)+mb8+value(31px) = ~84px, gap=22px
// Msg0 value center: y≈180+44+24+53 = 301   Msg1: 301+84+22+53 = 460 - wait let me recalc
// Actually: panel top=180, titlebar=44, padding=24 → y_start=248
// Msg0 value top = 248 + 20+5+20+8 = 301, center = 301+15 = 316
// Msg1 value top = 248 + 84+22 + 20+5+20+8 = 407, center = 422
// Msg2 value top = 248 + 84+22+84+22 + 53 = 513, center = 528
// Msg3 value top = 248 + 84+22+84+22+84+22 + 53 = 619, center = 634
const CURSOR_POSITIONS = [
  { frame: 0, x: 400, y: 260 },     // start neutral
  { frame: 14, x: 540, y: 316 },    // arrive at item 0 value
  { frame: 18, x: 540, y: 316 },    // click item 0
  { frame: 28, x: 540, y: 316 },    // hold
  { frame: 36, x: 530, y: 422 },    // arrive at item 1
  { frame: 40, x: 530, y: 422 },    // click item 1
  { frame: 50, x: 530, y: 422 },    // hold
  { frame: 54, x: 510, y: 528 },    // arrive at item 2
  { frame: 58, x: 510, y: 528 },    // click item 2
  { frame: 66, x: 510, y: 528 },    // hold
  { frame: 73, x: 540, y: 650 },    // arrive at item 3
  { frame: 78, x: 540, y: 650 },    // click item 3
  { frame: 90, x: 540, y: 650 },    // hold
  { frame: 105, x: 700, y: 480 },   // drift away
];

// Type icon SVGs
const TypeIcons: Record<string, (c: string) => React.ReactNode> = {
  URL: (c) => (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
  ),
  "API Key": (c) => (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" />
    </svg>
  ),
  Color: (c) => (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="13.5" cy="6.5" r="2.5" />
      <circle cx="17.5" cy="10.5" r="2.5" />
      <circle cx="8.5" cy="7.5" r="2.5" />
      <circle cx="6.5" cy="12.5" r="2.5" />
      <path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z" />
    </svg>
  ),
  Code: (c) => (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="16 18 22 12 16 6" />
      <polyline points="8 6 2 12 8 18" />
    </svg>
  ),
};

export const Scene8CodeGlimpse: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const panelLeftIn = spring({ frame, fps, config: { damping: 15, stiffness: 100 } });
  const panelRightIn = spring({ frame: frame - 5, fps, config: { damping: 15, stiffness: 100 } });

  // Perspective entrance — settles to visible tilt
  const perspRotY = interpolate(frame, [0, 35], [-20, -10], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const perspRotX = interpolate(frame, [0, 35], [10, 5], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // Count of captured items
  const capturedCount = CHAT_MESSAGES.filter((m) => frame >= m.clipFrame + 8).length;

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

      {/* Giant animated macOS cursor */}
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

        const cursorOpacity = interpolate(frame, [0, 8, 100, 115], [0, 1, 1, 0], {
          extrapolateRight: "clamp",
          extrapolateLeft: "clamp",
        });

        // Click frames + press animation
        const clickFrames = [18, 40, 58, 78];
        const isPressed = clickFrames.some(
          (cf) => frame >= cf && frame < cf + 4
        );
        const cursorScale = isPressed ? 0.85 : 1;

        return (
          <>
            {/* Click ripples — dual ring + filled circle */}
            {clickFrames.map((cf, ci) => {
              if (frame < cf || frame > cf + 14) return null;

              const rippleX = interpolate(cf, wpFrames, xs, {
                extrapolateRight: "clamp",
                extrapolateLeft: "clamp",
              });
              const rippleY = interpolate(cf, wpFrames, ys, {
                extrapolateRight: "clamp",
                extrapolateLeft: "clamp",
              });

              // Inner filled dot
              const dotOpacity = interpolate(
                frame, [cf, cf + 2, cf + 8], [0, 0.5, 0],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );
              // Outer expanding ring
              const ringProgress = interpolate(
                frame, [cf, cf + 12], [0, 1],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );
              const ringOpacity = interpolate(
                frame, [cf, cf + 3, cf + 12], [0, 0.6, 0],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );
              // Second ring (slightly delayed)
              const ring2Progress = interpolate(
                frame, [cf + 3, cf + 14], [0, 1],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );
              const ring2Opacity = interpolate(
                frame, [cf + 3, cf + 5, cf + 14], [0, 0.35, 0],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );

              return (
                <React.Fragment key={ci}>
                  {/* Filled click dot */}
                  <div
                    style={{
                      position: "absolute",
                      left: rippleX,
                      top: rippleY,
                      width: 20,
                      height: 20,
                      borderRadius: "50%",
                      background: COLORS.accent,
                      opacity: dotOpacity,
                      transform: "translate(-50%, -50%)",
                      zIndex: 100,
                      pointerEvents: "none",
                    }}
                  />
                  {/* Ring 1 */}
                  <div
                    style={{
                      position: "absolute",
                      left: rippleX,
                      top: rippleY,
                      width: 30 + ringProgress * 50,
                      height: 30 + ringProgress * 50,
                      borderRadius: "50%",
                      border: `3px solid ${COLORS.accent}`,
                      opacity: ringOpacity,
                      transform: "translate(-50%, -50%)",
                      zIndex: 100,
                      pointerEvents: "none",
                    }}
                  />
                  {/* Ring 2 */}
                  <div
                    style={{
                      position: "absolute",
                      left: rippleX,
                      top: rippleY,
                      width: 20 + ring2Progress * 70,
                      height: 20 + ring2Progress * 70,
                      borderRadius: "50%",
                      border: `2px solid ${COLORS.accent}60`,
                      opacity: ring2Opacity,
                      transform: "translate(-50%, -50%)",
                      zIndex: 100,
                      pointerEvents: "none",
                    }}
                  />
                </React.Fragment>
              );
            })}

            {/* Giant cursor */}
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
                transition: "transform 0.08s ease-out",
              }}
            >
              <MacCursor pressed={isPressed} />
            </div>
          </>
        );
      })()}

      <div style={{ display: "flex", gap: 28, alignItems: "center", zIndex: 2, transform: `rotateY(${perspRotY}deg) rotateX(${perspRotX}deg)` }}>
        {/* LEFT — Chat Window */}
        <div
          style={{
            width: 840,
            height: 720,
            borderRadius: 14,
            overflow: "hidden",
            background: COLORS.bg,
            border: `1px solid ${COLORS.border}`,
            boxShadow: "0 20px 60px rgba(0,0,0,0.1), 0 4px 16px rgba(0,0,0,0.06)",
            display: "flex",
            flexDirection: "column",
            opacity: panelLeftIn,
            transform: `translateX(${(1 - panelLeftIn) * -40}px)`,
            flexShrink: 0,
          }}
        >
          {/* Chat title bar */}
          <div
            style={{
              height: 44,
              background: COLORS.surface,
              borderBottom: `1px solid ${COLORS.border}`,
              display: "flex",
              alignItems: "center",
              paddingLeft: 16,
              gap: 8,
            }}
          >
            <div style={{ display: "flex", gap: 8 }}>
              <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#ff5f57" }} />
              <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#febc2e" }} />
              <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#28c840" }} />
            </div>
            <div style={{ flex: 1, textAlign: "center", fontSize: 14, fontWeight: 600, color: COLORS.muted }}>
              #engineering
            </div>
            <div style={{ width: 60 }} />
          </div>

          {/* Chat messages */}
          <div style={{ flex: 1, padding: "24px 28px", display: "flex", flexDirection: "column", gap: 22 }}>
            {CHAT_MESSAGES.map((msg, i) => {
              const msgIn = spring({ frame: frame - msg.msgFrame, fps, config: { damping: 20, stiffness: 120 } });

              // Selection highlight
              const selectionProgress = interpolate(
                frame, [msg.copyFrame, msg.copyFrame + 6], [0, 1],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );
              const isSelecting = frame >= msg.copyFrame && frame < msg.copyFrame + 10;

              // "Copied!" flash
              const copiedFlash = frame >= msg.copyFrame + 4 && frame < msg.copyFrame + 16;
              const copiedOpacity = interpolate(
                frame, [msg.copyFrame + 4, msg.copyFrame + 7, msg.copyFrame + 13, msg.copyFrame + 16], [0, 1, 1, 0],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );

              return (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    gap: 14,
                    opacity: msgIn,
                    transform: `translateY(${(1 - msgIn) * 20}px)`,
                  }}
                >
                  {/* Avatar — Memoji */}
                  <div
                    style={{
                      width: 48,
                      height: 48,
                      borderRadius: 14,
                      overflow: "hidden",
                      flexShrink: 0,
                      background: COLORS.surface,
                      border: `1px solid ${COLORS.border}`,
                    }}
                  >
                    <Img
                      src={staticFile(msg.memoji)}
                      style={{
                        width: "100%",
                        height: "100%",
                        objectFit: "cover",
                      }}
                    />
                  </div>

                  <div style={{ flex: 1 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 5 }}>
                      <span style={{ fontSize: 17, fontWeight: 700, color: COLORS.text }}>{msg.sender}</span>
                      <span style={{ fontSize: 13, color: COLORS.dim }}>just now</span>
                    </div>
                    <div style={{ fontSize: 17, color: COLORS.textSecondary, marginBottom: 8 }}>
                      {msg.text}
                    </div>

                    {/* Copyable value */}
                    <div style={{ position: "relative", display: "inline-block" }}>
                      <div
                        style={{
                          fontSize: 15,
                          fontFamily: FONTS.mono,
                          color: msg.copyColor,
                          background: `${msg.copyColor}08`,
                          border: `1px solid ${msg.copyColor}20`,
                          padding: "8px 16px",
                          borderRadius: 10,
                          position: "relative",
                          overflow: "hidden",
                        }}
                      >
                        {/* Selection sweep */}
                        {isSelecting && (
                          <div
                            style={{
                              position: "absolute",
                              top: 0,
                              left: 0,
                              height: "100%",
                              width: `${selectionProgress * 100}%`,
                              background: `${msg.copyColor}18`,
                              borderRadius: 10,
                            }}
                          />
                        )}
                        {msg.copyValue}
                      </div>

                      {/* Copied badge */}
                      {copiedFlash && (
                        <div
                          style={{
                            position: "absolute",
                            top: -10,
                            right: -12,
                            background: COLORS.text,
                            color: COLORS.bg,
                            fontSize: 12,
                            fontWeight: 700,
                            padding: "4px 12px",
                            borderRadius: 8,
                            opacity: copiedOpacity,
                            transform: `scale(${0.8 + copiedOpacity * 0.2})`,
                            letterSpacing: 0.5,
                            display: "flex",
                            alignItems: "center",
                            gap: 4,
                            boxShadow: "0 2px 8px rgba(0,0,0,0.15)",
                          }}
                        >
                          <span style={{ fontSize: 11 }}>⌘C</span>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* RIGHT — Klippy Panel */}
        <div
          style={{
            width: 440,
            height: 720,
            borderRadius: 14,
            overflow: "hidden",
            background: COLORS.bg,
            border: `1px solid ${COLORS.border}`,
            boxShadow: "0 20px 60px rgba(0,0,0,0.1), 0 4px 16px rgba(0,0,0,0.06)",
            display: "flex",
            flexDirection: "column",
            opacity: panelRightIn,
            transform: `translateX(${(1 - panelRightIn) * 40}px)`,
            flexShrink: 0,
          }}
        >
          {/* Header */}
          <div
            style={{
              height: 52,
              background: COLORS.surface,
              borderBottom: `1px solid ${COLORS.border}`,
              display: "flex",
              alignItems: "center",
              paddingLeft: 18,
              paddingRight: 18,
            }}
          >
            {/* Klippy icon */}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={COLORS.accent} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="8" y="2" width="8" height="4" rx="1" ry="1" />
              <path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2" />
              <path d="m9 14 2 2 4-4" />
            </svg>
            <span style={{ fontSize: 16, fontWeight: 700, color: COLORS.text, marginLeft: 10 }}>
              Klippy
            </span>
            <div style={{ flex: 1 }} />
            <div
              style={{
                fontSize: 13,
                fontFamily: FONTS.mono,
                color: COLORS.accent,
                background: `${COLORS.accent}10`,
                padding: "4px 12px",
                borderRadius: 12,
                fontWeight: 700,
                border: `1px solid ${COLORS.accent}20`,
              }}
            >
              {capturedCount} captured
            </div>
          </div>

          {/* Captured items */}
          <div style={{ flex: 1, padding: "14px 16px", display: "flex", flexDirection: "column", gap: 12 }}>
            {CHAT_MESSAGES.map((msg, i) => {
              const itemIn = spring({
                frame: frame - msg.clipFrame,
                fps,
                config: { damping: 12, stiffness: 150 },
              });

              // Glow on arrival
              const glowOpacity = interpolate(
                frame, [msg.clipFrame, msg.clipFrame + 5, msg.clipFrame + 20], [0, 0.5, 0],
                { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
              );

              if (frame < msg.clipFrame) return null;

              return (
                <div
                  key={i}
                  style={{
                    padding: "16px 18px",
                    borderRadius: 12,
                    background: COLORS.bg,
                    border: `1px solid ${COLORS.border}`,
                    opacity: itemIn,
                    transform: `scale(${0.85 + itemIn * 0.15}) translateY(${(1 - itemIn) * 10}px)`,
                    position: "relative",
                    overflow: "hidden",
                    boxShadow: "0 2px 10px rgba(0,0,0,0.04)",
                  }}
                >
                  {/* Arrival glow */}
                  <div
                    style={{
                      position: "absolute",
                      inset: -1,
                      borderRadius: 12,
                      border: `2px solid ${msg.copyColor}`,
                      opacity: glowOpacity,
                    }}
                  />
                  <div
                    style={{
                      position: "absolute",
                      inset: 0,
                      background: `linear-gradient(135deg, ${msg.copyColor}12, transparent)`,
                      opacity: glowOpacity,
                      borderRadius: 12,
                    }}
                  />

                  <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 8 }}>
                    {/* Type icon + badge */}
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 6,
                        fontSize: 11,
                        fontWeight: 700,
                        color: msg.copyColor,
                        background: `${msg.copyColor}10`,
                        padding: "3px 10px",
                        borderRadius: 8,
                        letterSpacing: 0.5,
                        textTransform: "uppercase",
                        border: `1px solid ${msg.copyColor}15`,
                      }}
                    >
                      {TypeIcons[msg.copyType]?.(msg.copyColor)}
                      {msg.copyType}
                    </div>
                    <div style={{ flex: 1 }} />
                    <span style={{ fontSize: 12, color: COLORS.dim }}>just now</span>
                  </div>

                  <div
                    style={{
                      fontSize: 14,
                      fontFamily: FONTS.mono,
                      color: COLORS.text,
                      whiteSpace: "nowrap",
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                    }}
                  >
                    {msg.copyValue}
                  </div>

                  {/* Color swatch preview */}
                  {msg.copyType === "Color" && (
                    <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 10 }}>
                      <div
                        style={{
                          width: 24,
                          height: 24,
                          borderRadius: 6,
                          background: msg.copyValue,
                          border: `1px solid ${COLORS.border}`,
                          boxShadow: `0 2px 8px ${msg.copyValue}40`,
                        }}
                      />
                      <span style={{ fontSize: 12, color: COLORS.dim }}>Preview</span>
                    </div>
                  )}
                </div>
              );
            })}

            {/* Empty state */}
            {frame < CHAT_MESSAGES[0].clipFrame && (
              <div
                style={{
                  flex: 1,
                  display: "flex",
                  flexDirection: "column",
                  justifyContent: "center",
                  alignItems: "center",
                  gap: 14,
                  opacity: 0.35,
                }}
              >
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke={COLORS.dim} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <rect x="8" y="2" width="8" height="4" rx="1" ry="1" />
                  <path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2" />
                </svg>
                <span style={{ fontSize: 16, color: COLORS.dim }}>Watching clipboard...</span>
              </div>
            )}
          </div>

          {/* Bottom bar */}
          <div
            style={{
              padding: "12px 18px",
              borderTop: `1px solid ${COLORS.border}`,
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            <span style={{ fontSize: 13, color: COLORS.dim }}>100% Local</span>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <div style={{ width: 7, height: 7, borderRadius: "50%", background: "#22c55e" }} />
              <span style={{ fontSize: 13, color: COLORS.dim }}>Active</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
