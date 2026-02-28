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

// Scene 2 — Logo Reveal (4s / 120 frames)

export const Scene2LogoReveal: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Converging lines
  const lineProgress = interpolate(frame, [0, 40], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const linesFadeOut = interpolate(frame, [35, 55], [1, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });

  // Dual burst rings
  const burst1Scale = spring({ frame: frame - 30, fps, config: { damping: 12, stiffness: 100 } });
  const burst1Opacity = interpolate(frame, [30, 42, 65], [0, 0.45, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });
  const burst2Scale = spring({ frame: frame - 35, fps, config: { damping: 14, stiffness: 80 } });
  const burst2Opacity = interpolate(frame, [35, 48, 72], [0, 0.25, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });

  // Logo — blur-to-sharp
  const logoScale = spring({ frame: frame - 38, fps, config: { damping: 10, stiffness: 120 } });
  const logoOpacity = interpolate(frame, [38, 52], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });
  const logoBlur = interpolate(frame, [38, 56], [18, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // Warm glow behind logo
  const glowOpacity = interpolate(frame, [42, 62], [0, 0.45], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });
  const glowPulse = 1 + Math.sin(frame * 0.05) * 0.04;

  // Name — blur reveal
  const nameIn = spring({ frame: frame - 58, fps, config: { damping: 200 } });
  const nameBlur = interpolate(frame, [58, 72], [12, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // Tagline — blur reveal
  const taglineIn = spring({ frame: frame - 72, fps, config: { damping: 200 } });
  const taglineBlur = interpolate(frame, [72, 85], [8, 0], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // Burst particles
  const particles = Array.from({ length: 14 }, (_, i) => ({
    x: Math.sin(i * 1.1 + 0.5) * (300 + (i % 4) * 60),
    y: Math.cos(i * 0.8 + 0.3) * (200 + (i % 3) * 50),
    size: 4 + (i % 4) * 2,
    delay: i * 2.5,
  }));

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

      {/* Converging lines */}
      {[0, 45, 90, 135, 180, 225, 270, 315].map((angle, i) => {
        const lineLen = interpolate(lineProgress, [0, 1], [600, 0]);
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              top: "50%",
              left: "50%",
              width: 3,
              height: lineLen,
              background: `linear-gradient(to bottom, transparent, ${COLORS.accent}90)`,
              transform: `rotate(${angle}deg) translateY(-${160 + lineLen}px)`,
              opacity: lineProgress * 0.5 * linesFadeOut,
              zIndex: 2,
            }}
          />
        );
      })}

      {/* Burst ring 1 */}
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: `translate(-50%, -50%) scale(${burst1Scale * 3.5})`,
          width: 200,
          height: 200,
          borderRadius: "50%",
          border: `2.5px solid ${COLORS.accent}`,
          opacity: burst1Opacity,
          zIndex: 2,
        }}
      />

      {/* Burst ring 2 */}
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: `translate(-50%, -50%) scale(${burst2Scale * 2.5})`,
          width: 200,
          height: 200,
          borderRadius: "50%",
          border: `1.5px solid ${COLORS.accent}`,
          opacity: burst2Opacity,
          zIndex: 2,
        }}
      />

      {/* Burst particles */}
      {particles.map((p, i) => {
        const pProgress = spring({
          frame: frame - 32 - p.delay,
          fps,
          config: { damping: 18 },
        });
        const pFade = interpolate(
          frame,
          [32 + p.delay, 40 + p.delay, 85 + p.delay],
          [0, 0.45, 0.1],
          { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
        );
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              top: "50%",
              left: "50%",
              transform: `translate(${p.x * pProgress}px, ${p.y * pProgress}px)`,
              width: p.size,
              height: p.size,
              borderRadius: "50%",
              background: COLORS.accent,
              opacity: pFade,
              zIndex: 2,
            }}
          />
        );
      })}

      {/* Orange glow behind logo */}
      <div
        style={{
          position: "absolute",
          top: "42%",
          left: "50%",
          transform: `translate(-50%, -50%) scale(${glowPulse})`,
          width: 550,
          height: 550,
          borderRadius: "50%",
          background: `radial-gradient(circle,
            rgba(249,115,22,${glowOpacity * 0.15}) 0%,
            rgba(249,115,22,${glowOpacity * 0.06}) 35%,
            transparent 65%
          )`,
          zIndex: 2,
        }}
      />

      {/* Logo — blur-to-sharp */}
      <div
        style={{
          transform: `scale(${logoScale})`,
          opacity: logoOpacity,
          filter: `blur(${logoBlur}px)`,
          zIndex: 3,
          marginBottom: 20,
        }}
      >
        <Img
          src={staticFile("klippy-icon.png")}
          style={{ width: 500, height: "auto" }}
        />
      </div>

      {/* App name */}
      <div
        style={{
          fontSize: 100,
          fontWeight: 800,
          color: COLORS.text,
          letterSpacing: -2,
          zIndex: 3,
          opacity: nameIn,
          filter: `blur(${nameBlur}px)`,
          transform: `translateY(${(1 - nameIn) * 15}px)`,
        }}
      >
        Klippy
      </div>

      {/* Tagline */}
      <div
        style={{
          fontSize: 30,
          color: COLORS.textSecondary,
          zIndex: 3,
          opacity: taglineIn,
          filter: `blur(${taglineBlur}px)`,
          transform: `translateY(${(1 - taglineIn) * 12}px)`,
          marginTop: 12,
          letterSpacing: 0.5,
        }}
      >
        The clipboard manager that actually scales
      </div>

      {/* Badges */}
      <div style={{ display: "flex", gap: 12, marginTop: 24, zIndex: 3 }}>
        {["SwiftUI", "macOS", "Open Source"].map((tag, i) => {
          const tagIn = spring({ frame: frame - 85 - i * 5, fps, config: { damping: 200 } });
          const tBlur = interpolate(frame, [85 + i * 5, 96 + i * 5], [6, 0], {
            extrapolateRight: "clamp",
            extrapolateLeft: "clamp",
          });
          return (
            <div
              key={tag}
              style={{
                padding: "8px 20px",
                borderRadius: 20,
                background: COLORS.surface,
                border: `1px solid ${COLORS.border}`,
                color: COLORS.textSecondary,
                fontSize: 17,
                fontWeight: 600,
                opacity: tagIn,
                filter: `blur(${tBlur}px)`,
                transform: `scale(${0.85 + tagIn * 0.15})`,
              }}
            >
              {tag}
            </div>
          );
        })}
      </div>
    </div>
  );
};
