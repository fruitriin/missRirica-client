import { I18n } from "@/scripts/i18n";
import arSA from "@/locales/ar-SA.json";
import csCZ from "@/locales/cs-CZ.json";
import daDK from "@/locales/da-DK.json";
import deDE from "@/locales/de-DE.json";
import enUS from "@/locales/en-US.json";
import esES from "@/locales/es-ES.json";
import frFR from "@/locales/fr-FR.json";
import idID from "@/locales/id-ID.json";
import itIT from "@/locales/it-IT.json";
import jaJP from "@/locales/ja-JP.json";
import jaKS from "@/locales/ja-KS.json";
import kabKAB from "@/locales/kab-KAB.json";
import knIN from "@/locales/kn-IN.json";
import koKR from "@/locales/ko-KR.json";
import nlNL from "@/locales/nl-NL.json";
import noNO from "@/locales/no-NO.json";
import plPL from "@/locales/pl-PL.json";
import ptPT from "@/locales/pt-PT.json";
import ruRU from "@/locales/ru-RU.json";
import skSK from "@/locales/sk-SK.json";
import ugCN from "@/locales/ug-CN.json";
import ukUA from "@/locales/uk-UA.json";
import viVN from "@/locales/vi-VN.json";
import zhCN from "@/locales/zh-CN.json";
import zhTW from "@/locales/zh-TW.json";

import Fuse from "fuse.js";

const languages = {
	"ar-SA": arSA,
	"cs-CZ": csCZ,
	"da-DK": daDK,
	"de-DE": deDE,
	"en-US": enUS,
	"es-ES": esES,
	"fr-FR": frFR,
	"id-ID": idID,
	"it-IT": itIT,
	"ja-JP": jaJP,
	"ja-KS": jaKS,
	"kab-KAB": kabKAB,
	"kn-IN": knIN,
	"ko-KR": koKR,
	"nl-NL": nlNL,
	"no-NO": noNO,
	"pl-PL": plPL,
	"pt-PT": ptPT,
	"ru-RU": ruRU,
	"sk-SK": skSK,
	"ug-CN": ugCN,
	"uk-UA": ukUA,
	"vi-VN": viVN,
	"zh-CN": zhCN,
	"zh-TW": zhTW,
} as const;

export let langNames =  Object.keys(languages).map(l => {
	return [l,  languages[l]._lang_]
})

export function setLanguage(lang: keyof typeof languages) {
	console.log(lang)
	if (Object.keys(languages).includes(lang)) {
		i18n = new I18n(languages[lang]);
		return lang
	} else {
		const fuse = new Fuse(Object.keys(languages));
		const results = fuse.search(lang);
		i18n = new I18n(languages[results[0].item]);
		console.log(results[0])
		return results[0].item
	}
}
export let i18n = new I18n(languages["ja-JP"]);