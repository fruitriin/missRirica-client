import { $i } from "@/account";

const address = $i? new URL($i.instanceUrl) : null;
const siteName = (
  document.querySelector('meta[property="og:site_name"]') as HTMLMetaElement
)?.content;

export const host = address?.host;
export const hostname = address?.hostname;
export const url = $i?.instanceUrl;
export const apiUrl = url + "/api";
export const wsUrl =
  url?.replace("http://", "ws://").replace("https://", "wss://") + "/streaming";
export const lang = localStorage.getItem("lang");
export const langs = _LANGS_;
export const locale = JSON.parse(window.localStorage.getItem("locale"));
export const version = _VERSION_;
export const instanceName = siteName === "Misskey" ? host : siteName;
export const ui = localStorage.getItem("ui");
export const debug = localStorage.getItem("debug") === "true";
