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

export default defineComponent({
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
});
</script>

<style lang="scss" scoped>
.statusbar {
  height: 20px;
  position: sticky;
  background-color: #ccc;
}
.container {
  width: 100%;
  min-width: 0;
  background: black;
  padding: 24px;
  height: 100%;

  .content {
    overflow-y: auto;
    height: calc(100% - 24px);
    border-radius: 15px;
    background: #fff;
  }
}
</style>

<style>
html,
#__nuxt,
body {
  margin: 0;
  padding: 0;
  font-size: 16px;
  height: 100dvh;
}

:root {
  --header: white;
}
</style>
