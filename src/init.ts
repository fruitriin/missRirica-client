/**
 * Client entry point
 */
// https://vitejs.dev/config/build-options.html#build-modulepreload
import "vite/modulepreload-polyfill";

import "@/style.scss";

//#region account indexedDB migration
import { set } from "@/scripts/idb-proxy";

{
  const accounts = miLocalStorage.getItem("accounts");
  if (accounts) {
    set("accounts", JSON.parse(accounts));
    miLocalStorage.removeItem("accounts");
  }
}
//#endregion

import {
  computed,
  createApp,
  watch,
  markRaw,
  version as vueVersion,
  defineAsyncComponent,
} from "vue";
import { compareVersions } from "compare-versions";
import JSON5 from "json5";

import widgets from "@/widgets";
import directives from "@/directives";
import components from "@/components";
import { version, ui } from "@/config";
import { applyTheme } from "@/scripts/theme";
import { isDeviceDarkmode } from "@/scripts/is-device-darkmode";
import { i18n, setLanguage } from "@/i18n";
import { confirm, alert, post, popup, toast } from "@/os";
import { stream } from "@/stream";
import * as sound from "@/scripts/sound";
import { $i, refreshAccount, login, updateAccount, signout } from "@/account";
import { defaultStore, ColdDeviceStorage } from "@/store";
import { fetchInstance, instance } from "@/instance";
import { makeHotkey } from "@/scripts/hotkey";
import { search } from "@/scripts/search";
import { deviceKind } from "@/scripts/device-kind";
import { initializeSw } from "@/scripts/initialize-sw";
import { reloadChannel } from "@/scripts/unison-reload";
import { reactionPicker } from "@/scripts/reaction-picker";
import { getUrlWithoutLoginId } from "@/scripts/login-id";
import { getAccountFromId } from "@/scripts/get-account-from-id";
import { miLocalStorage } from "./local-storage";
import { claimAchievement, claimedAchievements } from "./scripts/achievements";
import { fetchCustomEmojis } from "./custom-emojis";
import { Device } from "@capacitor/device";
import lightTheme from "@/themes/_light.json5";
import OneSignal from "onesignal-cordova-plugin";
import { App } from "@capacitor/app";
export let storedDeviceInfo: Object;

