import { miLocalStorage } from "./local-storage";
import { $i } from "@/account";
import { langNames } from "@/i18n"

const address = $i? new URL($i.instanceUrl) : null;
const siteName = (document.querySelector('meta[property="og:site_name"]') as HTMLMetaElement)?.content;

export const host = address?.host;
export const hostname = address?.hostname;
export const url = $i?.instanceUrl;
export const apiUrl = url + '/api';
export const wsUrl = url?.replace('http://', 'ws://').replace('https://', 'wss://') + '/streaming';
export const lang = miLocalStorage.getItem('lang');
export const langs = langNames
export const version = _VERSION_;
export const instanceName = siteName === 'Misskey' ? host : siteName;
export const ui = miLocalStorage.getItem('ui');
export const debug = miLocalStorage.getItem('debug') === 'true';
