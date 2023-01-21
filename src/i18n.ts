import { I18n } from "@/scripts/i18n";
import { load } from "js-yaml";
const languages = [
    'ar-SA',
    'cs-CZ',
    'da-DK',
    'de-DE',
    'en-US',
    'es-ES',
    'fr-FR',
    'id-ID',
    'it-IT',
    'ja-JP',
    'ja-KS',
    'kab-KAB',
    'kn-IN',
    'ko-KR',
    'nl-NL',
    'no-NO',
    'pl-PL',
    'pt-PT',
    'ru-RU',
    'sk-SK',
    'ug-CN',
    'uk-UA',
    'vi-VN',
    'zh-CN',
    'zh-TW',
] as const
async function loadLanguage(locale: typeof languages[number]){
    if(!languages.includes(locale)) return
    const res = await fetch("/client-assets/locales/" + locale + ".yml").then(res => res.text())

    console.log(locale, res)
    return load(res)
}

export async function setLanguage(locale: string){
    console.log(locale)
    i18n = new I18n(await loadLanguage(locale))
}

export let i18n = new I18n(await loadLanguage("ja-JP"))