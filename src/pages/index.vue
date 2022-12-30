<template>
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
