import type { CapacitorConfig } from "@capacitor/cli";

/**
 * HRMate native shell — loads the live app over HTTPS (always the newest build,
 * zero store-update friction). Geolocation & camera handled natively via plugins;
 * the web code falls back to navigator APIs in the browser.
 */
const config: CapacitorConfig = {
  appId: "in.flavorflow.hrmate",
  appName: "HRMate",
  webDir: "public",
  server: {
    url: "https://hr.flavorflow.co.in",
    cleartext: false,
  },
  android: {
    allowMixedContent: false,
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1200,
      backgroundColor: "#0a1628",
      androidScaleType: "CENTER_CROP",
    },
  },
};

export default config;
