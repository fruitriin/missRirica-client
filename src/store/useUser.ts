import { defineStore } from "pinia";

import { Pref } from "~/store/Preferences";
import { MisskeyClient } from "~/utils/apiClient";
import { APIClient } from "misskey-js/built/api";

export const useUser = defineStore("users", {
  state: () => ({
    account: {
      origin: "",
      accessToken: "",
    },
    api: {} as APIClient,
    stream: {} as MisskeyClient["stream"],
  }),
  getters: {},
  actions: {
    async init() {
      // ストレージからデータを復旧する処理
      this.account = Object.assign(this.account, await Pref.get("account"));
      const client = new MisskeyClient(
        this.account.accessToken,
        this.account.origin
      );
      this.api = client.api;
      this.stream = client.stream;
      console.info("init end");
    },
    // アカウントの実在を確認したい
    async verifyAccount(token: string, origin: string) {
      this.api = new MisskeyClient(token, origin).api;
      await this.api.request("i").catch(() => {
        throw new Error("アクセストークンが正しくありません");
      });
    },
    // トークンを保存するのは実在が確認できたときのみ
    async setToken(token: string, origin = "https://misskey.io") {
      await this.verifyAccount(token, origin);
      this.account.origin = origin;
      this.account.accessToken = token;
      Pref.set("account", this.account).then();
    },
  },
});
