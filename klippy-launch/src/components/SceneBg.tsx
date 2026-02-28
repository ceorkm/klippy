import React from "react";
import { useCurrentFrame, interpolate, Easing } from "remotion";
import { COLORS } from "../theme";

// Premium background: sparkle stars + tiny dots + vignette + soft gradient wash
// Used across all scenes for consistent cinematic depth

const SPARKLE_PATH =
  "M12 0 L12.8 9.8 L24 12 L12.8 14.2 L12 24 L11.2 14.2 L0 12 L11.2 9.8 Z";

interface SparkleConfig {
  x: number;
  y: number;
  size: number;
  delay: number;
  rotation: number;
}

const DEFAULT_SPARKLES: SparkleConfig[] = [
  { x: 12, y: 15, size: 30, delay: 0, rotation: 0 },
  { x: 88, y: 10, size: 20, delay: 8, rotation: 15 },
  { x: 75, y: 80, size: 24, delay: 4, rotation: -10 },
  { x: 18, y: 75, size: 16, delay: 12, rotation: 20 },
  { x: 50, y: 6, size: 34, delay: 6, rotation: -5 },
  { x: 93, y: 50, size: 14, delay: 10, rotation: 30 },
  { x: 5, y: 45, size: 22, delay: 14, rotation: -15 },
  { x: 38, y: 90, size: 12, delay: 16, rotation: 10 },
  { x: 65, y: 30, size: 10, delay: 18, rotation: -20 },
  { x: 30, y: 35, size: 8, delay: 20, rotation: 25 },
];

// Tiny floating dots for texture
const TINY_DOTS = Array.from({ length: 15 }, (_, i) => ({
  x: ((i * 41 + 17) % 94) + 3,
  y: ((i * 31 + 11) % 90) + 5,
  size: 2 + (i % 3),
  delay: i * 3,
}));

export const SceneBg: React.FC<{
  sparkles?: SparkleConfig[];
  color?: string;
}> = ({ sparkles = DEFAULT_SPARKLES, color = COLORS.accent }) => {
  const frame = useCurrentFrame();

  return (
    <>
      {/* Vignette — focus toward center */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse at center, transparent 40%, rgba(0,0,0,0.05) 100%)",
          zIndex: 1,
        }}
      />

      {/* Soft center gradient wash */}
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          width: 900,
          height: 900,
          borderRadius: "50%",
          transform: "translate(-50%, -50%)",
          background: `radial-gradient(circle, ${color}08 0%, ${color}03 40%, transparent 70%)`,
          zIndex: 1,
        }}
      />

      {/* Sparkle stars — 4-pointed with glow */}
      {sparkles.map((sparkle, i) => {
        const sparkleIn = interpolate(
          frame,
          [sparkle.delay, sparkle.delay + 22],
          [0, 1],
          {
            extrapolateRight: "clamp",
            extrapolateLeft: "clamp",
            easing: Easing.out(Easing.quad),
          }
        );
        // Subtle pulse
        const pulse = 1 + Math.sin((frame + i * 35) * 0.04) * 0.2;
        // Gentle rotation drift
        const rot =
          sparkle.rotation + Math.sin((frame + i * 25) * 0.015) * 8;

        return (
          <div
            key={`sparkle-${i}`}
            style={{
              position: "absolute",
              left: `${sparkle.x}%`,
              top: `${sparkle.y}%`,
              transform: `translate(-50%, -50%) rotate(${rot}deg) scale(${sparkleIn * pulse})`,
              opacity: sparkleIn * 0.3,
              filter: `drop-shadow(0 0 ${sparkle.size / 2.5}px ${color}50)`,
              zIndex: 1,
            }}
          >
            <svg
              width={sparkle.size}
              height={sparkle.size}
              viewBox="0 0 24 24"
            >
              <path d={SPARKLE_PATH} fill={color} />
            </svg>
          </div>
        );
      })}

      {/* Tiny floating dots — starfield texture */}
      {TINY_DOTS.map((dot, i) => {
        const dotIn = interpolate(
          frame,
          [dot.delay, dot.delay + 15],
          [0, 1],
          {
            extrapolateRight: "clamp",
            extrapolateLeft: "clamp",
          }
        );
        const dotPulse = 0.5 + Math.sin((frame + i * 20) * 0.06) * 0.5;

        return (
          <div
            key={`dot-${i}`}
            style={{
              position: "absolute",
              left: `${dot.x}%`,
              top: `${dot.y}%`,
              width: dot.size,
              height: dot.size,
              borderRadius: "50%",
              background: color,
              opacity: dotIn * dotPulse * 0.2,
              zIndex: 1,
            }}
          />
        );
      })}
    </>
  );
};
