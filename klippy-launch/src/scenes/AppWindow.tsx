import React from "react";
import { COLORS } from "../theme";

// macOS-style window chrome wrapper — clean light theme
export const AppWindow: React.FC<{
  children: React.ReactNode;
  title?: string;
  width?: number;
  height?: number;
  opacity?: number;
  scale?: number;
}> = ({ children, title = "Klippy", width = 900, height = 580, opacity = 1, scale = 1 }) => {
  return (
    <div
      style={{
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        width: "100%",
        height: "100%",
        opacity,
        transform: `scale(${scale})`,
      }}
    >
      <div
        style={{
          width,
          height,
          borderRadius: 12,
          overflow: "hidden",
          background: COLORS.bg,
          border: `1px solid ${COLORS.border}`,
          boxShadow: "0 25px 60px rgba(0,0,0,0.12), 0 8px 24px rgba(0,0,0,0.08)",
          display: "flex",
          flexDirection: "column",
        }}
      >
        {/* Title bar with traffic lights */}
        <div
          style={{
            height: 40,
            background: COLORS.surface,
            borderBottom: `1px solid ${COLORS.border}`,
            display: "flex",
            alignItems: "center",
            paddingLeft: 16,
            paddingRight: 16,
            gap: 8,
            flexShrink: 0,
          }}
        >
          <div style={{ display: "flex", gap: 8 }}>
            <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#ff5f57" }} />
            <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#febc2e" }} />
            <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#28c840" }} />
          </div>
          <div
            style={{
              flex: 1,
              textAlign: "center",
              fontSize: 13,
              fontWeight: 500,
              color: COLORS.muted,
              fontFamily: "Inter, system-ui, sans-serif",
            }}
          >
            {title}
          </div>
          <div style={{ width: 60 }} />
        </div>
        <div style={{ flex: 1, overflow: "hidden", position: "relative", background: COLORS.bg }}>
          {children}
        </div>
      </div>
    </div>
  );
};
