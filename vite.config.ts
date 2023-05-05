import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vitejs.dev/config/
export default defineConfig({
  publicDir: "public",
  plugins: [vue()],
  resolve: {
    alias: {
      "@@" :  fileURLToPath(new URL('./src', import.meta.url)),
    }
  },
  build: {
    emptyOutDir: false,
  },
  server: {
    port: 5173,
    proxy: {
      '/misskey-v13': {
        target: "http://localhost:6013",
        changeOrigin: true,
        rewrite: (path) => `${path}`.replace(/(.*?)\/misskey-v13/, "misskey-v13/$1")
      },
    }

  }

})
