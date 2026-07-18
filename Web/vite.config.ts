import { defineConfig } from "vitest/config";
import preact from "@preact/preset-vite";

const editorTarget = "http://127.0.0.1:8787";

export default defineConfig({
  plugins: [preact()],
  base: "/",
  build: {
    outDir: "dist",
    emptyOutDir: true,
    assetsDir: "assets",
    sourcemap: false,
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": {
        target: editorTarget,
        changeOrigin: true,
        ws: true,
        configure(proxy) {
          const setEditorOrigin = (proxyRequest: { setHeader(name: string, value: string): void }) => {
            proxyRequest.setHeader("Origin", editorTarget);
          };
          proxy.on("proxyReq", setEditorOrigin);
          proxy.on("proxyReqWs", setEditorOrigin);
        },
      },
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./tests/setup.ts",
    exclude: ["tests/e2e/**", "node_modules/**", "dist/**"],
    css: true,
    restoreMocks: true,
  },
});
