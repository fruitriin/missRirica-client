// https://nuxt.com/docs/api/configuration/nuxt-config
import { defineNuxtConfig } from "nuxt/config";

export default defineNuxtConfig({
  ssr: false,
  srcDir: "src/",

  devServer: {
    port: 5173,
    host: "0.0.0.0",
  },
  modules: [
    // ...
    '@pinia/nuxt',
  ],
})
