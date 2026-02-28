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

// Scene 1 — The Hook (4s / 120 frames)
// Kinetic text: "YOUR CLIPBOARD" → "ONLY REMEMBERS" → "ONE" → subtitle

export const Scene1Hook: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Phase 1: "YOUR CLIPBOARD" (frames 3–34)
  const p1In = interpolate(frame, [3, 16], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const p1Out = interpolate(frame, [26, 34], [1, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.in(Easing.quad),
  });
  const p1Opacity = frame < 26 ? p1In : p1In * p1Out;
  const p1Blur = frame < 26 ? (1 - p1In) * 28 : (1 - p1Out) * 12;
  const p1Scale = frame < 26 ? 1 + (1 - p1In) * 0.06 : 1 + (1 - p1Out) * -0.03;
  const p1Y = frame < 26 ? (1 - p1In) * 18 : (1 - p1Out) * -10;

  // Phase 2: "ONLY REMEMBERS" (frames 30–58)
  const p2In = interpolate(frame, [30, 44], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const p2Out = interpolate(frame, [50, 58], [1, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.in(Easing.quad),
  });
  const p2Opacity = frame < 50 ? p2In : p2In * p2Out;
  const p2Blur = frame < 50 ? (1 - p2In) * 28 : (1 - p2Out) * 12;
  const p2Scale = frame < 50 ? 1 + (1 - p2In) * 0.06 : 1 + (1 - p2Out) * -0.03;
  const p2Y = frame < 50 ? (1 - p2In) * 18 : (1 - p2Out) * -10;

  // Phase 3: "ONE" — spring bounce, stays
  const oneSpring = spring({
    frame: frame - 55,
    fps,
    config: { damping: 8, stiffness: 100 },
  });
  const oneOpacity = interpolate(frame, [55, 66], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });
  const oneBlur = Math.max(0, (1 - oneSpring) * 35);
  const oneScale = 0.82 + oneSpring * 0.18;

  // Orange glow
  const glow = interpolate(frame, [72, 85], [0, 0.6], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });

  // Impact ring
  const ringProgress = interpolate(frame, [58, 88], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const ringOpacity = interpolate(frame, [58, 64, 88], [0, 0.25, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });

  // Burst particles
  const particles = Array.from({ length: 10 }, (_, i) => {
    const angle = (i / 10) * Math.PI * 2 + 0.3;
    const pProgress = interpolate(frame, [58, 82], [0, 1], {
      extrapolateRight: "clamp",
      extrapolateLeft: "clamp",
      easing: Easing.out(Easing.cubic),
    });
    const pOpacity = interpolate(frame, [58, 63, 82], [0, 0.5, 0], {
      extrapolateRight: "clamp",
      extrapolateLeft: "clamp",
    });
    const dist = pProgress * (200 + (i % 3) * 80);
    return {
      x: Math.cos(angle) * dist,
      y: Math.sin(angle) * dist * 0.6,
      opacity: pOpacity,
      size: 3 + (i % 3) * 2,
    };
  });

  // Subtitle
  const subIn = interpolate(frame, [88, 100], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const subBlur = (1 - subIn) * 10;

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
      }}
    >
      <SceneBg />

      {/* PHRASE 1: YOUR CLIPBOARD */}
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: `translate(-50%, -50%) scale(${p1Scale}) translateY(${p1Y}px)`,
          opacity: p1Opacity,
          filter: `blur(${p1Blur}px)`,
          zIndex: 3,
          whiteSpace: "nowrap",
        }}
      >
        <div
          style={{
            fontSize: 100,
            fontWeight: 800,
            color: COLORS.text,
            letterSpacing: 5,
            textTransform: "uppercase",
            lineHeight: 1,
          }}
        >
          Your Clipboard
        </div>
      </div>

      {/* PHRASE 2: ONLY REMEMBERS */}
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: `translate(-50%, -50%) scale(${p2Scale}) translateY(${p2Y}px)`,
          opacity: p2Opacity,
          filter: `blur(${p2Blur}px)`,
          zIndex: 3,
          whiteSpace: "nowrap",
        }}
      >
        <div
          style={{
            fontSize: 100,
            fontWeight: 800,
            color: COLORS.text,
            letterSpacing: 5,
            textTransform: "uppercase",
            lineHeight: 1,
          }}
        >
          Only Remembers
        </div>
      </div>

      {/* PHRASE 3: ONE */}
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: `translate(-50%, -50%) scale(${oneScale})`,
          opacity: oneOpacity,
          filter: `blur(${oneBlur}px)`,
          zIndex: 3,
        }}
      >
        <div
          style={{
            fontSize: 320,
            fontWeight: 900,
            color: COLORS.accent,
            letterSpacing: -10,
            lineHeight: 1,
            textShadow: `
              0 0 80px rgba(249,115,22,${glow}),
              0 0 200px rgba(249,115,22,${glow * 0.3})
            `,
          }}
        >
          ONE
        </div>
      </div>

      {/* Impact ring */}
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          width: 200,
          height: 200,
          borderRadius: "50%",
          border: `2px solid ${COLORS.accent}`,
          transform: `translate(-50%, -50%) scale(${0.5 + ringProgress * 3.5})`,
          opacity: ringOpacity,
          zIndex: 2,
        }}
      />

      {/* Burst particles */}
      {particles.map((p, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            top: "50%",
            left: "50%",
            width: p.size,
            height: p.size,
            borderRadius: "50%",
            background: COLORS.accent,
            transform: `translate(calc(-50% + ${p.x}px), calc(-50% + ${p.y}px))`,
            opacity: p.opacity,
            zIndex: 2,
          }}
        />
      ))}

      {/* Subtitle */}
      <div
        style={{
          position: "absolute",
          bottom: 180,
          zIndex: 3,
          opacity: subIn,
          filter: `blur(${subBlur}px)`,
          transform: `translateY(${(1 - subIn) * 10}px)`,
        }}
      >
        <span
          style={{
            fontSize: 32,
            color: COLORS.dim,
            letterSpacing: 2,
            fontWeight: 500,
            fontStyle: "italic",
          }}
        >
          There's a better way.
        </span>
      </div>
    </div>
  );
};