(async () => {
  console.info(`Misskey v${version}`);
  const lang = await setLanguage(
    localStorage.getItem("lang") ||
      (await Device.getLanguageCode().value) ||
      "ja-JP"
  );

  if (_DEV_) {
    console.warn("Development mode!!!");

    console.info(`vue ${vueVersion}`);

    (window as any).$i = $i;
    (window as any).$store = defaultStore;

    window.addEventListener("error", (event) => {
      console.error(event);
      /*
			alert({
				type: 'error',
				title: 'DEV: Unhandled error',
				text: event.message
			});
			*/
    });

    window.addEventListener("unhandledrejection", (event) => {
      console.error(event);
      /*
			alert({
				type: 'error',
				title: 'DEV: Unhandled promise rejection',
				text: event.reason
			});
			*/
    });
  }

  // タッチデバイスでCSSの:hoverを機能させる
  document.addEventListener("touchend", () => {}, { passive: true });

  // 一斉リロード
  reloadChannel.addEventListener("message", (path) => {
    if (path !== null) location.href = path;
    else location.reload();
  });

  // If mobile, insert the viewport meta tag
  if (["smartphone", "tablet"].includes(deviceKind)) {
    const viewport = document.getElementsByName("viewport").item(0);
    viewport.setAttribute(
      "content",
      `${viewport.getAttribute(
        "content"
      )}, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover`
    );
  }

  //#region Set lang attr
  const html = document.documentElement;

  html.setAttribute("lang", lang);
  const res = await Device.getInfo();
  console.log(res);
  storedDeviceInfo = res;
  html.setAttribute("class", res.platform);

  const css = localStorage.getItem("customCss") || "";
  if (css) {
    const cssNode = document.createElement("style");
    const cssTextNode = document.createTextNode(css);
    cssNode.appendChild(cssTextNode);
    document.body.appendChild(cssNode);
  }
  //#endregion

  //#region loginId
  const params = new URLSearchParams(location.search);
  const loginId = params.get("loginId");

  if (loginId) {
    const target = getUrlWithoutLoginId(location.href);

    if (!$i || $i.id !== loginId) {
      const account = await getAccountFromId(loginId);
      if (account) {
        await login(account.token, target);
        await afterLoginSetup();
      }
    }

    history.replaceState({ misskey: "loginId" }, "", target);
  }

  //#endregion

  //#region Fetch user
  if ($i && $i.token) {
    if (_DEV_) {
      console.log("account cache found. refreshing...");
    }

    await refreshAccount();
    await afterLoginSetup();
  } else {
    if (_DEV_) {
      console.log("no account cache found.");
    }

    // 連携ログインの場合用にCookieを参照する
    const i = (document.cookie.match(/igi=(\w+)/) ?? [null, null])[1];

    if (i != null && i !== "null") {
      if (_DEV_) {
        console.log("signing...");
      }

      try {
        document.body.innerHTML = "<div>Please wait...</div>";
        await login(i);
      } catch (err) {
        // Render the error screen
        // TODO: ちゃんとしたコンポーネントをレンダリングする(v10とかのトラブルシューティングゲーム付きのやつみたいな)
        document.body.innerHTML = '<div id="err">Oops!</div>';
      }
    } else {
      if (_DEV_) {
        console.log("not signed in");
      }
      applyTheme(lightTheme);
    }
  }
  //#endregion

  const app = createApp(
    window.location.search === "?zen"
      ? defineAsyncComponent(() => import("@/ui/zen.vue"))
      : !$i
      ? defineAsyncComponent(() => import("@/ui/visitor.vue"))
      : ui === "deck"
      ? defineAsyncComponent(() => import("@/ui/deck.vue"))
      : ui === "classic"
      ? defineAsyncComponent(() => import("@/ui/classic.vue"))
      : defineAsyncComponent(() => import("@/ui/universal.vue"))
  );

  if (_DEV_) {
    app.config.performance = true;
    app.config.errorHandler = function (err, instance, info) {
      console.error(info, err, instance);
    };
  }

  // TODO: 廃止
  app.config.globalProperties = {
    $i,
    $store: defaultStore,
    $instance: instance,
    $t: i18n.t,
    $ts: i18n.ts,
  };

  widgets(app);
  directives(app);
  components(app);

  const splash = document.getElementById("splash");
  // 念のためnullチェック(HTMLが古い場合があるため(そのうち消す))
  if (splash)
    splash.addEventListener("transitionend", () => {
      splash.remove();
    });

  // https://github.com/misskey-dev/misskey/pull/8575#issuecomment-1114239210
  // なぜかinit.tsの内容が2回実行されることがあるため、mountするdivを1つに制限する
  const rootEl = (() => {
    const MISSKEY_MOUNT_DIV_ID = "misskey_app";

    const currentEl = document.getElementById(MISSKEY_MOUNT_DIV_ID);

    if (currentEl) {
      console.warn("multiple import detected");
      return currentEl;
    }

    const rootEl = document.createElement("div");
    rootEl.id = MISSKEY_MOUNT_DIV_ID;
    document.body.appendChild(rootEl);
    return rootEl;
  })();

  app.mount(rootEl);

  // boot.jsのやつを解除
  window.onerror = null;
  window.onunhandledrejection = null;

  if (splash) {
    splash.style.opacity = "0";
    splash.style.pointerEvents = "none";
  }

  // クライアントが更新されたか？
  const lastVersion = miLocalStorage.getItem("lastVersion");
  if (lastVersion !== version) {
    miLocalStorage.setItem("lastVersion", version);

    // テーマリビルドするため
    miLocalStorage.removeItem("theme");

    try {
      // 変なバージョン文字列来るとcompareVersionsでエラーになるため
      if (lastVersion != null && compareVersions(version, lastVersion) === 1) {
        // ログインしてる場合だけ
        if ($i) {
          popup(
            defineAsyncComponent(() => import("@/components/MkUpdated.vue")),
            {},
            {},
            "closed"
          );
        }
      }
    } catch (err) {}
  }

  App.addListener("backButton", (canGoBack) => {
    if (canGoBack) {
      history.back();
    } else {
      App.exitApp();
    }
  });
})();

