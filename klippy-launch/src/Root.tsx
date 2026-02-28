import React from "react";
import { Composition } from "remotion";
import { KlippyLaunchVideo } from "./KlippyLaunchVideo";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="KlippyLaunch"
      component={KlippyLaunchVideo}
      durationInFrames={1050}
      fps={30}
      width={1920}
      height={1080}
    />
  );
};
