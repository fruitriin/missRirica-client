<template>
  <div class="statusbar" />
  <div class="container">
    <div class="content">
      <login v-if="!isLogin" />
      <timeline v-if="isLogin && inited" />
    </div>
  </div>
</template>

<script lang="ts">
import Login from "~/pages/login.vue";
import { userStore } from "~/store/UserStore";

export default {
  setup() {
    const { $state: state, init } = userStore();
    return {
      state,
      init,
    };
  },
  data() {
    return { inited: false };
  },
  components: { Login },
  async mounted() {
    await this.init();
    this.inited = true;
  },
  computed: {
    isLogin() {
      return this.state.account.accessToken;
    },
  },
};
</script>

<style lang="scss">
.statusbar {
  height: 20px;
  position: sticky;
  background-color: #ccc;
}
.container {
  width: 100%;
  min-width: 0;
  background: rgb(249, 249, 249);

  .content {
    padding: 24px;
    background: #fff;
  }
}
</style>

<style>
@tailwind base;
@tailwind components;
@tailwind utilities;
html,
#__nuxt,
body {
  margin: 0;
  padding: 0;
  font-size: 16px;
  height: 100dvh;
}
</style>
