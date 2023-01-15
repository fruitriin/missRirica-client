import { defineAsyncComponent, reactive } from "vue";
import * as misskey from "misskey-js";
import { showSuspendedDialog } from "./scripts/show-suspended-dialog";
import { i18n } from "./i18n";
import { del, get, set } from "@/scripts/idb-proxy";
import { waiting, api, popup, popupMenu, success, alert, apiGet } from "@/os";
import { unisonReload, reloadChannel } from "@/scripts/unison-reload";
import * as Misskey from "misskey-js";
import { instance } from "@/instance";


// アカウントデータがJSONでパースできないほど壊れてたら諦めて再設定

type Account = misskey.entities.MeDetailed;
let accountData = null
try {
   accountData = JSON.parse(localStorage.getItem("account"))
}catch (e) {
  localStorage.removeItem("account")
  window.location.reload()
}

if(accountData && accountData?.instanceUrl) accountData.instanceUrl = "https://misskey.io"

// TODO: 外部からはreadonlyに
export const $i = accountData
  ? reactive(accountData as Account)
  : null;

export const iAmModerator = $i != null && ($i.isAdmin || $i.isModerator);
export const iAmAdmin = $i != null && $i.isAdmin;

export async function signout() {
  waiting();
  localStorage.removeItem("account");

  await removeAccount($i.id);

  const accounts = await getAccounts();

  document.cookie = "igi=; path=/";

  if (accounts.length > 0) login(accounts[0].token, accounts[0].instanceUrl);
  else unisonReload("/");
}

export async function getAccounts(): Promise<
  { id: Account["id"]; token: Account["token"] , instanceUrl: string}[]
> {
  return (await get("accounts")) || [];
}

export async function addAccount(id: Account["id"], token: Account["token"], instanceUrl: string) {
  const accounts = await getAccounts();
  if (!accounts.some((x) => x.id === id)) {
    await set("accounts", accounts.concat([{ id, token , instanceUrl}]));
  }
}

export async function removeAccount(id: Account["id"]) {
  const accounts = await getAccounts();
  accounts.splice(
    accounts.findIndex((x) => x.id === id),
    1
  );

  if (accounts.length > 0) await set("accounts", accounts);
  else await del("accounts");
}

function fetchAccount(token: string, instanceUrl: string): Promise<Account & {instanceUrl: string}> {

  const apiClient = new Misskey.api.APIClient({
    origin: instanceUrl,
    credential: token,
  });
  return apiClient
    .request("i")
    .then((res) => {
      return {...res as Account, token,  instanceUrl};
    })
    .catch((err) => {
      if (err.id === "a8c724b3-6e9c-4b46-b1a8-bc3ed6258370") {
        showSuspendedDialog().then(() => {
          signout();
        });
      } else {
        alert({
          type: "error",
          title: i18n.ts.failedToFetchAccountInformation,
          text: JSON.stringify(err),
        })
      }
      return Promise.reject(err)
    });
}

export function updateAccount(accountData: Object) {
  for (const [key, value] of Object.entries(accountData)) {
    $i[key] = value;
  }
  localStorage.setItem("account", JSON.stringify($i));
}

export function refreshAccount() {
  return fetchAccount($i.token, $i.instanceUrl).then(updateAccount);
}

export async function login(token: Account["token"], instanceUrl: string,  redirect?: string) {
  if (_DEV_) console.log("logging as token ", token, instanceUrl);
  const me = await fetchAccount(token, instanceUrl)
  localStorage.setItem("account", JSON.stringify(me));
  localStorage.setItem("instance", JSON.stringify(await new Misskey.api.APIClient({origin: instanceUrl, credential: token}).request("meta")))
  document.cookie = `token=${token}; path=/; max-age=31536000`; // bull dashboardの認証とかで使う
  await addAccount(me.id, token, instanceUrl);

  if (redirect) {
    // 他のタブは再読み込みするだけ
    reloadChannel.postMessage(null);
    // このページはredirectで指定された先に移動
    location.href = redirect;
    return;
  }

  unisonReload();
}

export async function openAccountMenu(
  opts: {
    includeCurrentAccount?: boolean;
    withExtraOperation: boolean;
    active?: misskey.entities.UserDetailed["id"];
    onChoose?: (account: misskey.entities.UserDetailed) => void;
  },
  ev: MouseEvent
) {
  function showSigninDialog() {
    popup(
      defineAsyncComponent(() => import("@/components/MkSigninDialog.vue")),
      {},
      {
        done: (res) => {
          addAccount(res.id, res.i, res.instanceUrl);
          success();
        },
      },
      "closed"
    );
  }



  async function switchAccount(account: misskey.entities.UserDetailed) {
    const storedAccounts = await getAccounts();
    const acc = storedAccounts.find((x) => x.id === account.id);
     const{ token, instanceUrl } = acc
    switchAccountWithToken(token, instanceUrl);
  }

  function switchAccountWithToken(token: string, instanceUrl: string) {
    login(token, instanceUrl);
  }

  const storedAccounts = await getAccounts().then((accounts) =>
    accounts.filter((x) => x.id !== $i.id)
  );


  function createItem(account: misskey.entities.UserDetailed) {
    return {
      type: "user",
      user: account,
      active: opts.active != null ? opts.active === account.id : false,
      action: () => {
        if (opts.onChoose) {
          opts.onChoose(account);
        } else {
          switchAccount(account);
        }
      },
    };
  }

  const accountItemPromises = storedAccounts.map(
    (a) =>
      new Promise((res) => {
        const client = new Misskey.api.APIClient({origin: a.instanceUrl, credential: a.token})

        client.request("users/show", {
          userIds: [a.id]
        }).then((accounts) => {
          const account = accounts.find((x) => x.id === a.id);
          if (account == null) return res(null);

          client.request("meta").then(meta => {
            res(createItem({ ...account, host: meta.name}))
          })
        });
      })
  );

  if (opts.withExtraOperation) {
    popupMenu(
      [
        ...[
          {
            type: "link",
            text: i18n.ts.profile,
            to: `/@${$i.username}`,
            avatar: $i,
          },
          null,
          ...(opts.includeCurrentAccount ? [createItem($i)] : []),
          ...accountItemPromises,
          {
            type: "link",
            icon: "fas fa-users",
            text: i18n.ts.manageAccounts,
            to: "/settings/accounts",
          },
        ],
      ],
      ev.currentTarget ?? ev.target,
      {
        align: "left",
      }
    );
  } else {
    popupMenu(
      [
        ...(opts.includeCurrentAccount ? [createItem($i)] : []),
        ...accountItemPromises,
      ],
      ev.currentTarget ?? ev.target,
      {
        align: "left",
      }
    );
  }
}
