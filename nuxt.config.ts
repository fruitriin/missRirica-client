// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  devtools: { enabled: true },
  srcDir: "src/",
  devServer: {
    port: 8000,
  },
  ssr: false

})
