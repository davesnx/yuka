import brumate from "brumate/vite";
import { defineConfig } from "vite";

export default defineConfig({
  base: "/brumate/",
  plugins: [brumate({ navigate: false, prerender: { paths: ["/"], crawl: false } })],
  build: {
    manifest: true,
    rolldownOptions: { input: "src/client.ts" },
  },
});
