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

// Scene 9 — GitHub CTA (4.5s / 135 frames)

export const Scene9CTA: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const labelIn = spring({ frame, fps, config: { damping: 200 } });
  const logoScale = spring({ frame: frame - 15, fps, config: { damping: 10, stiffness: 120 } });

  const githubRotation = interpolate(frame, [25, 55], [-180, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });
  const githubScale = spring({ frame: frame - 25, fps, config: { damping: 10, stiffness: 150 } });

  const ctaIn = spring({ frame: frame - 50, fps, config: { damping: 200 } });
  const urlIn = spring({ frame: frame - 65, fps, config: { damping: 200 } });

  const labelBlur = interpolate(frame, [0, 16], [10, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const ctaBlur = interpolate(frame, [50, 65], [12, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const urlBlur = interpolate(frame, [65, 78], [8, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // Perspective
  const perspRotX = interpolate(frame, [0, 35], [14, 6], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const pulseScale = interpolate(
    frame, [70, 80, 90, 100, 110, 120, 135], [1, 1.08, 1, 1.05, 1, 1.03, 1],
    { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
  );

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

      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", transform: `rotateX(${perspRotX}deg)`, width: "100%", flex: 1, zIndex: 2 }}>
      {/* "100% OPEN SOURCE" label */}
      <div
        style={{
          fontSize: 18,
          fontWeight: 700,
          letterSpacing: 4,
          color: COLORS.accent,
          background: `${COLORS.accent}08`,
          padding: "8px 24px",
          borderRadius: 20,
          border: `1px solid ${COLORS.accent}20`,
          marginBottom: 30,
          opacity: labelIn,
          transform: `scale(${0.8 + labelIn * 0.2})`,
          filter: `blur(${labelBlur}px)`,
          zIndex: 2,
        }}
      >
        100% OPEN SOURCE
      </div>

      {/* Klippy logo */}
      <div style={{ marginBottom: 20, zIndex: 2 }}>
        <Img
          src={staticFile("klippy-icon.png")}
          style={{
            width: 420,
            height: "auto",
            transform: `scale(${logoScale})`,
          }}
        />
      </div>

      {/* GitHub icon */}
      <div style={{ marginBottom: 20, transform: `rotate(${githubRotation}deg) scale(${githubScale})`, zIndex: 2 }}>
        <svg width="60" height="60" viewBox="0 0 24 24" fill={COLORS.text}>
          <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
        </svg>
      </div>

      {/* CTA text */}
      <div
        style={{
          fontSize: 52,
          fontWeight: 800,
          color: COLORS.text,
          marginBottom: 16,
          opacity: ctaIn,
          transform: `scale(${pulseScale}) translateY(${(1 - ctaIn) * 15}px)`,
          filter: `blur(${ctaBlur}px)`,
          zIndex: 2,
        }}
      >
        Star us on GitHub
      </div>

      {/* URL card */}
      <div
        style={{
          padding: "12px 28px",
          borderRadius: 10,
          background: COLORS.surface,
          border: `1px solid ${COLORS.border}`,
          opacity: urlIn,
          transform: `translateY(${(1 - urlIn) * 10}px)`,
          filter: `blur(${urlBlur}px)`,
          zIndex: 2,
        }}
      >
        <span style={{ fontSize: 26, fontFamily: FONTS.mono, color: COLORS.textSecondary }}>
          github.com/<span style={{ color: COLORS.accent, fontWeight: 700 }}>ceorkm/klippy</span>
        </span>
      </div>
      </div>
    </div>
  );
};
