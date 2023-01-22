import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";
import vue from "@vitejs/plugin-vue";
import pluginJson5 from "./vite.json5";
import meta from "./package.json";
// https://vitejs.dev/config/

const extensions = [
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".mjs",
  ".json",
  ".json5",
  ".svg",
  ".sass",
  ".scss",
  ".css",
  ".vue",
];

export default defineConfig({
  plugins: [vue({ reactivityTransform: true }), pluginJson5(), tsconfigPaths()],
  resolve: {
    extensions,
    alias: {
      "@/": __dirname + "/src/",
      "/client-assets/": __dirname + "/src/assets/",
      // '/static-assets/': __dirname + '/../backend/assets/',
    },
  },
  build: {
    outDir: "dist",
  },

  define: {
    _VERSION_: JSON.stringify(meta.version),
    _ENV_: JSON.stringify(process.env.NODE_ENV),
    _DEV_: process.env.NODE_ENV !== "production",
    _PERF_PREFIX_: JSON.stringify("Misskey:"),
    _DATA_TRANSFER_DRIVE_FILE_: JSON.stringify("mk_drive_file"),
    _DATA_TRANSFER_DRIVE_FOLDER_: JSON.stringify("mk_drive_folder"),
    _DATA_TRANSFER_DECK_COLUMN_: JSON.stringify("mk_deck_column"),
    __VUE_OPTIONS_API__: true,
    __VUE_PROD_DEVTOOLS__: false,
  },
});
