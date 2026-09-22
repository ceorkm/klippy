import React from "react";
import {
  AbsoluteFill,
  Composition,
  Img,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { FONT, INK, Words, fadeOut } from "./Words";

/**
 * Klippy launch film. 30 seconds, 1920x1080, silent, white throughout.
 *
 * White on purpose, start to finish, including the end card. The panel captures
 * are real window grabs with transparent corners, so they sit on the white
 * rather than in a mocked-up window frame.
 *
 * There is never a hard cut. The background never changes, the panel holds one
 * position and one continuous push-in, and only its content cross-fades. That
 * is what makes the reference film read as a single unbroken take.
 */

const FPS = 30;
const W = 1920;
const H = 1080;
const DURATION = 30 * FPS;

// Where the panel sits: centred, anchored low, running off the bottom edge the
// way a laptop lid does in the reference. The panel's own header and list are
// in its top two thirds, so nothing that matters is lost off-frame.
// Native capture is 860 wide. Shown at 1120 it is a 1.3x upscale of a retina
// grab, which video compression hides completely, and it stops the panel
// reading as a small object lost in the white.
const PANEL_W = 1120;
const PANEL_TOP = 250;

type Beat = { src: string; from: number; to: number };

// One shot per panel state. Overlapping by 20 frames so each dissolves into
// the next instead of cutting.
const BEATS: Beat[] = [
  { src: "01-list.png", from: 100, to: 360 },
  { src: "04-search.png", from: 340, to: 510 },
  { src: "03-cards.png", from: 490, to: 620 },
  { src: "02-images.png", from: 600, to: 680 },
  { src: "05-settings.png", from: 660, to: 790 },
];

/** Every panel state stacked, with only one visible at a time. */
const PanelStack: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // The rise: the panel comes up off the bottom edge once, at the start, and
  // then never moves again except for the slow push-in.
  const rise = spring({
    frame: frame - 100,
    fps,
    config: { damping: 200, mass: 1.1, stiffness: 70 },
  });
  const lift = interpolate(rise, [0, 1], [520, 0], {
    extrapolateRight: "clamp",
  });

  // A single continuous scale across the whole film. Slow enough that you feel
  // it rather than see it.
  const push = interpolate(frame, [100, 790], [0.97, 1.07], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const leaving = fadeOut(frame, 770, 20);

  return (
    <div
      style={{
        position: "absolute",
        left: (W - PANEL_W) / 2,
        top: PANEL_TOP,
        width: PANEL_W,
        transform: `translateY(${lift}px) scale(${push})`,
        transformOrigin: "50% 20%",
        opacity: leaving,
        // Lifts the panel off the page. Without it the transparent corners
        // make it look pasted on rather than placed.
        filter: "drop-shadow(0 34px 70px rgba(10,10,10,0.26))",
      }}
    >
      {BEATS.map((beat) => (
        <Img
          key={beat.src}
          src={staticFile(beat.src)}
          style={{
            position: beat.src === BEATS[0].src ? "relative" : "absolute",
            top: 0,
            left: 0,
            width: PANEL_W,
            // Cross-fade in and out. Both ends are eased, so no state ever
            // pops on or off.
            opacity: interpolate(
              frame,
              [beat.from, beat.from + 20, beat.to - 20, beat.to],
              [0, 1, 1, 0],
              { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
            ),
          }}
        />
      ))}
    </div>
  );
};

/** A headline that reveals, holds, then fades. */
const Line: React.FC<{
  from: number;
  durationInFrames: number;
  children: React.ReactNode;
}> = ({ from, durationInFrames, children }) => (
  <Sequence from={from} durationInFrames={durationInFrames}>
    <HeadlineBody durationInFrames={durationInFrames}>{children}</HeadlineBody>
  </Sequence>
);

const HeadlineBody: React.FC<{
  durationInFrames: number;
  children: React.ReactNode;
}> = ({ durationInFrames, children }) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "flex-start",
        paddingTop: 110,
        opacity: fadeOut(frame, durationInFrames - 16),
      }}
    >
      <div style={{ width: 1500, textAlign: "center" }}>{children}</div>
    </AbsoluteFill>
  );
};

/** The shortcut, shown as two keys, at the moment the panel arrives. */
const Shortcut: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame, fps, config: { damping: 14, mass: 0.5 } });

  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "flex-start",
        paddingTop: 196,
        opacity: interpolate(frame, [0, 6, 46, 58], [0, 1, 1, 0], {
          extrapolateRight: "clamp",
        }),
      }}
    >
      <div
        style={{
          display: "flex",
          gap: 14,
          transform: `scale(${interpolate(pop, [0, 1], [0.86, 1])})`,
        }}
      >
        {["control", "⌘", "V"].map((key) => (
          <div
            key={key}
            style={{
              fontFamily: FONT,
              fontSize: 34,
              fontWeight: 600,
              color: INK,
              padding: "14px 26px",
              borderRadius: 14,
              background: "#F1F1EF",
              border: "1px solid rgba(10,10,10,0.09)",
              boxShadow: "0 2px 0 rgba(10,10,10,0.10)",
            }}
          >
            {key}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

/** End card: the raw icon on the same white, nothing behind it. */
const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({
    frame,
    fps,
    config: { damping: 200, mass: 0.9, stiffness: 80 },
  });

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <Img
        src={staticFile("icon.png")}
        style={{
          width: 300,
          height: 300,
          opacity: interpolate(enter, [0, 0.4], [0, 1], {
            extrapolateRight: "clamp",
          }),
          transform: `scale(${interpolate(enter, [0, 1], [0.88, 1])})`,
        }}
      />
      <div style={{ height: 54 }} />
      <Words text="Klippy" size={116} delay={12} />
      <div style={{ height: 26 }} />
      <div
        style={{
          fontFamily: FONT,
          fontSize: 44,
          fontWeight: 500,
          color: "rgba(10,10,10,0.55)",
          opacity: interpolate(frame, [30, 46], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
        }}
      >
        Free on the Mac App Store
      </div>
    </AbsoluteFill>
  );
};

export const KlippyFilm: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#FFFFFF" }}>
      <PanelStack />

      {/* The hook. A complaint, before the product exists. */}
      <Line from={0} durationInFrames={100}>
        <Words text="copied it." size={132} />
        <div style={{ height: 8 }} />
        <Words text="now where'd it go??" size={132} delay={20} />
      </Line>

      <Sequence from={110} durationInFrames={60}>
        <Shortcut />
      </Sequence>

      <Line from={190} durationInFrames={150}>
        <Words text="everything you copy, kept" size={122} />
      </Line>

      <Line from={350} durationInFrames={140}>
        <Words text="find it in a second" size={126} />
      </Line>

      <Line from={500} durationInFrames={140}>
        <Words text="text, links, pictures, colours" size={108} />
      </Line>

      <Line from={650} durationInFrames={120}>
        <Words text="and it never leaves your Mac" size={112} />
      </Line>

      <Sequence from={790} durationInFrames={110}>
        <EndCard />
      </Sequence>
    </AbsoluteFill>
  );
};

export const MyComposition: React.FC = () => {
  return (
    <Composition
      id="KlippyFilm"
      component={KlippyFilm}
      durationInFrames={DURATION}
      fps={FPS}
      width={W}
      height={H}
    />
  );
};
