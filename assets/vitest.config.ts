import { fileURLToPath } from "node:url"
import vue from "@vitejs/plugin-vue"
import { defineConfig } from "vitest/config"

const assetsRoot = fileURLToPath(new URL(".", import.meta.url))

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      "@": assetsRoot,
    },
  },
  test: {
    environment: "node",
    include: ["assets/vue/**/*.test.ts"],
  },
})
