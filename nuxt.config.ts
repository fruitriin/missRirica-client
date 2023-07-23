// https://nuxt.com/docs/api/configuration/nuxt-config
import { defineNuxtConfig } from "nuxt/config";
import AppConfig from "@nuxt/schema"

const option: AppConfig.NuxtConfig = {
  ssr: false,
  srcDir: "src/",
  experimental: {
    reactivityTransform: true
  },
  devServer: {
    port: 5173,
    host: "0.0.0.0",
  },
  modules: [
    // ...
    '@pinia/nuxt',
  ],
}

export default defineNuxtConfig(option as any )
