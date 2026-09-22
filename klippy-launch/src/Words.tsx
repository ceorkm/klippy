import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";

/**
 * The reference video's signature move: each word arrives blurred and a little
 * low, then settles. Nothing else carries the text moments, so this is the one
 * effect worth getting exactly right.
 *
 * Per word rather than per letter. Letters read as a gimmick at this size;
 * words read like someone typing a thought.
 */

export const INK = "#0A0A0A";
export const FONT =
  '"SF Pro Display", "SF Pro Text", -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif';

type Props = {
  /** One line. Pass two <Words> for two lines. */
  text: string;
  /** Frame this line starts revealing, relative to its Sequence. */
  delay?: number;
  size?: number;
  /** Frames between one word landing and the next starting. */
  stagger?: number;
  weight?: number;
  color?: string;
};

export const Words: React.FC<Props> = ({
  text,
  delay = 0,
  size = 132,
  stagger = 5,
  weight = 700,
  color = INK,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        gap: `0 ${size * 0.26}px`,
        justifyContent: "center",
        fontFamily: FONT,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: size * -0.022,
        lineHeight: 1.04,
        color,
      }}
    >
      {text.split(" ").map((word, i) => {
        const progress = spring({
          frame: frame - delay - i * stagger,
          fps,
          config: { damping: 200, mass: 0.55, stiffness: 120 },
        });

        return (
          <span
            key={`${word}-${i}`}
            style={{
              display: "inline-block",
              opacity: interpolate(progress, [0, 0.35], [0, 1], {
                extrapolateRight: "clamp",
              }),
              // Blur and lift together. The blur is what sells it; the 30px of
              // travel alone looks like a slide-in, which is a different, cheaper
              // effect.
              filter: `blur(${interpolate(progress, [0, 1], [22, 0], {
                extrapolateRight: "clamp",
              })}px)`,
              transform: `translateY(${interpolate(progress, [0, 1], [30, 0], {
                extrapolateRight: "clamp",
              })}px)`,
            }}
          >
            {word}
          </span>
        );
      })}
    </div>
  );
};

/** Fades a whole line out, so a headline leaves without a hard cut. */
export const fadeOut = (frame: number, start: number, length = 14) =>
  interpolate(frame, [start, start + length], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
