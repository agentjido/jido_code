import {defineConfig} from "vite"
import vue from "@vitejs/plugin-vue"
import liveVuePlugin from "live_vue/vitePlugin"
import tailwindcss from "@tailwindcss/vite"
import {fileURLToPath} from "node:url"

const phoenixHost = process.env.PHX_HOST ?? "localhost"
const phoenixPort = process.env.PORT ?? "4100"
const viteHost = process.env.VITE_HOST ?? (process.env.PHX_HOST ? "0.0.0.0" : "127.0.0.1")
const vitePort = Number(process.env.VITE_PORT ?? "5173")
const allowedOrigins = [
  `http://localhost:${phoenixPort}`,
  `http://127.0.0.1:${phoenixPort}`,
  `http://${phoenixHost}:${phoenixPort}`,
]

export default defineConfig({
  server: {
    host: viteHost,
    port: vitePort,
    strictPort: true,
    cors: {origin: [...new Set(allowedOrigins)]},
  },
  optimizeDeps: {
    include: ["live_vue", "phoenix", "phoenix_html", "phoenix_live_view"],
  },
  ssr: {noExternal: process.env.NODE_ENV === "production" ? true : undefined},
  build: {
    manifest: false,
    ssrManifest: false,
    rollupOptions: {
      input: ["js/app.js", "css/app.css"],
    },
    outDir: "../priv/static",
    emptyOutDir: true,
  },
  resolve: {
    alias: {
      "@": fileURLToPath(new URL(".", import.meta.url)),
      "phoenix-colocated": `${process.env.MIX_BUILD_PATH}/phoenix-colocated`,
    },
  },
  plugins: [tailwindcss(), vue(), liveVuePlugin()],
})
