import { defineStore } from "pinia";

import { Pref } from "~/store/Preferences";
import { MisskeyClient } from "~/utils/apiClient";
import { APIClient } from "misskey-js/built/api";
import { entities, Stream } from "misskey-js";

export const userStore = defineStore("users", {
  state: () => ({
    account: {
      origin: "",
      accessToken: "",
    },
    $i: {} as entities.User,
    client: {} as MisskeyClient,
  }),
  getters: {
    api(): APIClient {
      return this.client.api;
    },
    stream(): MisskeyClient["stream"] {
      return this.client.stream;
    },
  },
  actions: {
    async init() {
      // ストレージからデータを復旧する処理
      this.account = Object.assign(this.account, await Pref.get("account"));
      this.client = new MisskeyClient(
        this.account.accessToken,
        this.account.origin
      );
      console.info("init end");
      return true;
    },
    // アカウントの実在を確認したい
    async verifyAccount(token: string, origin: string) {
      this.api = new MisskeyClient(token, origin).api;
      this.$i = await this.api.request("i").catch(() => {
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
