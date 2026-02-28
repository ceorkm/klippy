import React from "react";
import { Audio, interpolate, useCurrentFrame, useVideoConfig, staticFile } from "remotion";
import { TransitionSeries, springTiming } from "@remotion/transitions";
import { slide } from "@remotion/transitions/slide";
import { loadFont as loadSpaceGrotesk } from "@remotion/google-fonts/SpaceGrotesk";
import { loadFont as loadSpaceMono } from "@remotion/google-fonts/SpaceMono";

const { fontFamily: spaceGrotesk } = loadSpaceGrotesk();
const { fontFamily: spaceMono } = loadSpaceMono();

// Export for use in theme
export const LOADED_FONTS = {
  heading: spaceGrotesk,
  mono: spaceMono,
} as const;

import { Scene1Hook } from "./scenes/Scene1Hook";
import { Scene2LogoReveal } from "./scenes/Scene2LogoReveal";
import { Scene3MenuBar } from "./scenes/Scene3MenuBar";
import { Scene4Classification } from "./scenes/Scene4Classification";
import { Scene5Search } from "./scenes/Scene5Search";
import { Scene6Scale } from "./scenes/Scene6Scale";
import { Scene7Privacy } from "./scenes/Scene7Privacy";
import { Scene8CodeGlimpse } from "./scenes/Scene8CodeGlimpse";
import { Scene9CTA } from "./scenes/Scene9CTA";

// Scene layout:
// Scene 1 — Hook (4s / 120 frames)
// Scene 2 — Logo Reveal (4s / 120 frames)
// Scene 3 — Menu Bar App (5s / 150 frames)
// Scene 4 — Smart Classification (5s / 150 frames)
// Scene 5 — Search Power (5s / 150 frames)
// Scene 8 — Klippy In Action (4s / 120 frames) ← after search
// Scene 6 — Scale Demo (4s / 120 frames)
// Scene 7 — Privacy (3.5s / 105 frames)
// Scene 9 — GitHub CTA (4.5s / 135 frames)
// Total: ~37s with transitions

const TRANSITION_DURATION = 15; // 0.5s overlap

const BGM: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames, fps } = useVideoConfig();

  // 1s fade in, 2s fade out
  const fadeInFrames = fps * 1;
  const fadeOutFrames = fps * 2;

  const volume = interpolate(
    frame,
    [0, fadeInFrames, durationInFrames - fadeOutFrames, durationInFrames],
    [0, 0.8, 0.8, 0],
    { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
  );

  return <Audio src={staticFile("bgm2.mp3")} volume={volume} />;
};

export const KlippyLaunchVideo: React.FC = () => {
  return (
    <>
    <BGM />
    <TransitionSeries>
      {/* Scene 1 — The Hook */}
      <TransitionSeries.Sequence durationInFrames={120}>
        <Scene1Hook />
      </TransitionSeries.Sequence>

      <TransitionSeries.Transition
        presentation={slide({ direction: "from-right" })}
        timing={springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION_DURATION })}
      />

      {/* Scene 2 — Logo Reveal */}
      <TransitionSeries.Sequence durationInFrames={120}>
        <Scene2LogoReveal />
      </TransitionSeries.Sequence>

      <TransitionSeries.Transition
        presentation={slide({ direction: "from-right" })}
        timing={springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION_DURATION })}
      />

      {/* Scene 3 — Menu Bar App */}
      <TransitionSeries.Sequence durationInFrames={150}>
        <Scene3MenuBar />
      </TransitionSeries.Sequence>

      <TransitionSeries.Transition
        presentation={slide({ direction: "from-right" })}
        timing={springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION_DURATION })}
      />

      {/* Scene 4 — Smart Classification */}
      <TransitionSeries.Sequence durationInFrames={150}>
        <Scene4Classification />
      </TransitionSeries.Sequence>

      <TransitionSeries.Transition
        presentation={slide({ direction: "from-bottom" })}
        timing={springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION_DURATION })}
      />

      {/* Scene 5 — Search Power */}
      <TransitionSeries.Sequence durationInFrames={150}>
        <Scene5Search />
      </TransitionSeries.Sequence>

      <TransitionSeries.Transition
        presentation={slide({ direction: "from-right" })}
        timing={springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION_DURATION })}
      />

      {/* Scene 8 — Klippy In Action (after search) */}
      <TransitionSeries.Sequence durationInFrames={120}>
        <Scene8CodeGlimpse />
      </TransitionSeries.Sequence>

      <TransitionSeries.Transition
        presentation={slide({ direction: "from-bottom" })}
        timing={springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION_DURATION })}
      />

      {/* Scene 6 — Scale Demo */}
      <TransitionSeries.Sequence durationInFrames={120}>
        <Scene6Scale />
      </TransitionSeries.Sequence>

      <TransitionSeries.Transition
        presentation={slide({ direction: "from-right" })}
        timing={springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION_DURATION })}
      />

      {/* Scene 7 — Privacy & Security */}
      <TransitionSeries.Sequence durationInFrames={105}>
        <Scene7Privacy />
      </TransitionSeries.Sequence>

      <TransitionSeries.Transition
        presentation={slide({ direction: "from-bottom" })}
        timing={springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION_DURATION })}
      />

      {/* Scene 9 — GitHub CTA */}
      <TransitionSeries.Sequence durationInFrames={135}>
        <Scene9CTA />
      </TransitionSeries.Sequence>
    </TransitionSeries>
    </>
  );
};