async function afterLoginSetup() {
  if (!$i) return;
  const hotkeys = {
    d: (): void => {
      defaultStore.set("darkMode", !defaultStore.state.darkMode);
    },
    s: search,
    ["p|n"]: post,
  };

  // shortcut
  document.addEventListener("keydown", makeHotkey(hotkeys));
  reactionPicker.init();
  const fetchInstanceMetaPromise = fetchInstance();

  fetchInstanceMetaPromise.then(() => {
    miLocalStorage.setItem("v", instance.version);
  });
  try {
    await fetchCustomEmojis();
  } catch (err) {
    console.error(err);
  }

  applyTheme(
    defaultStore.reactiveState.darkMode.value
      ? ColdDeviceStorage.get("darkTheme")
      : ColdDeviceStorage.get("lightTheme")
  );

  // NOTE: この処理は必ず↑のクライアント更新時処理より後に来ること(テーマ再構築のため)
  watch(
    defaultStore.reactiveState.darkMode,
    (darkMode) => {
      applyTheme(
        darkMode
          ? ColdDeviceStorage.get("darkTheme")
          : ColdDeviceStorage.get("lightTheme")
      );
    },
    { immediate: miLocalStorage.getItem("theme") == null }
  );
  const darkTheme = computed(ColdDeviceStorage.makeGetterSetter("darkTheme"));
  const lightTheme = computed(ColdDeviceStorage.makeGetterSetter("lightTheme"));

  watch(darkTheme, (theme) => {
    if (defaultStore.state.darkMode) {
      applyTheme(theme);
    }
  });

  watch(lightTheme, (theme) => {
    if (!defaultStore.state.darkMode) {
      applyTheme(theme);
    }
  });

  //#region Sync dark mode
  if (ColdDeviceStorage.get("syncDeviceDarkMode")) {
    defaultStore.set("darkMode", isDeviceDarkmode());
  }

  window.matchMedia("(prefers-color-scheme: dark)").addListener((mql) => {
    if (ColdDeviceStorage.get("syncDeviceDarkMode")) {
      defaultStore.set("darkMode", mql.matches);
    }
  });
  //#endregion

  watch(
    defaultStore.reactiveState.useBlurEffectForModal,
    (v) => {
      document.documentElement.style.setProperty(
        "--modalBgFilter",
        v ? "blur(4px)" : "none"
      );
    },
    { immediate: true }
  );

  watch(
    defaultStore.reactiveState.useBlurEffect,
    (v) => {
      if (v) {
        document.documentElement.style.removeProperty("--blur");
      } else {
        document.documentElement.style.setProperty("--blur", "none");
      }
    },
    { immediate: true }
  );

  let reloadDialogShowing = false;
  stream.on("_disconnected_", async () => {
    if (defaultStore.state.serverDisconnectedBehavior === "reload") {
      location.reload();
    } else if (defaultStore.state.serverDisconnectedBehavior === "dialog") {
      if (reloadDialogShowing) return;
      reloadDialogShowing = true;
      const { canceled } = await confirm({
        type: "warning",
        title: i18n.ts.disconnectedFromServer,
        text: i18n.ts.reloadConfirm,
      });
      reloadDialogShowing = false;
      if (!canceled) {
        location.reload();
      }
    }
  });

  stream.on("emojiAdded", (emojiData) => {
    // TODO
    //store.commit('instance/set', );
  });

  for (const plugin of ColdDeviceStorage.get("plugins").filter(
    (p) => p.active
  )) {
    import("./plugin").then(({ install }) => {
      install(plugin);
    });
  }

  const now = new Date();
  const m = now.getMonth() + 1;
  const d = now.getDate();

  if ($i.birthday) {
    const bm = parseInt($i.birthday.split("-")[1]);
    const bd = parseInt($i.birthday.split("-")[2]);
    if (m === bm && d === bd) {
      claimAchievement("loggedInOnBirthday");
    }
  }

  if (m === 1 && d === 1) {
    claimAchievement("loggedInOnNewYearsDay");
  }

  if ($i.loggedInDays >= 3) claimAchievement("login3");
  if ($i.loggedInDays >= 7) claimAchievement("login7");
  if ($i.loggedInDays >= 15) claimAchievement("login15");
  if ($i.loggedInDays >= 30) claimAchievement("login30");
  if ($i.loggedInDays >= 60) claimAchievement("login60");
  if ($i.loggedInDays >= 100) claimAchievement("login100");
  if ($i.loggedInDays >= 200) claimAchievement("login200");
  if ($i.loggedInDays >= 300) claimAchievement("login300");
  if ($i.loggedInDays >= 400) claimAchievement("login400");
  if ($i.loggedInDays >= 500) claimAchievement("login500");
  if ($i.loggedInDays >= 600) claimAchievement("login600");
  if ($i.loggedInDays >= 700) claimAchievement("login700");
  if ($i.loggedInDays >= 800) claimAchievement("login800");
  if ($i.loggedInDays >= 900) claimAchievement("login900");
  if ($i.loggedInDays >= 1000) claimAchievement("login1000");

  if ($i.notesCount > 0) claimAchievement("notes1");
  if ($i.notesCount >= 10) claimAchievement("notes10");
  if ($i.notesCount >= 100) claimAchievement("notes100");
  if ($i.notesCount >= 500) claimAchievement("notes500");
  if ($i.notesCount >= 1000) claimAchievement("notes1000");
  if ($i.notesCount >= 5000) claimAchievement("notes5000");
  if ($i.notesCount >= 10000) claimAchievement("notes10000");
  if ($i.notesCount >= 20000) claimAchievement("notes20000");
  if ($i.notesCount >= 30000) claimAchievement("notes30000");
  if ($i.notesCount >= 40000) claimAchievement("notes40000");
  if ($i.notesCount >= 50000) claimAchievement("notes50000");
  if ($i.notesCount >= 60000) claimAchievement("notes60000");
  if ($i.notesCount >= 70000) claimAchievement("notes70000");
  if ($i.notesCount >= 80000) claimAchievement("notes80000");
  if ($i.notesCount >= 90000) claimAchievement("notes90000");
  if ($i.notesCount >= 100000) claimAchievement("notes100000");

  if ($i.followersCount > 0) claimAchievement("followers1");
  if ($i.followersCount >= 10) claimAchievement("followers10");
  if ($i.followersCount >= 50) claimAchievement("followers50");
  if ($i.followersCount >= 100) claimAchievement("followers100");
  if ($i.followersCount >= 300) claimAchievement("followers300");
  if ($i.followersCount >= 500) claimAchievement("followers500");
  if ($i.followersCount >= 1000) claimAchievement("followers1000");

  if (
    Date.now() - new Date($i.createdAt).getTime() >
    1000 * 60 * 60 * 24 * 365
  ) {
    claimAchievement("passedSinceAccountCreated1");
  }
  if (
    Date.now() - new Date($i.createdAt).getTime() >
    1000 * 60 * 60 * 24 * 365 * 2
  ) {
    claimAchievement("passedSinceAccountCreated2");
  }
  if (
    Date.now() - new Date($i.createdAt).getTime() >
    1000 * 60 * 60 * 24 * 365 * 3
  ) {
    claimAchievement("passedSinceAccountCreated3");
  }

  if (claimedAchievements.length >= 30) {
    claimAchievement("collectAchievements30");
  }

  window.setInterval(() => {
    if (Math.floor(Math.random() * 10000) === 0) {
      claimAchievement("justPlainLucky");
    }
  }, 1000 * 10);

  window.setTimeout(() => {
    claimAchievement("client30min");
  }, 1000 * 60 * 30);

  const lastUsed = miLocalStorage.getItem("lastUsed");
  if (lastUsed) {
    const lastUsedDate = parseInt(lastUsed, 10);
    // 二時間以上前なら
    if (Date.now() - lastUsedDate > 1000 * 60 * 60 * 2) {
      toast(
        i18n.t("welcomeBackWithName", {
          name: $i.name || $i.username,
        })
      );
    }
  }
  miLocalStorage.setItem("lastUsed", Date.now().toString());

  if ("Notification" in window) {
    // 許可を得ていなかったらリクエスト
    if (Notification.permission === "default") {
      Notification.requestPermission();
    }
  }

  const main = markRaw(stream.useChannel("main", null, "System"));

  // 自分の情報が更新されたとき
  main.on("meUpdated", (i) => {
    updateAccount(i);
  });

  main.on("readAllNotifications", () => {
    updateAccount({ hasUnreadNotification: false });
  });

  main.on("unreadNotification", () => {
    updateAccount({ hasUnreadNotification: true });
  });

  main.on("unreadMention", () => {
    updateAccount({ hasUnreadMentions: true });
  });

  main.on("readAllUnreadMentions", () => {
    updateAccount({ hasUnreadMentions: false });
  });

  main.on("unreadSpecifiedNote", () => {
    updateAccount({ hasUnreadSpecifiedNotes: true });
  });

  main.on("readAllUnreadSpecifiedNotes", () => {
    updateAccount({ hasUnreadSpecifiedNotes: false });
  });

  main.on("readAllMessagingMessages", () => {
    updateAccount({ hasUnreadMessagingMessage: false });
  });

  main.on("unreadMessagingMessage", () => {
    updateAccount({ hasUnreadMessagingMessage: true });
    sound.play("chatBg");
  });

  main.on("readAllAntennas", () => {
    updateAccount({ hasUnreadAntenna: false });
  });

  main.on("unreadAntenna", () => {
    updateAccount({ hasUnreadAntenna: true });
    sound.play("antenna");
  });

  main.on("readAllAnnouncements", () => {
    updateAccount({ hasUnreadAnnouncement: false });
  });

  main.on("readAllChannels", () => {
    updateAccount({ hasUnreadChannel: false });
  });

  main.on("unreadChannel", () => {
    updateAccount({ hasUnreadChannel: true });
    sound.play("channel");
  });

  // トークンが再生成されたとき
  // このままではMisskeyが利用できないので強制的にサインアウトさせる
  main.on("myTokenRegenerated", () => {
    signout();
  });

  if (storedDeviceInfo.platform == "web") return;
  OneSignal.setAppId(import.meta.env.VITE_ONE_SIGNAL_APP_ID);
  const deviceId = await Device.getId();
  OneSignal.setExternalUserId(deviceId.uuid);
  const res = await fetch(import.meta.env.VITE_NOTIFICATION_TOKEN_ENDPOINT, {
    method: "POST", // *GET, POST, PUT, DELETE, etc.
    mode: "cors", // no-cors, *cors, same-origin
    cache: "no-cache", // *default, no-cache, reload, force-cache, only-if-cached
    credentials: "same-origin", // include, *same-origin, omit
    headers: {
      "Content-Type": "application/json",
    },
    redirect: "follow", // manual, *follow, error
    referrerPolicy: "no-referrer", // no-referrer, *no-referrer-when-downgrade, origin, origin-when-cross-origin, same-origin, strict-origin, strict-origin-when-cross-origin, unsafe-url
    body: JSON.stringify({
      misskey_token: $i.token,
      device_id: deviceId.uuid,
      instance_url: $i.instanceUrl,
    }), // 本体のデータ型は "Content-Type" ヘッダーと一致させる必要があります
  }).catch((err) => {
    console.error(err);
    // throw err
  });
  console.info(res);
  OneSignal.setNotificationOpenedHandler(function (jsonData) {
    console.log("notificationOpenedCallback: " + JSON.stringify(jsonData));
  });
  // Prompts the user for notification permissions.
  //    * Since this shows a generic native prompt, we recommend instead using an In-App Message to prompt for notification permission (See step 7) to better communicate to your users what notifications they will get.
  OneSignal.promptForPushNotificationsWithUserResponse(function (accepted) {
    console.log("User accepted notifications: " + accepted);
  });
}
