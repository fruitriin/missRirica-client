// https://nuxt.com/docs/api/configuration/nuxt-config

import {} from "twemoji";
export default defineNuxtConfig({
  ssr: false,
  experimental: {
    noScripts: true,
  },

  srcDir: "src/",
  alias: {
    "@": "misskey/packages/frontend/src",
  },
  css: ["vuetify/lib/styles/main.sass", "mdi/css/materialdesignicons.min.css"],
  build: {
    transpile: ["vuetify"],
  },
  modules: ["@pinia/nuxt"],
  vite: {
    define: {
      "process.env.DEBUG": true,
    },
  },
});
