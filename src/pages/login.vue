<template>
  <div class="login">
    <div class="main" style="text-align: center">
      MissRiricaはMisskeyClientです。<br />
      今の所 misskey.io 専用です。<br />
      Webからアクセストークンを用意してログインしてください

      <div>
        <a href="https://riinswork.space/missRirica/privacy/"
          >プライバシーポリシー及び利用規約を読む</a
        >

        <div style="display: flex">
          <v-checkbox id="term" v-model="isTerm" />
          <label for="term" style="width: 100%"
            >MissRiricaクライアント<br />
            プライバシーポリシー及び<br />
            利用規約に同意する</label
          >
        </div>

        <label for="accessToken">アクセストークン</label>
        <v-text-field v-model="token" id="accessToken" />
        <div style="display: flex; justify-content: center">
          <v-btn :disabled="!isTerm" @click="login">ログイン</v-btn>
        </div>
      </div>
    </div>
  </div>
</template>

<script lang="ts">
import { noCredential } from "~/utils/apiClient";
import { useUser } from "~/store/useUser";

export default {
  setup() {
    const { $state: state, setToken } = useUser();
    return {
      state,
      setToken,
    };
  },
  components: {},
  data() {
    return {
      token: "",
      isTerm: false,
      instance: {},
    };
  },
  async mounted() {
    this.instance = await noCredential.request("meta", { detail: false });
  },
  methods: {
    async fetchInstance() {},
    login() {
      this.setToken(this.token, "https://misskey.io");
      this.$emit("login");
    },
  },
};
</script>

<style lang="scss" scoped>
.login {
  display: flex;
  background: rgb(134, 179, 0);
  height: 100%;
  align-items: center;

  .main {
    margin: 20px;
    padding: 1em;
    background-color: white;
    border-radius: 1em;
  }
}
</style>
