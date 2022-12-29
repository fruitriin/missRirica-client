<template>
  <div class="statusbar"></div>
  <login v-if="!isLogin" />
  <timeline v-if="isLogin" />
</template>

<script lang="ts">
import Login from "~/pages/login.vue";
import { useUser } from "~/store/useUser";

export default {
  setup() {
    const { $state: state, init } = useUser();
    return {
      state,
      init,
    };
  },
  components: { Login },
  async mounted() {
    await this.init();
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
