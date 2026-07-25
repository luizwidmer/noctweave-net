import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Noctweb Lab",
    short_name: "Noctweb",
    description:
      "Build, publish, resolve, inspect, and fault-test Noctweb sites.",
    start_url: "/",
    scope: "/",
    display: "standalone",
    orientation: "any",
    background_color: "#0a0f0d",
    theme_color: "#0a0f0d",
    categories: ["developer", "productivity", "utilities"],
    icons: [
      {
        src: "/app-icon.png",
        sizes: "1254x1254",
        type: "image/png",
        purpose: "any",
      },
    ],
  };
}
