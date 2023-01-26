import { api } from "@/os";
import { $i } from "@/account";
import { Theme } from "./scripts/theme";

const lsCacheKey = $i ? `themes:${$i.id}` : "";

export function getThemes(): Theme[] {
  return JSON.parse(localStorage.getItem(lsCacheKey) || "[]");
}

export async function fetchThemes(): Promise<void> {
  if ($i == null) return;

  // const themes = await api('i/registry/get', { scope: ['client'], key: 'themes' });
  localStorage.setItem(
    lsCacheKey,
    JSON.stringify([
      {
        accent: "rgb(134, 179, 0)",
        accentDarken: "rgb(96, 128, 0)",
        accentLighten: "rgb(172, 230, 0)",
        accentedBg: "rgba(134, 179, 0, 0.15)",
        focus: "rgba(134, 179, 0, 0.3)",
        bg: "rgb(249, 249, 249)",
        acrylicBg: "rgba(249, 249, 249, 0.5)",
        fg: "rgb(103, 103, 103)",
        fgTransparentWeak: "rgba(103, 103, 103, 0.75)",
        fgTransparent: "rgba(103, 103, 103, 0.5)",
        fgHighlighted: "rgb(95, 95, 95)",
        fgOnAccent: "rgb(255, 255, 255)",
        divider: "rgb(232, 232, 232)",
        indicator: "rgb(134, 179, 0)",
        panel: "rgb(255, 255, 255)",
        panelHighlight: "rgb(247, 247, 247)",
        panelHeaderBg: "rgb(255, 255, 255)",
        panelHeaderFg: "rgb(103, 103, 103)",
        panelHeaderDivider: "rgb(232, 232, 232)",
        panelBorder: "solid 1px var(--divider)",
        acrylicPanel: "rgba(255, 255, 255, 0.5)",
        windowHeader: "rgba(255, 255, 255, 0.85)",
        popup: "rgb(255, 255, 255)",
        shadow: "rgba(0, 0, 0, 0.1)",
        header: "rgba(255, 255, 255, 0.95)",
        navBg: "rgb(255, 255, 255)",
        navFg: "rgb(103, 103, 103)",
        navHoverFg: "rgb(60, 60, 60)",
        navActive: "rgb(134, 179, 0)",
        navIndicator: "rgb(134, 179, 0)",
        link: "rgb(68, 164, 193)",
        hashtag: "rgb(255, 145, 86)",
        mention: "rgb(134, 179, 0)",
        mentionMe: "rgb(0, 179, 70)",
        renote: "rgb(34, 158, 130)",
        modalBg: "rgba(0, 0, 0, 0.3)",
        scrollbarHandle: "rgba(0, 0, 0, 0.2)",
        scrollbarHandleHover: "rgba(0, 0, 0, 0.4)",
        dateLabelFg: "rgb(103, 103, 103)",
        infoBg: "rgb(229, 245, 255)",
        infoFg: "rgb(114, 129, 138)",
        infoWarnBg: "rgb(255, 240, 219)",
        infoWarnFg: "rgb(143, 110, 49)",
        switchBg: "rgba(0, 0, 0, 0.15)",
        cwBg: "rgb(177, 185, 193)",
        cwFg: "rgb(255, 255, 255)",
        cwHoverBg: "rgb(187, 196, 206)",
        buttonBg: "rgba(0, 0, 0, 0.05)",
        buttonHoverBg: "rgba(0, 0, 0, 0.1)",
        buttonGradateA: "rgb(134, 179, 0)",
        buttonGradateB: "rgb(74, 179, 0)",
        swutchOffBg: "rgba(0, 0, 0, 0.1)",
        swutchOffFg: "rgb(255, 255, 255)",
        swutchOnBg: "rgb(134, 179, 0)",
        swutchOnFg: "rgb(255, 255, 255)",
        inputBorder: "rgba(0, 0, 0, 0.1)",
        inputBorderHover: "rgba(0, 0, 0, 0.2)",
        listItemHoverBg: "rgba(0, 0, 0, 0.03)",
        driveFolderBg: "rgba(134, 179, 0, 0.3)",
        wallpaperOverlay: "rgba(255, 255, 255, 0.5)",
        badge: "rgb(49, 177, 206)",
        messageBg: "rgb(249, 249, 249)",
        success: "rgb(134, 179, 0)",
        error: "rgb(236, 65, 55)",
        warn: "rgb(236, 182, 55)",
        codeString: "rgb(185, 135, 16)",
        codeNumber: "rgb(15, 187, 187)",
        codeBoolean: "rgb(98, 183, 12)",
        deckDivider: "rgb(241, 241, 241)",
        htmlThemeColor: "rgb(249, 249, 249)",
        X2: "rgb(250, 250, 250)",
        X3: "rgba(0, 0, 0, 0.05)",
        X4: "rgba(0, 0, 0, 0.1)",
        X5: "rgba(0, 0, 0, 0.05)",
        X6: "rgba(0, 0, 0, 0.25)",
        X7: "rgba(0, 0, 0, 0.05)",
        X8: "rgb(153, 204, 0)",
        X9: "rgb(115, 153, 0)",
        X10: "rgba(134, 179, 0, 0.4)",
        X11: "rgba(0, 0, 0, 0.1)",
        X12: "rgba(0, 0, 0, 0.1)",
        X13: "rgba(0, 0, 0, 0.15)",
        X14: "rgba(255, 255, 255, 0.95)",
        X15: "rgba(255, 255, 255, 0)",
        X16: "rgba(255, 255, 255, 0.7)",
        X17: "rgba(249, 249, 249, 0.8)",
      },
    ])
  );
}

export async function addTheme(theme: Theme): Promise<void> {
  await fetchThemes();
  const themes = getThemes().concat(theme);
  // await api("i/registry/set", {
  //   scope: ["client"],
  //   key: "themes",
  //   value: themes,
  // });
  localStorage.setItem(lsCacheKey, JSON.stringify(themes));
}

export async function removeTheme(theme: Theme): Promise<void> {
  const themes = getThemes().filter((t) => t.id !== theme.id);
  // await api("i/registry/set", {
  //   scope: ["client"],
  //   key: "themes",
  //   value: themes,
  // });
  localStorage.setItem(lsCacheKey, JSON.stringify(themes));
}
